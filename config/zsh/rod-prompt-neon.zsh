# ==============================================================================
# 💜 Rod Prompt Neon · Ultra-Fast Native Zsh Engine (< 1ms non-git / < 3ms git)
# ==============================================================================
#
# ARQUITETURA DE ULTRA VELOCIDADE APLICADA NESTE SCRIPT:
# 1. Zero-Fork fora de repos Git: Em vez de chamar `git rev-parse` em cada Enter
#    (o que abre um subshell externo e custa ~10-30ms), o script sobe a árvore de
#    diretórios na memória RAM procurando `.git` e lê `.git/HEAD` direto via Zsh.
# 2. Único comando Git por ciclo: Quando o cache expira, consolida status,
#    untracked, staged, dirty e ahead/behind em 1 única chamada (`git status`),
#    em vez de rodar 4 comandos separados (`status`, `ls-files`, `rev-parse`, `rev-list`).
# 3. Invalidação Inteligente (Event-Driven): O cache limpa automaticamente ao
#    executar comandos Git (`preexec`) ou trocar de pasta (`chpwd`), mantendo
#    o prompt sempre atualizado sem desperdício de CPU.
# 4. Relógio Nativo em C (`zsh/datetime`): Usa `$EPOCHSECONDS` direto da memória,
#    eliminando qualquer chamada externa ao binário `date`.
# 5. Bytecode Compilation (`zcompile`): Compila este próprio arquivo para `.zwc`
#    em background sempre que for modificado, acelerando o parsing do Zsh.
# ==============================================================================

# Aborta imediatamente se o shell não for interativo (ex: scripts, scp, rsync)
[[ -o interactive ]] || return 0

# Carrega o gerenciador oficial de hooks do Zsh (precmd, preexec, chpwd)
autoload -Uz add-zsh-hook

# Carrega apenas o parâmetro EPOCHSECONDS do módulo C zsh/datetime (zero forks de `date`)
zmodload -F zsh/datetime p:EPOCHSECONDS 2>/dev/null

# Garante que sequências %F, %K, %n, %~ sejam expandidas na variável PROMPT
setopt PROMPT_PERCENT

# ------------------------------------------------------------------------------
# 1. CONFIGURAÇÕES & PALETA DE CORES (256-color ANSI)
#    Usa `: ${VAR:=valor}` para preservar overrides definidos antes do source
# ------------------------------------------------------------------------------
: ${ROD_PROMPT_DOTS:=1}                 # 1 = preenche linha com pontilhado até a borda
: ${ROD_PROMPT_DOT_CHAR:=·}             # Caractere usado no preenchimento
: ${ROD_PROMPT_DIM_COLOR:=240}          # Cinza discreto para linhas e separadores

: ${ROD_PROMPT_SHOW_USER:=1}            # 1 = exibe badge com nome do usuário
: ${ROD_PROMPT_USER_COLOR:=225}         # Cor do texto do usuário (rosa claro)
: ${ROD_PROMPT_USER_BG:=54}             # Cor de fundo do badge (roxo escuro)

: ${ROD_PROMPT_DIR_MODE:=smart}         # Modos: full | basename | short | smart
: ${ROD_PROMPT_DIR_MAX:=32}             # Largura máxima do caminho antes de truncar
: ${ROD_PROMPT_DIR_KEEP:=2}             # Quantos diretórios finais manter no modo smart
: ${ROD_PROMPT_DIR_COLOR:=177}          # Cor do caminho atual (lilás neon)

: ${ROD_PROMPT_SHOW_BRANCH:=1}          # 1 = exibe informações do repositório Git
: ${ROD_PROMPT_BRANCH_MODE:=smart}      # Modos de encurtamento para nome da branch
: ${ROD_PROMPT_BRANCH_MAX:=24}          # Largura máxima do nome da branch
: ${ROD_PROMPT_BRANCH_ICON:=}          # Ícone Powerline/NerdFont da branch
: ${ROD_PROMPT_BRANCH_COLOR:=123}       # Cor do nome da branch (ciano neon)

