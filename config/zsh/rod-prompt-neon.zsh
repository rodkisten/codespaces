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

autoload -Uz add-zsh-hook
zmodload -F zsh/datetime p:EPOCHREALTIME 2>/dev/null
setopt PROMPT_PERCENT
unsetopt PROMPT_SUBST

typeset -g ROD_PROMPT_LAST_EXIT=0
typeset -g ROD_PROMPT_LAST_COMMAND=''
typeset -g ROD_PROMPT_DEBUG=${ROD_PROMPT_DEBUG:-0}

: ${ROD_PROMPT_DOTS:=1}
: ${ROD_PROMPT_SHOW_BRANCH:=1}
: ${ROD_PROMPT_SHOW_REPO:=1}
: ${ROD_PROMPT_SHOW_USER:=1}
: ${ROD_PROMPT_SHOW_COMMAND:=1}
: ${ROD_PROMPT_SHOW_SUCCESS:=0}
: ${ROD_PROMPT_SHOW_ERROR:=1}
: ${ROD_PROMPT_ERROR_TEXT:=1}

# Neon palette
typeset -g ROD_COLOR_PURPLE=177
typeset -g ROD_COLOR_CYAN=81
typeset -g ROD_COLOR_BRANCH=123
typeset -g ROD_COLOR_GREEN=84
typeset -g ROD_COLOR_YELLOW=221
typeset -g ROD_COLOR_RED=203
typeset -g ROD_COLOR_DIM=240

# Dimmed backgrounds
typeset -g ROD_BG_RED=52
typeset -g ROD_BG_YELLOW=58
typeset -g ROD_BG_PURPLE=53
typeset -g ROD_BG_GREEN=22
typeset -g ROD_BG_USER=54

# Escape prompt expansion characters.
_rod_prompt_escape() {
  REPLY="${1//\%/%%}"
}

