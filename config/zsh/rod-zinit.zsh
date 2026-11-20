# 💜 Rod Zsh · Zinit (Turbo Mode, Zero-Duplication & Cached Init)
[[ -o interactive ]] || return 0

# ==============================================================================
# 1. AMBIENTE, PATH & VARIÁVEIS GLOBAIS
# ==============================================================================
typeset -U path cdpath fpath manpath # Evita entradas duplicadas no PATH
path=(
  "$HOME/.local/bin"
  "$HOME/go/bin"
  "$HOME/.cargo/bin"
  $path
)
export PATH

export EDITOR='micro'
export VISUAL='micro'
export PAGER='less -FRX'
export GIT_PAGER='less -FRX'
export LESS='-FRX'
export PYTHONUTF8=1
export UV_NO_PROGRESS=1

ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
[[ -d "$ZSH_CACHE_DIR" ]] || mkdir -p "$ZSH_CACHE_DIR"

# ==============================================================================
# 2. HISTÓRICO & OPÇÕES DO SHELL
# ==============================================================================
HISTFILE="$HOME/.zsh_history"
HISTSIZE=20000
SAVEHIST=20000
DIRSTACKSIZE=12

setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS EXTENDED_GLOB
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_FIND_NO_DUPS HIST_REDUCE_BLANKS
setopt SHARE_HISTORY INC_APPEND_HISTORY
#unsetopt CORRECT_ALL BEEP

WORDCHARS=${WORDCHARS//\/}

# ==============================================================================
# 3. KEYBINDINGS (Emacs + Codespaces xterm.js)
# ==============================================================================
bindkey -e
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey '^W' backward-kill-word
bindkey '^U' backward-kill-line
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line

# Atalho Alt+Alt+Espaço para alternar 'sudo' na linha atual
function _rod_sudo_prefix() {
  [[ "$BUFFER" == sudo\ * ]] && BUFFER="${BUFFER#sudo }" || BUFFER="sudo $BUFFER"
  CURSOR=${#BUFFER}
}
zle -N _rod_sudo_prefix
bindkey '^[^[ ' _rod_sudo_prefix

# ==============================================================================
# 4. ZINIT & PLUGINS (Com Turbo Mode para Prompt Instantâneo)
# ==============================================================================
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ -r "$ZINIT_HOME/zinit.zsh" ]]; then
  source "$ZINIT_HOME/zinit.zsh"

  # Carrega completions no fpath antes do compinit
  zinit ice blockf atpull'zinit creinstall -q .'
  zinit light zsh-users/zsh-completions

  # Plugins visuais e de busca carregados de forma assíncrona (0ms de bloqueio)
  zinit wait lucid for \
    atload"_zsh_autosuggest_start" \
      zsh-users/zsh-autosuggestions \
    atload"bindkey '^[[A' history-substring-search-up; bindkey '^[[B' history-substring-search-down" \
      zsh-users/zsh-history-substring-search \
    atinit"zicompinit; zicdreplay" \
      zsh-users/zsh-syntax-highlighting
fi

# ==============================================================================
# 5. COMPLETION SYSTEM (Cache Inteligente de 24h)
# ==============================================================================
autoload -Uz compinit
zmodload zsh/complist