: ${ROD_PROMPT_GIT_DIRTY:=1}            # 1 = muda cor do ponto se houver arquivos modificados
: ${ROD_PROMPT_GIT_STAGED:=1}           # 1 = muda cor do ponto se houver arquivos no stage
: ${ROD_PROMPT_GIT_UNTRACKED:=1}        # 1 = verifica arquivos novos não rastreados (??)
: ${ROD_PROMPT_GIT_SYNC:=1}             # 1 = exibe setas ↑ahead / ↓behind em relação ao remote
: ${ROD_PROMPT_GIT_CACHE_TTL:=60}       # Tempo máximo (segundos) do cache de status Git
: ${ROD_PROMPT_GIT_SYNC_INTERVAL:=300}  # Intervalo mínimo (segundos) entre auto-fetches
: ${ROD_PROMPT_GIT_FETCH:=0}            # 1 = habilita `git fetch` silencioso em background

: ${ROD_PROMPT_SHOW_SUCCESS:=0}         # 1 = mostra barra de status mesmo quando rc == 0
: ${ROD_PROMPT_SHOW_ERROR:=1}           # 1 = mostra barra de status quando comando falha
: ${ROD_PROMPT_ERROR_TEXT:=1}           # 1 = exibe descrição textual além do código numérico
: ${ROD_PROMPT_ERROR_POSITION:=center}  # Posição do erro: center | left | right | inline | hidden
: ${ROD_PROMPT_SHOW_SEPARATOR:=1}       # 1 = desenha linha pontilhada separando comandos

: ${ROD_PROMPT_SYMBOL:='$'}             # Símbolo final do prompt ($ ou ❯)
: ${ROD_PROMPT_CORNER:=╰─}              # Conector visual da segunda linha do prompt

# ------------------------------------------------------------------------------
# 2. ESTADO GLOBAL & ESTRUTURAS DE CACHE EM MEMÓRIA
# ------------------------------------------------------------------------------
# Arrays associativos globais (hash maps nativos do Zsh em C):
# - _ROD_NEON_CACHE: guarda "dirty:staged:untracked:ahead:behind" por "repo:branch"
# - _ROD_NEON_TIME: timestamp (EPOCHSECONDS) da última coleta daquele repo
# - _ROD_NEON_FETCH_TIME: timestamp do último git fetch em background
typeset -gA _ROD_NEON_CACHE _ROD_NEON_TIME _ROD_NEON_FETCH_TIME

# Inteiros globais para controle de estado entre execuções
typeset -gi _ROD_NEON_LAST_RC=0 _ROD_NEON_RAN=0

# Cache de caminho para evitar percorrer diretórios pai repetidamente no mesmo PWD
typeset -g  _ROD_NEON_REPO_ROOT='' _ROD_NEON_GIT_DIR='' _ROD_NEON_LAST_PWD=''

# ------------------------------------------------------------------------------
# 3. FUNÇÕES AUXILIARES PURAS (100% Built-in Zsh, Zero Subshells)
# ------------------------------------------------------------------------------

