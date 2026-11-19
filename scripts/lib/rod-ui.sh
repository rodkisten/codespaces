#!/usr/bin/env bash
# ==============================================================================
# Rod Codespaces | Biblioteca Compartilhada de UI, Logs e Spinners
# Uso: source "${HOME}/.local/lib/rod-ui.sh"
# ==============================================================================

# Evita recarregamento duplo no mesmo shell
[[ -n "${_ROD_UI_LOADED:-}" ]] && return 0
_ROD_UI_LOADED=1

# ==============================================================================
# 1. PALETA DE CORES (Desativa automaticamente fora de TTY)
# ==============================================================================
if [[ -t 2 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_BLUE=$'\033[34m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
  C_MAGENTA=$'\033[35m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_CYAN='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_MAGENTA=''
fi

# Prefixo dinâmico (pode ser sobrescrito antes do source: ROD_PREFIX="meu-cmd")
ROD_PREFIX="${ROD_PREFIX:-$(basename "$0")}"

# ==============================================================================
# 2. FUNÇÕES DE LOG PADRONIZADAS (Saem em stderr para não sujar pipes)
# ==============================================================================
log()      { printf '%s[%s]%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$*" >&2; }
log_ok()   { printf '%s[%s]%s %s✔%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_GREEN" "$C_RESET" "$*" >&2; }
log_info() { printf '%s[%s]%s %sℹ%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_BLUE" "$C_RESET" "$*" >&2; }
log_warn() { printf '%s[%s]%s %s⚠ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET" >&2; }
log_skip() { printf '%s[%s]%s %s↷ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_DIM" "$*" "$C_RESET" >&2; }
log_run()  { printf '%s[%s]%s %s▶%s %s...\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_MAGENTA" "$C_RESET" "$*" >&2; }

fail() {
  tput cnorm 2>/dev/null || true
  printf '%s[%s]%s %s✖ %s%s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$C_RED" "$*" "$C_RESET" >&2
  exit 1
}

# ==============================================================================
# 3. CONTADOR AUTOMÁTICO DE ETAPAS (STEPS)
# ==============================================================================
ROD_TOTAL_STEPS=0
ROD_CURRENT_STEP=0

init_steps() {
  ROD_TOTAL_STEPS="${1:-0}"
  ROD_CURRENT_STEP=0
}

next_step() {
  ROD_CURRENT_STEP=$((ROD_CURRENT_STEP + 1))
  if (( ROD_TOTAL_STEPS > 0 )); then
    printf '\n%s[%d/%d]%s %s%s%s\n' \
      "$C_CYAN$C_BOLD" "$ROD_CURRENT_STEP" "$ROD_TOTAL_STEPS" "$C_RESET" \
      "$C_BOLD" "$1" "$C_RESET" >&2
  else
    printf '\n%s[%d]%s %s%s%s\n' \
      "$C_CYAN$C_BOLD" "$ROD_CURRENT_STEP" "$C_RESET" \
      "$C_BOLD" "$1" "$C_RESET" >&2
  fi
}

# ==============================================================================
# 4. SPINNER E EXECUÇÃO MONITORADA
# ==============================================================================
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

# Executa comando em background com spinner e aborta em caso de erro
run_with_spinner() {
  local step_prefix="$1"
  local label="$2"
  local log_target="${ROD_LOG_FILE:-/dev/null}"
  shift 2

  printf '=== %s %s ===\n' "$step_prefix" "$label" >> "$log_target"

  ( "$@" ) >> "$log_target" 2>&1 &
  local pid=$!

  spinner "$pid" "$step_prefix" "$label"

  local exit_code=0
  wait "$pid" || exit_code=$?

  [[ -t 2 ]] && printf '\r\033[K' >&2

  if [[ $exit_code -eq 0 ]]; then
    printf '%s[%s]%s %s%s✔%s %s\n' "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$step_prefix" "$C_GREEN" "$C_RESET" "$label" >&2
    return 0
  else
    printf '%s[%s]%s %s%s✖%s %s %s(código %d)%s\n' \
      "$C_CYAN" "$ROD_PREFIX" "$C_RESET" "$step_prefix" "$C_RED" "$C_RESET" "$label" "$C_RED" "$exit_code" "$C_RESET" >&2
    if [[ "$log_target" != "/dev/null" && -f "$log_target" ]]; then
      log_warn "Últimas linhas do log ($log_target):"
      tail -n 15 "$log_target" >&2
    fi
    return "$exit_code"
  fi
}