# Só regenera o zcompdump se tiver mais de 24 horas (acelera drasticamente o boot)
if [[ -n "$ZSH_CACHE_DIR/zcompdump"(#qN.mh+24) ]]; then
  compinit -d "$ZSH_CACHE_DIR/zcompdump"
else
  compinit -C -d "$ZSH_CACHE_DIR/zcompdump"
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$ZSH_CACHE_DIR"

# ==============================================================================
# 6. INTEGRAÇÕES CLI (Cache de Init Scripts para Evitar Subshells)
# ==============================================================================
# Zoxide (j)
if (( $+commands[zoxide] )); then
  _zoxide_cache="$ZSH_CACHE_DIR/zoxide.zsh"
  if [[ ! -r "$_zoxide_cache" || "$commands[zoxide]" -nt "$_zoxide_cache" ]]; then
    zoxide init zsh --cmd j > "$_zoxide_cache"
  fi
  source "$_zoxide_cache"
  unset _zoxide_cache
fi

# FZF (Ctrl+R / Ctrl+T)
if (( $+commands[fzf] )); then
  _fzf_cache="$ZSH_CACHE_DIR/fzf.zsh"
  if [[ ! -r "$_fzf_cache" || "$commands[fzf]" -nt "$_fzf_cache" ]]; then
    fzf --zsh > "$_fzf_cache" 2>/dev/null
  fi
  [[ -s "$_fzf_cache" ]] && source "$_fzf_cache"
  unset _fzf_cache
fi

# ==============================================================================
# 7. ALIASES & FERRAMENTAS MODERNAS
# ==============================================================================
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first --color=auto'
  alias ll='eza -lah --group-directories-first --color=auto'
  alias la='eza -a --group-directories-first --color=auto'
  alias lt='eza --tree --level=2 --group-directories-first'
else
  alias ll='ls -lah'
  alias la='ls -a'
  alias lt='ls -R'
fi

if (( $+commands[bat] )); then
  alias c='bat --paging=never'
elif (( $+commands[batcat] )); then
  alias c='batcat --paging=never'
fi

(( $+commands[fdfind] )) && alias fd='fdfind'
(( $+commands[rg] ))     && alias rg='rg --smart-case'

alias jpp='jq -C .'
alias ports='ss -tulpen'
alias py='python3'
alias pip='uv pip'
alias venv='uv venv'
alias wr='wrangler'
alias bootstrap="curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash -s -- exec zsh"

# ==============================================================================
# 8. FUNÇÕES UTILITÁRIAS
# ==============================================================================
function croot() {
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
}

function up() {
  local n="${1:-1}"
  if [[ "$n" != <-> ]] || (( n < 1 || n > 30 )); then
    print -u2 'Uso: up [1..30]'
    return 2
  fi
  local i
  for (( i=0; i<n; i++ )); do cd .. || return; done
}

function mkcd() {
  mkdir -p -- "$1" && cd -- "$1"
}

function ff() {
  if (( $+commands[fdfind] )); then
    fdfind --hidden --exclude .git "${@:-.}"
  elif (( $+commands[fd] )); then
    command fd --hidden --exclude .git "${@:-.}"
  else
    find . -iname "*${1:-}*"
  fi
}

function fcd() {
  local target
  if (( $+commands[fdfind] )); then
    target="$(fdfind --type d --hidden --exclude .git . | fzf --height=45% --reverse --no-multi)" || return
  elif (( $+commands[fd] )); then
    target="$(command fd --type d --hidden --exclude .git . | fzf --height=45% --reverse --no-multi)" || return
  else
    target="$(find . -type d -not -path '*/.git/*' | fzf --height=45% --reverse --no-multi)" || return
  fi
  [[ -n "$target" ]] && cd -- "$target"
}

function fh() {
  local selection
  selection="$(fc -l -n -r 1 | fzf --height=50% --reverse --no-multi)" || return
  [[ -n "$selection" ]] && print -z -- "$selection"
}

function gproject() {
  gcloud config get-value project 2>/dev/null
}

function gset() {
  if (( $# != 1 )); then
    print -u2 'Uso: gset PROJECT_ID'
    return 2
  fi
  gcloud config set project "$1"
}

function wrdev()    { pnpm exec wrangler dev "$@"; }
function wrdeploy() { pnpm exec wrangler deploy "$@"; }

function extract() {
  local f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    case "$f" in
      *.tar.gz|*.tgz) tar xzf "$f" ;;
      *.tar.xz)       tar xJf "$f" ;;
      *.tar.bz2)      tar xjf "$f" ;;
      *.tar)          tar xf "$f" ;;
      *.zip)          unzip "$f" ;;
      *.gz)           gunzip -k "$f" ;;
      *.7z)           7z x "$f" ;;
      *)              print -u2 "Unsupported: $f" ;;
    esac
  done
}

function man() {
  LESS_TERMCAP_md=$'\e[1;35m' LESS_TERMCAP_me=$'\e[0m' command man "$@"
}

function rod-notify-debug() {
  local script="$HOME/.local/share/rod/codespaces/scripts/rod-notify-debug.py"
  if [[ ! -f "$script" ]]; then
    print -u2 "Missing $script. Run the Codespaces Zinit installer again."
    return 1
  fi
  python3 "$script" "$@"
}

# ==============================================================================
# 9. PROMPT, NOTIFICAÇÕES & LIMPEZA DE HOOKS
# ==============================================================================
# Garante ausência de handlers lentos de "command not found" e traps de erro
unfunction command_not_found_handle TRAPZERR 2>/dev/null
trap - ERR ZERR

[[ -r "$HOME/.config/zsh/rod-notify.zsh" ]]            && source "$HOME/.config/zsh/rod-notify.zsh"
[[ -r "$HOME/.config/zsh/rod-prompt-neon.config.zsh" ]] && source "$HOME/.config/zsh/rod-prompt-neon.config.zsh"
[[ -r "$HOME/.config/zsh/rod-prompt.zsh" ]]            && source "$HOME/.config/zsh/rod-prompt.zsh"

# Auto-compila o próprio .zshrc para bytecode (.zwc) em background se alterado
if [[ "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" || ! -e "$HOME/.zshrc.zwc" ]]; then
  zcompile "$HOME/.zshrc" &!
fi
