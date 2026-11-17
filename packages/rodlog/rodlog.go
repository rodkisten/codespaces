// Package rodlog implements streaming output enhancement with conservative tool detection.
package rodlog

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"
)

type Mode string

const (
	Raw       Mode = "raw"
	Enhance   Mode = "enhance"
	Transform Mode = "transform"
)

type Tool string

const (
	Auto       Tool = "auto"
	NPM        Tool = "npm"
	TypeScript Tool = "typescript"
	GCloud     Tool = "gcloud"
	Wrangler   Tool = "wrangler"
	Docker     Tool = "docker"
	Vitest     Tool = "vitest"
	NodeTest   Tool = "node-test"
	Generic    Tool = "generic"
)

type Level string

const (
	Info    Level = "info"
	Warning Level = "warning"
	Error   Level = "error"
	Success Level = "success"
)

type Event struct {
	Diagnostic *Diagnostic
	Sequence   uint64
	Tool       Tool
	Level      Level
	Text       string
}
type Options struct {
	Mode    Mode
	Tool    Tool
	Color   bool
	MaxLine int
}
type Renderer interface{ Render(Event) ([]byte, error) }
type Engine struct {
	Options  Options
	Renderer Renderer
}

var ansi = regexp.MustCompile("\x1b\\[[0-9;]*[A-Za-z]")
var patterns = map[Tool][]string{
	NPM:        {"npm ERR!", "npm warn", "npm error", "npm run", "npm notice"},
	TypeScript: {"error TS", "warning TS", "tsc ", ".tsx(", ".ts("},
	GCloud:     {"gcloud ", "ERROR: (gcloud", "WARNING: (gcloud", "Updated property", "Deploying container"},
	Wrangler:   {"wrangler ", "cloudflare", "workers.dev", "wrangler.toml", "wrangler.jsonc"},
	Docker:     {"docker ", "Step 1/", "=> [", "dockerfile:", "exporting layers", "writing image"},
	Vitest:     {"vitest ", "vitest run", "❯ ", "test files ", "tests  "},
	NodeTest:   {"node --test", "✖ tests ", "ℹ tests ", "✖ failing tests:"},
}

func Detect(s string) Tool {
	lower := strings.ToLower(s)
	for _, tool := range []Tool{TypeScript, Vitest, NodeTest, NPM, GCloud, Wrangler, Docker} {
		for _, token := range patterns[tool] {
			if strings.Contains(lower, strings.ToLower(token)) {
				return tool
			}
		}
	}
	return Generic
}
func Classify(s string) Level {
	lower := strings.ToLower(ansi.ReplaceAllString(s, ""))
	switch {
	case strings.Contains(lower, "error"), strings.Contains(lower, "npm err!"), strings.Contains(lower, "failed"), strings.Contains(lower, "fatal"), strings.Contains(lower, "✘"):
		return Error
	case strings.Contains(lower, "warn"), strings.Contains(lower, "deprecated"):
		return Warning
	case strings.Contains(lower, "success"), strings.Contains(lower, "done"), strings.Contains(lower, "✔"), strings.Contains(lower, "✓"):
		return Success
	default:
		return Info
	}
}
func New(opts Options) *Engine {
	if opts.Mode == "" {
		opts.Mode = Enhance
	}
	if opts.Tool == "" {
		opts.Tool = Auto
	}
	if opts.MaxLine <= 0 {
		opts.MaxLine = 1024 * 1024
	}
	return &Engine{Options: opts}
}