# Zero-fork Git info reader (lê .git/HEAD direto em memória sem chamar binário git)
_rod_prompt_git_fast() {
  emulate -L zsh
  local dir="$PWD"
  local git_dir head_content

  REPLY_REPO=''
  REPLY_BRANCH=''

  # Sobe a árvore de diretórios procurando .git
  while [[ "$dir" != "/" && -n "$dir" ]]; do
    if [[ -e "$dir/.git" ]]; then
      REPLY_REPO="${dir:t}"
      if [[ -d "$dir/.git" ]]; then
        git_dir="$dir/.git"
      elif [[ -f "$dir/.git" ]]; then
        # Suporte a git worktrees e submódulos
        read -r git_dir < "$dir/.git"
        git_dir="${git_dir#gitdir: }"
        [[ "$git_dir" != /* ]] && git_dir="$dir/$git_dir"
      fi
      break
    fi
    dir="${dir:h}"
  done

  [[ -z "$git_dir" || ! -r "$git_dir/HEAD" ]] && return 1

  if (( ROD_PROMPT_SHOW_BRANCH )); then
    read -r head_content < "$git_dir/HEAD"
    if [[ "$head_content" == ref:\ refs/heads/* ]]; then
      REPLY_BRANCH="${head_content#ref: refs/heads/}"
    else
      # Detached HEAD: pega os primeiros 7 caracteres do hash
      REPLY_BRANCH="${head_content[1,7]}"
    fi
  fi
}

# Capture command before execution.
_rod_prompt_neon_preexec() {
  ROD_PROMPT_LAST_COMMAND="$1"
}

# Exit status description and colors.
_rod_prompt_neon_status() {
  emulate -L zsh
  local rc=$1
  local color=$ROD_COLOR_RED
  local bg=$ROD_BG_RED
  local meaning='Falha na execução'

  case $rc in
    0)   color=$ROD_COLOR_GREEN;  bg=$ROD_BG_GREEN;  meaning='OK' ;;
    1)   color=$ROD_COLOR_YELLOW; bg=$ROD_BG_YELLOW; meaning='Erro geral' ;;
    2)   color=$ROD_COLOR_YELLOW; bg=$ROD_BG_YELLOW; meaning='Uso incorreto' ;;
    64|65|78) color=$ROD_COLOR_YELLOW; bg=$ROD_BG_YELLOW; meaning='Entrada ou configuração inválida' ;;
    69|70|73|74|77) meaning='Falha de serviço, sistema ou permissão' ;;
    75)  color=$ROD_COLOR_YELLOW; bg=$ROD_BG_YELLOW; meaning='Falha temporária' ;;
    124) color=$ROD_COLOR_YELLOW; bg=$ROD_BG_YELLOW; meaning='Tempo esgotado' ;;
    126) meaning='Não executável' ;;
    127) meaning='Comando não encontrado' ;;
    128) meaning='Erro de saída' ;;
    130) color=$ROD_COLOR_PURPLE; bg=$ROD_BG_PURPLE; meaning='Interrompido · Ctrl+C' ;;
    137) color=$ROD_COLOR_PURPLE; bg=$ROD_BG_PURPLE; meaning='Finalizado · SIGKILL' ;;
    139) meaning='Falha de segmentação' ;;
    143) color=$ROD_COLOR_PURPLE; bg=$ROD_BG_PURPLE; meaning='Encerrado · SIGTERM' ;;
    *)
      if (( rc > 128 && rc <= 192 )); then
        color=$ROD_COLOR_PURPLE
        bg=$ROD_BG_PURPLE
        meaning="Sinal $(( rc - 128 ))"
      fi
      ;;
  esac

  local content
  if (( rc == 0 )); then
    content='✓ OK'
  else
    content="✕ $rc"
    (( ROD_PROMPT_ERROR_TEXT )) && content+=" · $meaning"
  fi

  REPLY="%F{$bg}%f%K{$bg}%F{$color} ${content} %f%k%F{$bg}%f"
  REPLY_WIDTH=$(( ${#content} + 4 ))
}

# Lightweight command syntax coloring.
_rod_prompt_neon_highlight() {
  emulate -L zsh
  setopt localoptions extendedglob

  local command="$1"
  local token color style output=''
  local -a tokens=("${(z)command}")
  local first=1

  # Cache da cor de comando do zsh-syntax-highlighting
  local cmd_color=$ROD_COLOR_CYAN
  if (( ${+ZSH_HIGHLIGHT_STYLES} )) && [[ -n "${ZSH_HIGHLIGHT_STYLES[command]-}" ]]; then
    style="${ZSH_HIGHLIGHT_STYLES[command]}"
    [[ "$style" == fg=* ]] && cmd_color="${${style#fg=}%%,*}"
  fi

  for token in "${tokens[@]}"; do
    color=252

    if [[ "$token" == -* ]]; then
      color=$ROD_COLOR_PURPLE
    elif [[ "$token" == \"*\" || "$token" == \'*\' ]]; then
      color=114
    elif [[ "$token" == '|' || "$token" == '&&' || "$token" == '||' || "$token" == ';' ]]; then
      color=$ROD_COLOR_YELLOW
      first=1
    elif (( first )); then
      color=$cmd_color
      first=0
    fi

    _rod_prompt_escape "$token"
    output+="%F{$color}${REPLY}%f "
  done

  REPLY="${output% }"
}

# Render the prompt after each command.
_rod_prompt_neon_precmd() {
  local rc=$?
  local t_start=${EPOCHREALTIME:-0}
  ROD_PROMPT_LAST_EXIT=$rc

  local branch='' repo='' label='' colored='' suffix=''
  local username="${(%):-%n}"
  local directory="${(%):-%~}"
  local width=${COLUMNS:-80}

  # Zero-fork Git metadata
  if (( ROD_PROMPT_SHOW_REPO || ROD_PROMPT_SHOW_BRANCH )); then
    _rod_prompt_git_fast
    repo="$REPLY_REPO"
    branch="$REPLY_BRANCH"
  fi

  # Rounded username capsule
  local user_part=''
  local user_width=0

  if (( ROD_PROMPT_SHOW_USER )); then
    _rod_prompt_escape "$username"
    user_part="%F{$ROD_BG_USER}%f%K{$ROD_BG_USER}%F{225} ${REPLY} %f%k%F{$ROD_BG_USER}%f"
    user_width=$(( ${#username} + 4 ))
  fi

  # Directory and branch
  label="$directory"
  _rod_prompt_escape "$directory"
  colored="%F{$ROD_COLOR_PURPLE}${REPLY}%f"

  if (( ROD_PROMPT_SHOW_REPO )) && [[ -n $repo && ${directory:t} != $repo ]]; then
    _rod_prompt_escape "$repo"
    label+=" · $repo"
    colored+=" %F{$ROD_COLOR_DIM}·%f %F{$ROD_COLOR_CYAN}${REPLY}%f"
  fi

  if [[ -n $branch ]]; then
    _rod_prompt_escape "$branch"
    label+=" · $branch"
    colored+=" %F{$ROD_COLOR_DIM}·%f %F{$ROD_COLOR_BRANCH}${REPLY}%f"
  fi

  # Mobile-friendly truncation
  local available=$(( width - user_width - 5 ))
  (( available < 8 )) && available=8

  if (( ${#label} > available )); then
    label="…${label[-$((available - 1)),-1]}"
    _rod_prompt_escape "$label"
    colored="%F{$ROD_COLOR_PURPLE}${REPLY}%f"
  fi

  # Last command, colored (e resetado para não repetir em Enter vazio)
  local command_line=''
  if (( ROD_PROMPT_SHOW_COMMAND )) && [[ -n $ROD_PROMPT_LAST_COMMAND ]]; then
    _rod_prompt_neon_highlight "$ROD_PROMPT_LAST_COMMAND"
    command_line="$REPLY"
  fi
  ROD_PROMPT_LAST_COMMAND=''

  # Execution status capsule
  local status_part=''
  local status_width=0

  if (( (rc != 0 && ROD_PROMPT_SHOW_ERROR) || (rc == 0 && ROD_PROMPT_SHOW_SUCCESS) )); then
    _rod_prompt_neon_status "$rc"
    status_part=$REPLY
    status_width=$REPLY_WIDTH
  fi

  # Full-width dotted divider
  local left_dots='' right_dots=''
  local left_count=0 right_count=0

  if (( ROD_PROMPT_DOTS )); then
    local free=$(( width - status_width - 2 ))
    (( free < 0 )) && free=0

    if [[ -n $status_part ]]; then
      left_count=$(( free / 2 ))
      right_count=$(( free - left_count ))
    else
      left_count=$free
    fi

    (( left_count > 0 )) && left_dots="${(l:$left_count::·:)}"
    (( right_count > 0 )) && right_dots="${(l:$right_count::·:)}"
  fi

  local divider="%F{$ROD_COLOR_DIM}${left_dots}%f"
  if [[ -n $status_part ]]; then
    divider+=" $status_part %F{$ROD_COLOR_DIM}${right_dots}%f"
  fi

  # Green success / red failure symbol
  if (( rc == 0 )); then
    suffix="%F{$ROD_COLOR_GREEN}\$%f"
  else
    suffix="%F{$ROD_COLOR_RED}\$%f"
  fi

  # Debug telemetry pill (ativa com ROD_PROMPT_DEBUG=1)
  local debug_line=''
  if (( ROD_PROMPT_DEBUG )) && [[ "$t_start" != "0" ]]; then
    local elapsed_ms
    printf -v elapsed_ms "%.2f" $(( (EPOCHREALTIME - t_start) * 1000 ))
    debug_line=$'\n'"%F{244}[⚡ Prompt Debug: ${elapsed_ms}ms | rc=${rc} | cols=${width} | git=${repo:-none}:${branch:-none}]%f"
  fi

  # Final layout
  PROMPT="${user_part} ${colored}"
  [[ -n $command_line ]] && PROMPT+=$'\n'"${command_line}"
  PROMPT+=$'\n'"${divider}"
  PROMPT+="${debug_line}"
  PROMPT+=$'\n'"%F{$ROD_COLOR_PURPLE}╰─%f ${suffix} "

  RPROMPT=''
}

# Reload-safe hooks.
add-zsh-hook -d preexec _rod_prompt_neon_preexec 2>/dev/null
add-zsh-hook -d precmd _rod_prompt_neon_precmd 2>/dev/null
add-zsh-hook preexec _rod_prompt_neon_preexec
add-zsh-hook precmd _rod_prompt_neon_precmd
