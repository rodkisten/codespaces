# 💜 Rod Zsh · Zinit, no Oh My Zsh
[[ -o interactive ]] || return 0
export PATH="$HOME/.local/bin:$HOME/go/bin:$HOME/.cargo/bin:$PATH"
export EDITOR=micro VISUAL=micro PAGER='less -FRX' GIT_PAGER='less -FRX'
export LESS='-FRX' PYTHONUTF8=1 UV_NO_PROGRESS=1
HISTFILE="$HOME/.zsh_history"
HISTSIZE=20000
SAVEHIST=20000
DIRSTACKSIZE=12
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS EXTENDED_GLOB
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_FIND_NO_DUPS HIST_REDUCE_BLANKS
setopt SHARE_HISTORY INC_APPEND_HISTORY
unsetopt CORRECT_ALL BEEP
WORDCHARS=${WORDCHARS//\/}
autoload -Uz compinit
zmodload zsh/complist
mkdir -p "$HOME/.cache/zsh"
compinit -d "$HOME/.cache/zsh/zcompdump"
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%F{yellow}%d%f'
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.cache/zsh"
bindkey -e
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[b' backward-word
bindkey '^[f' forward-word
bindkey '^W' backward-kill-word
bindkey '^U' backward-kill-line
bindkey '^A' beginning-of-line
bindkey '^E' end-of-line
bindkey '^[[3~' delete-char
# zinit installed once by installer; no network access during startup.
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ -r "$ZINIT_HOME/zinit.zsh" ]]; then
  source "$ZINIT_HOME/zinit.zsh"
  zinit light zsh-users/zsh-completions
  zinit light zsh-users/zsh-autosuggestions
  zinit light zsh-users/zsh-history-substring-search
  zinit light zsh-users/zsh-syntax-highlighting
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
fi
if (( $+commands[fzf] )) && fzf --zsh >/dev/null 2>&1; then
  source <(fzf --zsh)
fi
if (( $+commands[zoxide] )); then eval "$(zoxide init zsh --cmd j)"; fi
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first --color=auto'
  alias ll='eza -lah --group-directories-first --color=auto'
  alias la='eza -a --group-directories-first --color=auto'
  alias lt='eza --tree --level=2'
else
  alias ll='ls -lah' la='ls -a' lt='ls -R'
fi
if (( $+commands[batcat] )); then alias c='batcat --paging=never'; fi
if (( $+commands[bat] )); then alias c='bat --paging=never'; fi
if (( $+commands[fdfind] )); then alias fd='fdfind'; fi
alias jpp='jq -C .' ports='ss -tulpen' py='python3' wr='wrangler'
function croot() { cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; }
function up() { local n="${1:-1}" i; [[ "$n" == <-> ]] && (( n >= 1 && n <= 30 )) || return 2; for (( i=0; i<n; i++ )); do cd .. || return; done; }
function mkcd() { mkdir -p -- "$1" && cd -- "$1"; }
function ff() { if (( $+commands[fd] )); then command fd --hidden --exclude .git "${@:-.}"; else find . -iname "*${1:-}*"; fi; }
function fcd() { local d; d="$(find . -type d -not -path '*/.git/*' | fzf --height=45% --reverse)" && [[ -n "$d" ]] && cd -- "$d"; }
function fh() { local x; x="$(fc -l -n -r 1 | fzf --height=50% --reverse)" && [[ -n "$x" ]] && print -z -- "$x"; }
function gproject() { gcloud config get-value project; }
function gset() { gcloud config set project "$1"; }
function wrdev() { pnpm exec wrangler dev "$@"; }
function wrdeploy() { pnpm exec wrangler deploy "$@"; }
function extract() { local f; for f in "$@"; do [[ -f "$f" ]] || continue; case "$f" in *.tar.gz|*.tgz) tar xzf "$f";; *.tar.xz) tar xJf "$f";; *.tar.bz2) tar xjf "$f";; *.tar) tar xf "$f";; *.zip) unzip "$f";; *.gz) gunzip -k "$f";; *.7z) 7z x "$f";; *) print -u2 "Unsupported: $f";; esac; done; }
function man() { LESS_TERMCAP_md=$'\e[1;35m' LESS_TERMCAP_me=$'\e[0m' command man "$@"; }
function _rod_sudo_prefix() { [[ "$BUFFER" == sudo\ * ]] && BUFFER="${BUFFER#sudo }" || BUFFER="sudo $BUFFER"; CURSOR=${#BUFFER}; }
zle -N _rod_sudo_prefix
bindkey '^[^[ ' _rod_sudo_prefix
[[ -r /etc/zsh_command_not_found ]] && source /etc/zsh_command_not_found
[[ -r "$HOME/.config/zsh/rod-notify.zsh" ]] && source "$HOME/.config/zsh/rod-notify.zsh"
[[ -r "$HOME/.config/zsh/rod-prompt-neon.config.zsh" ]] && source "$HOME/.config/zsh/rod-prompt-neon.config.zsh"
[[ -r "$HOME/.config/zsh/rod-prompt.zsh" ]] && source "$HOME/.config/zsh/rod-prompt.zsh"

# Rod Notify interactive tmux debugger (no credentials in command arguments).
function rod-notify-debug() {
  local script="$HOME/.local/share/rod/codespaces/scripts/rod-notify-debug.py"
  if [[ ! -f "$script" ]]; then
    print -u2 "Missing $script. Run the Codespaces Zinit installer again."
    return 1
  fi
  python3 "$script" "$@"
}