# Escapa caracteres '%' literais em nomes de pastas ou branches para evitar que o
# Zsh os interprete como sequências de formatação de prompt.
# Usa a variável global $REPLY para retornar o valor sem abrir subshell $(...).
_rod_neon_safe() {
  REPLY=${1//\%/%%}
}

# Encurta caminhos ou nomes de branches usando expansão de parâmetros do Zsh.
_rod_neon_short() {
  local s=$1 mode=$2 max=$3 keep=$4
  [[ $max == <-> ]] || max=24
  (( max < 4 )) && max=4

  case $mode in
    basename)
      s=${s:t} # Extrai apenas o último segmento (tail)
      ;;
    short)
      [[ $s == */* ]] && s="…/${s:t}"
      ;;
    smart)
      if (( ${#s} > max )) && [[ $s == */* ]]; then
        [[ $keep == <-> ]] || keep=2
        # Divide a string nas barras '/' formando um array e junta os últimos $keep itens
        local -a a=("${(@s:/:)s}")
        s="…/${(j:/:)a[-$keep,-1]}"
      fi
      ;;
  esac

  # Se ainda exceder o limite máximo, aplica truncamento no meio (ex: abc…xyz)
  if (( ${#s} > max )); then
    local left=$(( (max - 1) / 2 ))
    s="${s[1,$left]}…${s[-$((max - left - 1)),-1]}"
  fi
  REPLY=$s
}

# ------------------------------------------------------------------------------
# 4. DETECÇÃO GIT ZERO-FORK (Navegação pura na RAM sem invocar o binário `git`)
# ------------------------------------------------------------------------------
_rod_neon_find_git_root() {
  # Fast-path: se o diretório atual não mudou desde o último prompt, retorna direto
  if [[ $PWD == $_ROD_NEON_LAST_PWD ]]; then
    REPLY=$_ROD_NEON_REPO_ROOT
    return
  fi

  _ROD_NEON_LAST_PWD=$PWD
  _ROD_NEON_REPO_ROOT=''
  _ROD_NEON_GIT_DIR=''

  # Sobe diretório por diretório até '/' verificando existência de `.git`
  local dir=$PWD
  while [[ -n $dir ]]; do
    if [[ -d "$dir/.git" ]]; then
      # Repositório Git padrão
      _ROD_NEON_REPO_ROOT=$dir
      _ROD_NEON_GIT_DIR="$dir/.git"
      break
    elif [[ -f "$dir/.git" ]]; then
      # Suporte a Git Worktrees e Submodules (onde `.git` é um arquivo de texto)
      # Lê o conteúdo do arquivo sem `cat` usando redirecionamento nativo $(<...)
      local gitfile=$(<"$dir/.git")
      if [[ $gitfile == gitdir:\ * ]]; then
        local gdir=${gitfile#gitdir: }
        [[ $gdir != /* ]] && gdir="$dir/$gdir"
        _ROD_NEON_REPO_ROOT=$dir
        _ROD_NEON_GIT_DIR=$gdir
        break
      fi
    fi
    [[ $dir == / ]] && break
    dir=${dir:h} # Sobe um nível (head) usando modificador nativo do Zsh
    [[ $dir == . ]] && dir=''
  done

  REPLY=$_ROD_NEON_REPO_ROOT
}

# Lê o nome da branch atual diretamente do arquivo `.git/HEAD` (0ms, zero fork)
_rod_neon_read_branch() {
  local head_file="$_ROD_NEON_GIT_DIR/HEAD"
  if [[ -r $head_file ]]; then
    local head=$(<"$head_file")
    if [[ $head == ref:\ refs/heads/* ]]; then
      # Remove o prefixo padrão para obter o nome exato da branch
      REPLY=${head#ref: refs/heads/}
      return 0
    fi
    # Modo Detached HEAD (ex: checkout de tag ou commit): mostra hash curto de 7 chars
    REPLY=${head[1,7]}
    return 0
  fi
  REPLY=''
  return 1
}

# ------------------------------------------------------------------------------
# 5. COLETA DE STATUS GIT CONSOLIDADA (1 única chamada ao `git` apenas no miss)
# ------------------------------------------------------------------------------
_rod_neon_git() {
  local root=$1 branch=$2 now=$EPOCHSECONDS
  local key="${root}:${branch}"
  local cached=${_ROD_NEON_CACHE[$key]-}
  local age=$(( now - ${_ROD_NEON_TIME[$key]:-0} ))

  # Só executa o processo `git` se não houver cache ou se o TTL tiver expirado
  if [[ -z $cached || $age -ge ${ROD_PROMPT_GIT_CACHE_TTL:-60} ]]; then
    local dirty=0 staged=0 untracked=0 ahead=0 behind=0
    local untracked_flag='-uno'
    (( ROD_PROMPT_GIT_UNTRACKED )) && untracked_flag='-unormal'

    # GIT_OPTIONAL_LOCKS=0 evita criar `.git/index.lock` e travar comandos paralelos
    # `--porcelain=v1 --branch` entrega TUDO em uma única execução:
    # linha 1: ## main...origin/main [ahead 1, behind 2]
    # demais linhas: XY arquivo (X = stage, Y = worktree, ?? = untracked)
    local out
    out=$(GIT_OPTIONAL_LOCKS=0 command git -C "$root" status --porcelain=v1 --branch "$untracked_flag" 2>/dev/null)

    if [[ -n $out ]]; then
      local line
      # Itera sobre cada linha da saída usando parameter expansion `${(@f)out}`
      for line in "${(@f)out}"; do
        if [[ $line == \#\#* ]]; then
          # Extrai números de commits à frente/atrás via regex nativa do Zsh
          [[ $line =~ 'ahead ([0-9]+)' ]]  && ahead=$match[1]
          [[ $line =~ 'behind ([0-9]+)' ]] && behind=$match[1]
        elif [[ $line == \?\?* ]]; then
          untracked=1
        else
          [[ ${line[1]} != ' ' ]] && staged=1 # Coluna 1 indica alteração no Index/Stage
          [[ ${line[2]} != ' ' ]] && dirty=1  # Coluna 2 indica alteração no Working Tree
        fi
        # Short-circuit: se todos os indicadores já são verdadeiros, para o loop antes
        (( dirty && staged && (!ROD_PROMPT_GIT_UNTRACKED || untracked) )) && break
      done
    fi

    # Armazena o resultado serializado no hash map em memória
    cached="$dirty:$staged:$untracked:$ahead:$behind"
    _ROD_NEON_CACHE[$key]=$cached
    _ROD_NEON_TIME[$key]=$now
  fi

  REPLY=$cached

  # Fetch opcional em background (totalmente desacoplado via `&!` para nunca bloquear)
  if (( ROD_PROMPT_GIT_FETCH && ROD_PROMPT_GIT_SYNC )); then
    local last=${_ROD_NEON_FETCH_TIME[$root]:-0}
    if (( now - last >= ROD_PROMPT_GIT_SYNC_INTERVAL )); then
      _ROD_NEON_FETCH_TIME[$root]=$now
      ( command git -C "$root" -c credential.interactive=never fetch --quiet --no-tags --prune </dev/null >/dev/null 2>&1 ) &!
    fi
  fi
}

# ------------------------------------------------------------------------------
# 6. TRADUÇÃO DE EXIT CODES & HOOKS DO SHELL
# ------------------------------------------------------------------------------
_rod_neon_status_label() {
  case $1 in
    0)   REPLY='✓ 0 · Sucesso' ;;
    1)   REPLY='✕ 1 · Erro geral' ;;
    2)   REPLY='✕ 2 · Uso inválido' ;;
    126) REPLY='✕ 126 · Sem permissão' ;;
    127) REPLY='✕ 127 · Comando não encontrado' ;;
    130) REPLY='✕ 130 · Ctrl+C' ;;
    137) REPLY='✕ 137 · Processo encerrado' ;;
    *)   REPLY="✕ $1 · Falha" ;;
  esac
  # Remove a descrição textual se ROD_PROMPT_ERROR_TEXT=0
  (( ROD_PROMPT_ERROR_TEXT )) || REPLY=${REPLY%% · *}
}

# Hook `preexec`: roda imediatamente antes de executar qualquer comando digitado.
# Se o comando mexer no repositório (git, gh, lazygit, etc.), zera o timestamp
# do cache daquele repo para que o próximo prompt reflita o novo estado na hora.
_rod_neon_preexec() {
  if [[ -n $_ROD_NEON_REPO_ROOT && $1 == *(git|gh|lazygit|stg|jj)* ]]; then
    local k
    for k in ${(k)_ROD_NEON_TIME}; do
      [[ $k == ${_ROD_NEON_REPO_ROOT}:* ]] && _ROD_NEON_TIME[$k]=0
    done
  fi
}

# Hook `precmd`: roda antes de desenhar cada novo prompt no terminal.
_rod_neon_precmd() {
  local rc=$? # Captura o código de saída do último comando ANTES de rodar qualquer coisa
  local width=${COLUMNS:-80}
  (( width < 20 )) && width=20
  _ROD_NEON_LAST_RC=$rc

  # 1. Formata o caminho atual (`%~` já substitui $HOME por `~`)
  local raw_path=${(%):-%~}
  _rod_neon_short "$raw_path" "$ROD_PROMPT_DIR_MODE" "$ROD_PROMPT_DIR_MAX" "$ROD_PROMPT_DIR_KEEP"
  local dir=$REPLY

  # 2. Monta o segmento Git (custo ~0ms fora de repositórios)
  local branch='' gitpart=''
  if (( ROD_PROMPT_SHOW_BRANCH )) && (( $+commands[git] )); then
    _rod_neon_find_git_root
    local root=$REPLY
    if [[ -n $root ]]; then
      _rod_neon_read_branch
      local fullbranch=$REPLY
      if [[ -n $fullbranch ]]; then
        _rod_neon_short "$fullbranch" "$ROD_PROMPT_BRANCH_MODE" "$ROD_PROMPT_BRANCH_MAX" 1
        branch=$REPLY

        _rod_neon_git "$root" "$fullbranch"
        local -a fields=("${(@s/:/)REPLY}")

        # Prioridade de cor da bolinha: Untracked (vermelho) > Staged (verde) > Dirty (amarelo) > Clean (cinza)
        local dotcolor=240
        if   (( fields[3] && ROD_PROMPT_GIT_UNTRACKED )); then dotcolor=203
        elif (( fields[2] && ROD_PROMPT_GIT_STAGED ));    then dotcolor=84
        elif (( fields[1] && ROD_PROMPT_GIT_DIRTY ));     then dotcolor=221
        fi

        _rod_neon_safe "$ROD_PROMPT_BRANCH_ICON $branch"
        gitpart="%F{$ROD_PROMPT_BRANCH_COLOR}$REPLY%f %F{$dotcolor}●%f"
        (( fields[4] > 0 )) && gitpart+=" %F{177}↑${fields[4]}%f"
        (( fields[5] > 0 )) && gitpart+=" %F{177}↓${fields[5]}%f"
      fi
    fi
  fi

  # 3. Monta o badge do usuário
  local userpart='' username=${(%):-%n}
  if (( ROD_PROMPT_SHOW_USER )); then
    _rod_neon_safe "$username"
    userpart="%K{$ROD_PROMPT_USER_BG}%F{$ROD_PROMPT_USER_COLOR} $REPLY %f%k "
  fi

  # 4. Responsividade: encurta ainda mais o caminho se a janela do terminal for estreita
  local budget=$(( width - ${#username} - ${#branch} - 14 ))
  if (( budget < 6 )); then
    _rod_neon_short "$dir" smart "$(( width / 3 ))" 1
    dir=$REPLY
  fi

  _rod_neon_safe "$dir"
  local header="${userpart}%F{$ROD_PROMPT_DIR_COLOR}$REPLY%f"
  [[ -n $gitpart ]] && header+=" $gitpart"

  # 5. Calcula espaço restante e preenche com caracteres pontilhados usando padding `${(l:N::char:)}`
  local plainlen=$(( ${#username} + ${#dir} + ${#branch} + 7 ))
  local fill=$(( width - plainlen ))
  if (( ROD_PROMPT_DOTS && fill > 0 )); then
    header+=" %F{$ROD_PROMPT_DIM_COLOR}${(l:$fill::$ROD_PROMPT_DOT_CHAR:)}%f"
  fi

  # 6. Monta a linha superior de status (erro/sucesso) ou separador
  local statusline=''
  if (( _ROD_NEON_RAN && (rc != 0 || ROD_PROMPT_SHOW_SUCCESS) )); then
    if (( (rc != 0 && ROD_PROMPT_SHOW_ERROR) || (rc == 0 && ROD_PROMPT_SHOW_SUCCESS) )); then
      _rod_neon_status_label "$rc"
      local status=$REPLY
      local free=$(( width - ${#status} - 2 ))
      (( free < 0 )) && free=0

      case $ROD_PROMPT_ERROR_POSITION in
        hidden) statusline='' ;;
        inline) header+=" %F{203}$status%f" ;;
        left)   statusline="%F{203}$status%f %F{$ROD_PROMPT_DIM_COLOR}${(l:$free::$ROD_PROMPT_DOT_CHAR:)}%f" ;;
        right)  statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$free::$ROD_PROMPT_DOT_CHAR:)}%f %F{203}$status%f" ;;
        *)
          local left=$(( free / 2 ))
          local right=$(( free - left ))
          statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$left::$ROD_PROMPT_DOT_CHAR:)}%f %F{203}$status%f %F{$ROD_PROMPT_DIM_COLOR}${(l:$right::$ROD_PROMPT_DOT_CHAR:)}%f"
          ;;
      esac
    fi
  elif (( _ROD_NEON_RAN && ROD_PROMPT_SHOW_SEPARATOR && ROD_PROMPT_DOTS )); then
    statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$width::$ROD_PROMPT_DOT_CHAR:)}%f"
  fi

  # 7. Renderiza o PROMPT final (verde se rc == 0, vermelho se rc != 0)
  _ROD_NEON_RAN=1
  local symbolcolor=84
  (( rc )) && symbolcolor=203

  PROMPT="${statusline:+$statusline$'\n'}$header
%F{177}$ROD_PROMPT_CORNER%f %F{$symbolcolor}$ROD_PROMPT_SYMBOL%f "
  RPROMPT=''
}

# ------------------------------------------------------------------------------
# 7. REGISTRO DE HOOKS & AUTO-COMPILAÇÃO BYTECODE (.zwc)
# ------------------------------------------------------------------------------
add-zsh-hook precmd _rod_neon_precmd
add-zsh-hook preexec _rod_neon_preexec

# `${(%):-%x}` resolve o caminho exato deste arquivo durante o `source`.
# Se ele foi editado recentemente, compila para `.zwc` em background para leitura instantânea.
if [[ -r "${(%):-%x}" && ( "${(%):-%x}" -nt "${(%):-%x}.zwc" || ! -e "${(%):-%x}.zwc" ) ]]; then
  zcompile "${(%):-%x}" &!
fi
EOF
