#!/usr/bin/env bash
# Biblioteca de UI e Logs compartilhada entre install.sh e scripts em ~/.local/bin

# Evita carregar duas vezes no mesmo processo
[[ -n "${_ROD_UI_LOADED:-}" ]] && return 0
_ROD_UI_LOADED=1

# Desativa cores automaticamente se stderr não for um terminal interativo
if [[ -t 2 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED=''
fi

# Permite personalizar o prefixo por script (padrão: nome do script atual)
ROD_PREFIX="${ROD_PREFIX:-$(basename "$0")}"

log()      { printf '%s[%s]%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$*" >&2; }
log_ok()   { printf '%s[%s]%s %s✔%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_GREEN" "$C_RESET" "$*" >&2; }
log_info() { printf '%s[%s]%s %sℹ%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_BLUE" "$C_RESET" "$*" >&2; }
log_warn() { printf '%s[%s]%s %s⚠ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET" >&2; }
log_skip() { printf '%s[%s]%s %s↷ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_DIM" "$*" "$C_RESET" >&2; }
fail() {
  tput cnorm 2>/dev/null || true
  printf '%s[%s]%s %s✖ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2
  exit 1
}

spinner() {
  local pid="$1"
  local step_prefix="$2"
  local message="$3"
  local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

  if [[ ! -t 2 ]]; then
    wait "$pid"
    return $?
  fi

  tput civis 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null; do
    local temp="${spinstr#?}"
    printf '\r%s[%s]%s %s%s%c%s %s...' \
      "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$step_prefix" "$C_YELLOW" "$spinstr" "$C_RESET" "$message" >&2
    spinstr="$temp${spinstr%"$temp"}"
    sleep 0.1
  done
  tput cnorm 2>/dev/null || true
}
