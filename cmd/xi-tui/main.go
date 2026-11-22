package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
)

// ============================================================================
// @TODO: EXTRACT TO `internal/domain/github.go` (Domain Models & Messages)
// ============================================================================

// Em Go, structs substituem classes/interfaces de dados do TS.
// As struct tags (`json:"..."`) funcionam como metadados de runtime para o encoding/json
// mapear camelCase do JSON para PascalCase (campos exportados/públicos em Go começam com letra MAIÚSCULA).
type run struct {
	ID         int64  `json:"databaseId"`
	Name       string `json:"workflowName"`
	Branch     string `json:"headBranch"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
}

type job struct {
	ID         int64  `json:"databaseId"`
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	Steps      []step `json:"steps"`
}

type step struct {
	Name       string `json:"name"`
	Status     string `json:"status"`
	Conclusion string `json:"conclusion"`
	Number     int    `json:"number"`
}

// Em arquitetura Elm/Redux (usada pelo Bubble Tea), não existem callbacks diretos nem `await` na UI.
// Todo evento assíncrono retorna uma struct de "Mensagem" (equivalente a uma Redux Action `{ type, payload }`).
type loaded struct {
	runs    []run
	err     error
	cached  bool
	stale   bool
	request int
}

type tickMsg struct{}
type jobResponse struct {
	jobs    []job
	err     error
	request int
	id      int64
}
type logChunk struct {
	text    string
	done    bool
	err     error
	request int
	id      int64
}
type logReady struct {
	// `<-chan logChunk` é um canal (channel) SOMENTE LEITURA.
	// Pense nele como uma fila tipada thread-safe ou um AsyncIterable<logChunk> do JS.
	chunks  <-chan logChunk
	request int
}
type detail struct {
	value   string
	err     error
	cached  bool
	request int
	target  int64
	logs    bool
}

// ============================================================================
// @TODO: EXTRACT TO `internal/cache/disk_cache.go` (Storage & Pooling)
// ============================================================================

type cacheEntry struct {
	Saved time.Time `json:"saved"`
	// `json.RawMessage` é equivalente a guardar o JSON ainda como Buffer/string sem parsear,
	// permitindo adiar o `JSON.parse` até sabermos o tipo exato do destino (`dest`).
	Payload json.RawMessage `json:"payload"`
}

// Em Node, módulos são avaliados no top-level no import.
// Em Go, variáveis globais com funções anônimas auto-executáveis (`func() string { ... }()`)
// rodam uma única vez na inicialização do binário antes do `main()`.
var baseCacheDir = func() string {
	base, err := os.UserCacheDir()
	if err != nil {
		base = os.TempDir()
	}
	return filepath.Join(base, "xi", "github")
}()

// `sync.Pool` é um pool de objetos reutilizáveis thread-safe.
// Em Node, você alocaria `Buffer.alloc(8192)` toda vez e deixaria o V8 limpar depois.
// Em Go, reaproveitamos os mesmos slices de 8KB entre streams para aliviar o Garbage Collector.
var streamBufPool = sync.Pool{
	New: func() any {
		b := make([]byte, 8192)
		return &b
	},
}

func cachePath(key string) string {
	// `sha256.Sum256` retorna um array de tamanho fixo `[32]byte` na STACK (zero alocação na heap!).
	sum := sha256.Sum256([]byte(key))
	var hexBuf [24]byte // 12 bytes em hexadecimal ocupam exatamente 24 caracteres ASCII.
	hex.Encode(hexBuf[:], sum[:12])
	return filepath.Join(baseCacheDir, string(hexBuf[:])+".json")
}

// `dest any` (`any` é alias para `interface{}`) funciona como `unknown` no TypeScript,
// mas aqui `dest` precisa ser um PONTEIRO (`&runs`) para que `json.Unmarshal` consiga mutar a variável original.
func readCache(key string, dest any, ttl time.Duration) (bool, bool) {
	if ok, stale := hotCache.get(key, dest, ttl); ok {
		return true, stale
	}
	b, err := os.ReadFile(cachePath(key))
	if err != nil {
		return false, false
	}
	var entry cacheEntry
	if json.Unmarshal(b, &entry) != nil || entry.Saved.IsZero() || json.Unmarshal(entry.Payload, dest) != nil {
		return false, false
	}
	hotCache.put(key, dest)
	return true, time.Since(entry.Saved) > ttl
}

// Escrita atômica em disco: escreve em um arquivo temporário e depois faz `os.Rename`.
// Isso evita que outra leitura pegue um arquivo JSON cortado pela metade caso o processo morra no meio.
func writeCache(key string, value any) {
	hotCache.put(key, value)
	payload, err := json.Marshal(value)
	if err != nil {
		return
	}
	b, err := json.Marshal(cacheEntry{Saved: time.Now(), Payload: payload})
	if err != nil {
		return
	}
	if os.MkdirAll(baseCacheDir, 0700) != nil {
		return
	}
	tmp, err := os.CreateTemp(baseCacheDir, ".xi-*.tmp")
	if err != nil {
		return
	}
	tmpName := tmp.Name()
	// `defer` agenda uma função para rodar obrigatoriamente quando a função atual retornar
	// (similar a um bloco `finally` do JS, mas atrelado ao escopo da função inteira).
	defer os.Remove(tmpName)

	if tmp.Chmod(0600) != nil {
		tmp.Close()
		return
	}
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return
	}
	if tmp.Close() != nil {
		return
	}
	_ = os.Rename(tmpName, cachePath(key))
}

func cachedRuns(repo string) ([]run, bool, bool) {
	var runs []run
	ok, stale := readCache("runs:"+repo, &runs, 45*time.Second)
	return runs, ok, stale
}

func cachedDetail(repo string, id int64, logs bool) (string, bool, bool) {
	var value string
	key := "detail:" + repo + ":" + strconv.FormatInt(id, 10) + ":" + strconv.FormatBool(logs)
	ttl := 2 * time.Minute
	if logs {
		ttl = 10 * time.Minute
	}
	ok, stale := readCache(key, &value, ttl)
	return value, ok, stale
}

// ============================================================================
// @TODO: EXTRACT TO `internal/github/cli_client.go` (Process Execution & Streaming)
// ============================================================================

// `gh` é síncrono (bloqueante), mas em Go isso NÃO trava a aplicação porque cada `tea.Cmd`
// é executado pelo runtime do Bubble Tea dentro de sua própria Goroutine (thread leve gerenciada pelo Go).
func gh(args ...string) ([]byte, error) {
	// `context.WithTimeout` é o equivalente exato ao `AbortSignal.timeout(18000)` do Node.js.
	ctx, cancel := context.WithTimeout(context.Background(), 18*time.Second)
	defer cancel() // Libera o timer interno assim que a função terminar, evitando memory leak.

	cmd := exec.CommandContext(ctx, "gh", args...)
	out, err := cmd.CombinedOutput() // Equivale a `execFileSync` capturando stdout + stderr num Buffer (`[]byte`).
	if ctx.Err() != nil {
		return nil, fmt.Errorf("GitHub request timed out after 18s; cached data remains available")
	}
	if err != nil {
		return nil, fmt.Errorf("%s: %s", err, bytes.TrimSpace(out))
	}
	return out, nil
}

// Um `tea.Cmd` é simplesmente um tipo alias para `func() tea.Msg` (uma thunk function).
// O Bubble Tea executa essa função em background (goroutine) e injeta o `tea.Msg` retornado no `Update()`.
func fetchRuns(repo string, request int) tea.Cmd {
	return func() tea.Msg {
		out, err := gh("run", "list", "-R", repo, "--limit", "30", "--json", "databaseId,workflowName,headBranch,status,conclusion")
		if err != nil {
			return loaded{err: err, request: request}
		}
		var runs []run
		// `json.Unmarshal` preenche o slice `runs` por referência (`&runs`).
		if err = json.Unmarshal(out, &runs); err != nil {
			return loaded{err: err, request: request}
		}
		writeCache("runs:"+repo, runs)
		return loaded{runs: runs, request: request}
	}
}

func fetchJobs(repo string, id int64, request int) tea.Cmd {
	return func() tea.Msg {
		idStr := strconv.FormatInt(id, 10)
		out, err := gh("run", "view", idStr, "-R", repo, "--json", "jobs")
		if err != nil {
			return jobResponse{err: err, request: request, id: id}
		}
		// Struct anônima inline: útil para desembrulhar wrappers JSON pontuais sem poluir o pacote.
		var payload struct {
			Jobs []job `json:"jobs"`
		}
		err = json.Unmarshal(out, &payload)
		if err == nil {
			writeCache("jobs:"+repo+":"+idStr, payload.Jobs)
		}
		return jobResponse{jobs: payload.Jobs, err: err, request: request, id: id}
	}
}

func fetchDetail(repo string, id int64, logs bool, request int) tea.Cmd {
	return func() tea.Msg {
		idStr := strconv.FormatInt(id, 10)
		args := make([]string, 0, 6)
		args = append(args, "run", "view", idStr, "-R", repo)
		if logs {
			args = append(args, "--log-failed")
		}
		out, err := gh(args...)
		if err != nil {
			return detail{err: err, request: request, target: id, logs: logs}
		}
		strOut := string(out)
		writeCache("detail:"+repo+":"+idStr+":"+strconv.FormatBool(logs), strOut)
		return detail{value: strOut, request: request, target: id, logs: logs}
	}
}

// Como o Bubble Tea espera 1 mensagem por `tea.Cmd`, para fazer streaming contínuo usamos um padrão
// de "recursão assíncrona": `waitChunk` lê 1 item do channel -> entrega ao `Update()` -> `Update()` chama `waitChunk` de novo.
func waitChunk(ch <-chan logChunk) tea.Cmd {
	return func() tea.Msg {
		// `v, ok := <-ch` bloqueia esta goroutine até chegar um chunk ou o channel ser fechado (`ok == false`).
		v, ok := <-ch
		if !ok {
			return logChunk{done: true}
		}
		return v
	}
}

// Aqui temos um padrão produtor-consumidor clássico de Go:
// 1. Cria um channel bufferizado (`make(chan logChunk, 32)`).
// 2. Dispara uma goroutine (`go func()`) que lê o `stdout` do processo `gh` em streaming e empurra pedaços no channel.
// 3. Retorna imediatamente a referência do channel (`logReady`) para a UI começar a consumir.
func streamJobLogs(ctx context.Context, repo string, jobID, runID int64, request int) tea.Cmd {
	return func() tea.Msg {
		ch := make(chan logChunk, 32)
		go func() {
			// Quando essa goroutine sair (por erro, cancelamento ou fim do log), fecha o channel.
			defer close(ch)
			ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
			defer cancel()

			cmd := exec.CommandContext(
				ctx,
				"gh", "run", "view",
				strconv.FormatInt(runID, 10),
				"-R", repo,
				"--job", strconv.FormatInt(jobID, 10),
				"--log",
			)
			// `StdoutPipe` funciona como `child_process.spawn().stdout` (um `io.ReadCloser` / stream).
			pipe, err := cmd.StdoutPipe()
			if err != nil {
				ch <- logChunk{err: err, done: true, request: request, id: jobID}
				return
			}
			cmd.Stderr = cmd.Stdout
			if err = cmd.Start(); err != nil {
				ch <- logChunk{err: err, done: true, request: request, id: jobID}
				return
			}

			// Pega um buffer de 8KB do pool e garante sua devolução ao final da goroutine.
			bufPtr := streamBufPool.Get().(*[]byte)
			defer streamBufPool.Put(bufPtr)
			buf := *bufPtr

			for {
				n, e := pipe.Read(buf)
				if n > 0 {
					// `select` em Go funciona como `Promise.race` entre operações de canais:
					// tenta enviar o chunk para `ch`, mas se o usuário apertou Esc (`ctx.Done()`), aborta na hora sem travar!
					select {
					case ch <- logChunk{text: string(buf[:n]), request: request, id: jobID}:
					case <-ctx.Done():
						_ = cmd.Wait()
						return
					}
				}
				if e != nil {
					break // `io.EOF` ou erro de leitura encerra o loop.
				}
			}
			err = cmd.Wait()
			if ctx.Err() != nil {
				err = ctx.Err()
			}
			select {
			case ch <- logChunk{done: true, err: err, request: request, id: jobID}:
			case <-ctx.Done():
			}
		}()
		return logReady{chunks: ch, request: request}
	}
}

// ============================================================================
// @TODO: EXTRACT TO `internal/tui/styles.go` (Pre-allocated Lipgloss Styles)
// ============================================================================

var (
	stylePurple   = lipgloss.NewStyle().Foreground(lipgloss.Color("#B6A4FF")).Bold(true)
	styleMuted    = lipgloss.NewStyle().Foreground(lipgloss.Color("#9495A8"))
	styleGreen    = lipgloss.NewStyle().Foreground(lipgloss.Color("#65D6AE"))
	styleBorder   = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("#77718F")).Padding(1, 2)
	spinnerFrames = [4]string{"◐", "◓", "◑", "◒"}
)

// ============================================================================
// @TODO: EXTRACT TO `internal/tui/model.go` (State Management & Update Loop)
// ============================================================================

const (
	pageRuns   = 0
	pageDetail = 1
	pageJobs   = 2
	pageLogs   = 3

	maxLogBytes = 2 << 20 // Bitwise shift: 2 * 2^20 = 2MB.
	omitBanner  = "… older output omitted to keep memory bounded …\n"
)

// `model` é o estado único e central da aplicação (Single Source of Truth, igual ao `state` do React/Redux).
type model struct {
	repo         string
	runs         []run
	selected     int
	page         int
	busy         bool
	message      string
	detail       string
	detailLines  []string // Cache das linhas já quebradas por `\n` para o View() não refazer `split` a cada frame.
	width        int
	height       int
	frame        int
	request      int // Contador monotônico para invalidar respostas de requests antigos (evita race conditions).
	refreshing   bool
	fromCache    bool
	updated      time.Time
	detailCache  bool
	detailID     int64
	detailLogs   bool
	scroll       int
	jobs         []job
	jobSelected  int
	stepSelected int
	stepFocus    bool
	logFilter    string
	logJobID     int64
	logChannel   <-chan logChunk
	logCancel    context.CancelFunc // Equivalente ao `abortController.abort()` para matar o streaming de log.
	logStep      string
	searchMode   bool
	searchQuery  string
}

func spinner() tea.Cmd {
	// Agenda um timer único de 110ms (como `setTimeout`), que dispara `tickMsg` no `Update()`.
	return tea.Tick(110*time.Millisecond, func(time.Time) tea.Msg { return tickMsg{} })
}

func initial(repo string) model {
	m := model{repo: repo, width: 80, height: 24, request: 1}
	// Padrão Stale-While-Revalidate: se houver cache, já preenche o estado inicial para renderizar no frame 0,
	// mas marca `refreshing = true` para buscar dados novos em background.
	if runs, ok, _ := cachedRuns(repo); ok {
		m.runs = runs
		m.fromCache = true
		m.refreshing = true
	} else {
		m.busy = true
	}
	return m
}

// Note o receiver por ponteiro `(m *model)` aqui:
// Em Go, tudo é passado por VALOR (cópia). Como queremos mutar `m.detail` e `m.detailLines` in-place,
// usamos `*model` (ponteiro).
func (m *model) setDetail(val string) {
	m.detail = val
	if val == "" {
		m.detailLines = nil
	} else {
		m.detailLines = strings.Split(val, "\n")
	}
}

func (m *model) appendDetail(chunk string) {
	m.detail += chunk
	if len(m.detail) > maxLogBytes {
		// Mantém apenas os últimos 2MB de log na memória (sliding window).
		m.detail = omitBanner + m.detail[len(m.detail)-maxLogBytes:]
	}
	m.detailLines = strings.Split(m.detail, "\n")
}

// `Init` é o lifecycle hook inicial do Bubble Tea (como `useEffect(..., [])` no React).
// `tea.Batch` dispara múltiplos comandos em paralelo (como `Promise.all`, mas cada um entrega sua msg quando acabar).
func (m model) Init() tea.Cmd {
	return tea.Batch(fetchRuns(m.repo, m.request), spinner())
}

func (m model) stopLog() model {
	if m.logCancel != nil {
		m.logCancel() // Cancela o `context` da goroutine de streaming, matando o processo `gh` filho imediatamente.
		m.logCancel = nil
	}
	m.logChannel = nil
	return m
}

func (m model) startLog() (tea.Model, tea.Cmd) {
	m = m.stopLog()
	ctx, cancel := context.WithCancel(context.Background())
	m.logCancel = cancel
	return m, streamJobLogs(ctx, m.repo, m.logJobID, m.detailID, m.request)
}

func (m model) openJobs() (tea.Model, tea.Cmd) {
	if len(m.runs) == 0 {
		return m, nil
	}
	m.page = pageJobs
	m.request++
	m.busy = true
	m.refreshing = false
	m.message = ""
	m.jobSelected = 0
	m.stepSelected = 0
	m.stepFocus = false

	var jobs []job
	key := "jobs:" + m.repo + ":" + strconv.FormatInt(m.detailID, 10)
	if ok, _ := readCache(key, &jobs, 2*time.Minute); ok {
		m.jobs = jobs
		m.busy = false
		m.refreshing = true
	}
	return m, fetchJobs(m.repo, m.detailID, m.request)
}

func (m model) openDetail(logs bool) (tea.Model, tea.Cmd) {
	if len(m.runs) == 0 {
		return m, nil
	}
	id := m.runs[m.selected].ID
	m.page = pageDetail
	m.detailID = id
	m.detailLogs = logs
	m.scroll = 0
	m.request++

	if value, ok, _ := cachedDetail(m.repo, id, logs); ok {
		m.setDetail(value)
		m.detailCache = true
		m.busy = false
		m.refreshing = true
	} else {
		m.setDetail("")
		m.detailCache = false
		m.busy = true
		m.refreshing = false
	}
	return m, fetchDetail(m.repo, id, logs, m.request)
}

// `Update` é o reducer puro da aplicação: `(state, event) => (newState, nextAsyncCmd)`.
// Ele roda na main loop do Bubble Tea, recebendo tanto teclas do usuário (`tea.KeyPressMsg`)
// quanto retornos das goroutines (`loaded`, `logChunk`, etc).
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Type switch: verifica qual tipo concreto chegou dentro da interface `tea.Msg`.
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = v.Width
		m.height = v.Height

	case tickMsg:
		if m.busy || m.refreshing {
			m.frame++
		}
		// Reagenda o próximo tick (loop recursivo de 110ms para animação do spinner).
		return m, spinner()

	case loaded:
		// Guard clause: se o usuário mudou de tela ou pediu refresh antes dessa goroutine terminar, descarta!
		if v.request != m.request || m.page != pageRuns {
			break
		}
		m.busy = false
		m.refreshing = false
		if v.err != nil {
			m.message = v.err.Error()
		} else {
			m.runs = v.runs
			m.fromCache = false
			m.updated = time.Now()
			m.message = ""
			if m.selected >= len(m.runs) {
				m.selected = 0
			}
		}

	case jobResponse:
		if v.request != m.request || m.page != pageJobs || v.id != m.detailID {
			break
		}
		m.busy = false
		m.refreshing = false
		if v.err != nil {
			m.message = v.err.Error()
		} else {
			m.jobs = v.jobs
			m.message = ""
			m.updated = time.Now()
		}

	case logReady:
		if v.request != m.request || m.page != pageLogs {
			break
		}
		m.logChannel = v.chunks
		// Começa a escutar o primeiro pedaço de texto vindo do channel.
		return m, waitChunk(v.chunks)

	case logChunk:
		if v.request != m.request || m.page != pageLogs || v.id != m.logJobID {
			break
		}
		if v.text != "" {
			m.appendDetail(v.text)
		}
		if v.done {
			m.logCancel = nil
			m.busy = false
			m.refreshing = false
			if v.err != nil {
				m.message = v.err.Error()
			} else {
				writeCache("joblogs:"+m.repo+":"+strconv.FormatInt(m.logJobID, 10), m.detail)
			}
		} else {
			// Enquanto não terminar (`!v.done`), agenda a leitura do próximo chunk do channel.
			return m, waitChunk(m.logChannel)
		}

	case detail:
		if v.request != m.request || m.page != pageDetail || v.target != m.detailID || v.logs != m.detailLogs {
			break
		}
		m.busy = false
		m.refreshing = false
		if v.err != nil {
			m.message = v.err.Error()
		} else {
			m.setDetail(v.value)
			m.detailCache = false
			m.message = ""
			m.updated = time.Now()
		}

	case tea.KeyPressMsg:
		key := v.String()
		if m.searchMode {
			switch key {
			case "esc", "enter":
				m.searchMode = false
			case "backspace":
				if len(m.searchQuery) > 0 {
					m.searchQuery = m.searchQuery[:len(m.searchQuery)-1]
				}
			default:
				if len(key) == 1 && len(m.searchQuery) < 80 {
					m.searchQuery += key
				}
			}
			m.scroll = 0
			return m, nil
		}

		switch key {
		case "ctrl+c", "q":
			m = m.stopLog()
			return m, tea.Quit

		case "esc", "backspace", "left":
			m = m.stopLog()
			if m.page != pageRuns {
				switch m.page {
				case pageLogs:
					m.page = pageJobs
				case pageJobs:
					m.page = pageDetail
				default:
					m.page = pageRuns
				}
				m.scroll = 0
				m.request++
				m.busy = false
				m.refreshing = false
				m.message = ""
			} else {
				return m, tea.Quit
			}

		case "r":
			if m.busy || m.refreshing {
				break
			}
			m.request++
			m.message = ""
			m.refreshing = true
			switch m.page {
			case pageRuns:
				return m, fetchRuns(m.repo, m.request)
			case pageJobs:
				return m, fetchJobs(m.repo, m.detailID, m.request)
			case pageLogs:
				m.setDetail("")
				m.busy = true
				m.refreshing = false
				return m.startLog()
			default:
				return m, fetchDetail(m.repo, m.detailID, m.detailLogs, m.request)
			}

		case "up", "k":
			if m.page == pageRuns && m.selected > 0 {
				m.selected--
			} else if m.page == pageJobs && m.stepFocus && len(m.jobs) > 0 && m.stepSelected > 0 {
				m.stepSelected--
			} else if m.page == pageJobs && m.jobSelected > 0 {
				m.jobSelected--
				m.stepSelected = 0
			} else if (m.page == pageDetail || m.page == pageLogs) && m.scroll > 0 {
				m.scroll--
			}

		case "down", "j":
			if m.page == pageRuns && m.selected < len(m.runs)-1 {
				m.selected++
			} else if m.page == pageJobs && m.stepFocus && len(m.jobs) > 0 && m.stepSelected < len(m.jobs[m.jobSelected].Steps)-1 {
				m.stepSelected++
			} else if m.page == pageJobs && !m.stepFocus && m.jobSelected < len(m.jobs)-1 {
				m.jobSelected++
				m.stepSelected = 0
			} else if m.page == pageDetail || m.page == pageLogs {
				m.scroll++
			}

		case "/":
			m.searchMode = true
			m.searchQuery = ""
			m.scroll = 0

		case "f":
			if m.page == pageLogs {
				if m.logFilter == "" {
					m.logFilter = "error"
				} else {
					m.logFilter = ""
				}
				m.scroll = 0
			}

		case "tab":
			if m.page == pageJobs && len(m.jobs) > 0 && len(m.jobs[m.jobSelected].Steps) > 0 {
				m.stepFocus = !m.stepFocus
			}

		case "enter", "right":
			if m.page == pageRuns {
				return m.openDetail(false)
			}
			if m.page == pageDetail {
				return m.openJobs()
			}
			if m.page == pageJobs && len(m.jobs) > 0 {
				m.page = pageLogs
				m.request++
				m.logJobID = m.jobs[m.jobSelected].ID
				m.setDetail("")
				m.scroll = 0
				m.message = ""
				m.busy = true
				m.refreshing = false

				var cached string
				key := "joblogs:" + m.repo + ":" + strconv.FormatInt(m.logJobID, 10)
				if ok, _ := readCache(key, &cached, 10*time.Minute); ok {
					m.setDetail(cached)
					m.busy = false
					m.refreshing = true
				}
				m.logStep = ""
				if m.stepFocus && m.stepSelected < len(m.jobs[m.jobSelected].Steps) {
					m.logStep = m.jobs[m.jobSelected].Steps[m.stepSelected].Name
				}
				return m.startLog()
			}

		case "l":
			if m.page == pageDetail && !m.detailLogs {
				return m.openDetail(true)
			}

		case "J":
			if m.page == pageDetail {
				return m.openJobs()
			}

		case "d":
			if m.page == pageDetail && m.detailLogs {
				return m.openDetail(false)
			}

		case "home", "g":
			if m.page == pageDetail || m.page == pageLogs {
				m.scroll = 0
			}

		case "end", "G":
			if m.page == pageDetail || m.page == pageLogs {
				m.scroll = len(m.detailLines)
			}
		}
	}
	return m, nil
}

// ============================================================================
// @TODO: EXTRACT TO `internal/tui/view.go` (Zero-Overhead Viewport Rendering)
// ============================================================================

// Em Go, strings são imutáveis e indexadas por BYTES (não por caracteres UTF-16 como no JS).
// `containsFold` faz busca case-insensitive direto nos bytes sem criar novas strings com `strings.ToLower`.
func containsFold(s, substr string) bool {
	if len(substr) == 0 {
		return true
	}
	if len(substr) > len(s) {
		return false
	}
	// Converte o primeiro byte de A-Z para a-z somando 32 ('a' - 'A') na tabela ASCII.
	c0 := substr[0]
	if c0 >= 'A' && c0 <= 'Z' {
		c0 += 'a' - 'A'
	}
	limit := len(s) - len(substr)
	for i := 0; i <= limit; i++ {
		c := s[i]
		if c >= 'A' && c <= 'Z' {
			c += 'a' - 'A'
		}
		if c == c0 && strings.EqualFold(s[i:i+len(substr)], substr) {
			return true
		}
	}
	return false
}

// `View` é o renderizador declarativo (como o `render()` do React):
// Toda vez que `Update()` retorna um novo `model`, o Bubble Tea chama `View()` e faz o diff
// na tela do terminal para atualizar apenas o que mudou.
func (m model) View() tea.View {
	w := m.width - 4
	if w > 84 {
		w = 84
	}
	if w < 28 {
		w = 28
	}

	// `strings.Builder` é o jeito performático de concatenar strings em Go sem criar dezenas de
	// strings intermediárias descartáveis (similar ao `Array.join('')` em JS antigo).
	var body strings.Builder
	body.Grow(4096) // Pré-aloca 4KB de capacidade inicial de uma só vez.

	body.WriteString(stylePurple.Render("⚡ xi  /  GitHub Actions") + "\n")
	body.WriteString(styleMuted.Render(m.repo) + "\n\n")

	if m.busy || m.refreshing {
		state := "Loading"
		if m.refreshing {
			state = "Syncing"
		}
		// `m.frame & 3` é um truque bitwise equivalente a `m.frame % 4` (pois 4 é potência de 2).
		body.WriteString(stylePurple.Render(spinnerFrames[m.frame&3]+" "+state+" GitHub data…") + "\n")
	}
	if (m.page == pageRuns && m.fromCache) || (m.page == pageDetail && m.detailCache) {
		body.WriteString(styleMuted.Render("⚡ Instant cache · refreshing in background") + "\n")
	}
	if m.message != "" {
		body.WriteString("⚠ " + m.message + "\n")
	}
	if !m.updated.IsZero() && !m.refreshing && !m.busy {
		// Curiosidade do Go: formatação de datas não usa `HH:mm:ss`, mas sim a data de referência
		// `Mon Jan 2 15:04:05 MST 2006` (1-2-3-4-5-6-7).
		body.WriteString(styleMuted.Render("✓ Synced "+m.updated.Format("15:04:05")) + "\n")
	}

	switch m.page {
	case pageRuns:
		body.WriteString(stylePurple.Render("WORKFLOW RUNS") + "\n")
		if len(m.runs) == 0 && !m.busy {
			body.WriteString("No runs found.\n")
		}
		if m.searchQuery != "" {
			body.WriteString(styleMuted.Render("Search: "+m.searchQuery) + "\n")
		}
		// Virtualização de lista (windowing): calcula apenas a fatia visível na altura do terminal.
		max := m.height - 11
		if max < 3 {
			max = 3
		}
		start := 0
		if m.selected >= max {
			start = m.selected - max + 1
		}
		shown := 0
		var idBuf [20]byte // Buffer na stack para formatar int64 sem alocar string na heap.
		for i := start; i < len(m.runs) && shown < max; i++ {
			r := m.runs[i]
			if m.searchQuery != "" {
				idBytes := strconv.AppendInt(idBuf[:0], r.ID, 10)
				if !containsFold(r.Name, m.searchQuery) &&
					!containsFold(r.Branch, m.searchQuery) &&
					!containsFold(string(idBytes), m.searchQuery) {
					continue
				}
			}
			shown++
			cursor := "  "
			if i == m.selected {
				cursor = "❯ "
			}
			state := r.Conclusion
			if state == "" {
				state = r.Status
			}
			label := cursor + state + "  " + r.Name + "  ·  " + r.Branch
			if i == m.selected {
				body.WriteString(stylePurple.Render(label))
			} else if state == "success" {
				body.WriteString(styleGreen.Render(label))
			} else {
				body.WriteString(label)
			}
			body.WriteByte('\n')
		}

	case pageJobs:
		body.WriteString(stylePurple.Render("JOBS & STEPS") + "\n")
		max := m.height - 12
		if max < 3 {
			max = 3
		}
		start := 0
		if m.jobSelected >= max {
			start = m.jobSelected - max + 1
		}
		for i := start; i < len(m.jobs) && i < start+max; i++ {
			j := m.jobs[i]
			if m.searchQuery != "" && !containsFold(j.Name, m.searchQuery) {
				continue
			}
			prefix := "  "
			if i == m.jobSelected {
				prefix = "❯ "
			}
			body.WriteString(prefix + j.Conclusion + "  " + j.Name + "  (" + strconv.Itoa(len(j.Steps)) + " steps)\n")
		}
		if len(m.jobs) == 0 && !m.busy {
			body.WriteString("No jobs available.\n")
		}
		if len(m.jobs) > 0 {
			if m.searchQuery != "" {
				body.WriteString(styleMuted.Render("Search: "+m.searchQuery) + "\n")
			}
			body.WriteString(styleMuted.Render("Tab switches focus between jobs and steps") + "\n")
			steps := m.jobs[m.jobSelected].Steps
			room := m.height - 14 - max
			if room < 2 {
				room = 2
			}
			startStep := 0
			if m.stepSelected >= room {
				startStep = m.stepSelected - room + 1
			}
			for i := startStep; i < len(steps) && i < startStep+room; i++ {
				s := steps[i]
				prefix := "  "
				if m.stepFocus && i == m.stepSelected {
					prefix = "❯ "
				}
				line := prefix + strconv.Itoa(s.Number) + " · " + s.Name + " · " + s.Conclusion
				if m.stepFocus && i == m.stepSelected {
					body.WriteString(stylePurple.Render(line) + "\n")
				} else {
					body.WriteString(styleMuted.Render(line) + "\n")
				}
			}
		}

	default:
		body.WriteString(stylePurple.Render("RUN DETAILS / COMMAND OUTPUT") + "\n")
		if m.page == pageLogs {
			if m.logStep != "" {
				body.WriteString(stylePurple.Render("STEP: "+m.logStep) + "\n")
			}
			cmdHint := "❯ gh run view " + strconv.FormatInt(m.detailID, 10) + " --job " + strconv.FormatInt(m.logJobID, 10) + " --log"
			body.WriteString(styleMuted.Render(cmdHint) + "\n")
			if m.logFilter != "" {
				body.WriteString(stylePurple.Render("FILTER: "+m.logFilter) + "\n")
			} else {
				body.WriteByte('\n')
			}
		} else if len(m.runs) > 0 {
			cmdHint := "❯ gh run view " + strconv.FormatInt(m.runs[m.selected].ID, 10) + " -R " + m.repo
			body.WriteString(styleMuted.Render(cmdHint) + "\n\n")
		}

		lines := m.detailLines
		hasLogFilter := m.page == pageLogs && (m.logFilter != "" || m.logStep != "")
		hasSearch := m.searchQuery != ""

		// Passada única de filtragem sobre as linhas pré-quebradas.
		if hasLogFilter || hasSearch {
			filtered := make([]string, 0, len(lines)/4)
			for _, line := range lines {
				if hasLogFilter {
					if m.logFilter != "" && !containsFold(line, m.logFilter) {
						continue
					}
					if m.logStep != "" && !containsFold(line, m.logStep) {
						continue
					}
				}
				if hasSearch && !containsFold(line, m.searchQuery) {
					continue
				}
				filtered = append(filtered, line)
			}
			lines = filtered
		}

		max := m.height - 13
		if max < 3 {
			max = 3
		}
		maxScroll := len(lines) - max
		if maxScroll < 0 {
			maxScroll = 0
		}
		if m.scroll > maxScroll {
			m.scroll = maxScroll
		}
		if m.scroll < 0 {
			m.scroll = 0
		}
		if len(lines) > 0 {
			end := m.scroll + max
			if end > len(lines) {
				end = len(lines)
			}
			// Slicing `lines[m.scroll:end]` em Go é O(1) e não copia os elementos, apenas cria um ponteiro de janela.
			for _, line := range lines[m.scroll:end] {
				body.WriteString(line)
				body.WriteByte('\n')
			}
		}
	}

	if m.searchMode {
		body.WriteString("\n" + stylePurple.Render("⌕ Search: "+m.searchQuery+"▏") + "\n")
	}
	body.WriteString("\n" + styleMuted.Render("← Esc Back  ↑↓ Scroll  Enter Open  Tab Steps  F Errors  L Logs  D Details  R Refresh  Q Quit"))

	v := tea.NewView(styleBorder.Width(w).Render(body.String()))
	v.AltScreen = true // Usa o buffer alternativo do terminal (igual ao `vim` ou `htop`), restaurando o terminal ao sair.
	return v
}

func main() {
	// `os.Args[0]` é o caminho do próprio executável (como `process.argv[1]` no Node).
	repo := "rodkisten/codespaces"
	if len(os.Args) > 1 {
		repo = os.Args[1]
	}
	// Inicia o event loop bloqueante do Bubble Tea até que `tea.Quit` seja retornado por `Update()`.
	p := tea.NewProgram(initial(repo))
	if _, err := p.Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