// Process consumes command output incrementally, preserving its original order.
// Raw mode copies bytes exactly. In other modes, each line is classified and
// optionally parsed into a structured diagnostic before being rendered.
// A renderer failure falls back to the original bytes, never hiding errors.
// Colored Transform mode deduplicates diagnostics and summarizes them at EOF.
func (e *Engine) Process(ctx context.Context, src io.Reader, dst io.Writer) error {
	if e.Options.Mode == Raw {
		_, err := io.Copy(dst, src)
		return err
	}
	reader := bufio.NewReaderSize(src, 32*1024)
	var seq uint64
	var current Tool = Generic
	counts := map[Level]int{Error: 0, Warning: 0}
	seen := map[string]bool{}
	grouped := map[string]map[Level]int{}
	lastGroup := ""
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		line, err := reader.ReadSlice('\n')
		if err == bufio.ErrBufferFull {
			// Long lines are emitted in bounded fragments, never silently truncated.
			err = nil
		}
		if len(line) > 0 {
			seq++
			text := string(line)
			if e.Options.Tool != Auto {
				current = e.Options.Tool
			} else if detected := Detect(text); detected != Generic {
				current = detected
			}
			event := Event{Sequence: seq, Tool: current, Level: Classify(text), Text: text}
			event.Diagnostic = ParseDiagnostic(current, text)
			if event.Diagnostic != nil {
				event.Level = event.Diagnostic.Level
				if e.Options.Mode == Transform && e.Renderer == nil && e.Options.Color {
					key := fmt.Sprintf("%s:%d:%d:%s:%s", event.Diagnostic.File, event.Diagnostic.Line, event.Diagnostic.Column, event.Diagnostic.Code, event.Diagnostic.Message)
					if seen[key] {
						continue
					}
					seen[key] = true
					counts[event.Level]++
					group := event.Diagnostic.File
					if group == "" {
						group = string(event.Diagnostic.Tool)
					}
					if grouped[group] == nil {
						grouped[group] = map[Level]int{}
					}
					grouped[group][event.Level]++
					if group != lastGroup {
						if _, writeErr := fmt.Fprintf(dst, "\n\x1b[1;36m▸ %s\x1b[0m\n", group); writeErr != nil {
							return writeErr
						}
						lastGroup = group
					}
				}
			}
			var out []byte
			var renderErr error
			if e.Renderer != nil {
				out, renderErr = e.Renderer.Render(event)
			} else {
				out = Render(event, e.Options)
			}
			if renderErr != nil {
				out = line
			}
			if _, writeErr := dst.Write(out); writeErr != nil {
				return fmt.Errorf("write output: %w", writeErr)
			}
		}
		if err == io.EOF {
			if e.Options.Mode == Transform && e.Renderer == nil && e.Options.Color && counts[Error]+counts[Warning] > 0 {
				groups := make([]string, 0, len(grouped))
				for name := range grouped {
					groups = append(groups, name)
				}
				sort.Strings(groups)
				for _, name := range groups {
					if _, writeErr := fmt.Fprintf(dst, "  \x1b[2m%s\x1b[0m  \x1b[31m%d errors\x1b[0m · \x1b[33m%d warnings\x1b[0m\n", name, grouped[name][Error], grouped[name][Warning]); writeErr != nil {
						return writeErr
					}
				}
				_, writeErr := fmt.Fprintf(dst, "\n\x1b[1mDiagnostics: \x1b[31m%d errors\x1b[0m, \x1b[33m%d warnings\x1b[0m\n", counts[Error], counts[Warning])
				return writeErr
			}
			return nil
		}
		if err != nil {
			return err
		}
	}
}

// Render applies presentation to a single event. Existing ANSI sequences win
// over our palette; unrecognized output is preserved rather than rewritten.
// Transform may replace recognized diagnostics with structured error cards.
func Render(ev Event, opts Options) []byte {
	if opts.Mode == Raw || !opts.Color {
		return []byte(ev.Text)
	}
	text := ev.Text
	if ev.Diagnostic != nil && opts.Mode == Transform && !ansi.MatchString(text) {
		return renderDiagnostic(ev.Diagnostic)
	}
	if ansi.MatchString(text) {
		return []byte(text)
	}
	// Structured payloads use Chroma; diagnostic lines retain semantic token highlighting.
	if opts.Mode == Transform {
		if table, ok := JSONTable(strings.TrimSpace(text), opts.Color); ok {
			return []byte(table)
		}
	}
	// Docker output gets contextual styling before generic severity coloring.
	// Do not rewrite an already-colored stream or fabricate a diagnostic.
	if ev.Tool == Docker {
		if colored, ok := highlightDocker(text); ok {
			return []byte(colored)
		}
	}
	if language := syntaxLanguage(text); language != "" {
		if colored, err := SyntaxHighlight(strings.TrimRight(text, "\r\n"), language); err == nil {
			return []byte(colored + text[len(strings.TrimRight(text, "\r\n")):])
		}
	}
	// Tool-aware spans take precedence over whole-line severity styling.
	highlighted := highlightLine(text)
	if highlighted != text {
		return []byte(highlighted)
	}
	color := ""
	switch ev.Level {
	case Error:
		color = "31"
	case Warning:
		color = "33"
	case Success:
		color = "32"
	}
	if color == "" {
		return []byte(text)
	}
	suffix := ""
	body := text
	if strings.HasSuffix(body, "\n") {
		body = strings.TrimSuffix(body, "\n")
		suffix = "\n"
	}
	if strings.HasSuffix(body, "\r") {
		body = strings.TrimSuffix(body, "\r")
		suffix = "\r" + suffix
	}
	return []byte("\x1b[" + color + "m" + body + "\x1b[0m" + suffix)
}
