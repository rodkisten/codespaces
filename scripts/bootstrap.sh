#!/usr/bin/env bash
# ==============================================================================
# Rod Codespaces | Lifecycle Bootstrapper (create / start / attach)
# Gerencia links de dotfiles, serviços de rede (Tailscale), CLIs internas e checks.
# ==============================================================================
set -Eeuo pipefail

# ==============================================================================
# 1. VALIDAÇÃO DE ARGUMENTOS E VARIÁVEIS DE AMBIENTE
# ==============================================================================
PHASE="${1:-start}"
case "$PHASE" in
  create|start|attach|--install-theme-only) ;;
  *)
    printf '\033[31m[erro]\033[0m Uso: bootstrap.sh {create|start|attach|--install-theme-only}\n' >&2
    exit 2
    ;;
esac

REPO_DIR="${CODESPACE_VSCODE_FOLDER:-$PWD}"
LOCAL_BIN="$HOME/.local/bin"
LOG_DIR="$HOME/.local/state/rod-codespaces/logs"
LOG_FILE="$LOG_DIR/${PHASE}.log"

mkdir -p "$LOG_DIR" "$LOCAL_BIN"

# ==============================================================================
# 2. SISTEMA DE LOGS (COLORIDO NO TERMINAL + LIMPO NO ARQUIVO)
# ==============================================================================
# Redireciona stdout/stderr via tee, removendo sequências ANSI apenas no arquivo de log
exec > >(tee >(sed -u 's/\x1B\[[0-9;]*[a-zA-Z]//g' >> "$LOG_FILE")) 2>&1

# Paleta de cores ANSI (desativa automaticamente se não for um terminal interativo)
if [[ -t 1 ]]; then
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

# Controle automático de numeração das etapas
TOTAL_STEPS=6
CURRENT_STEP=0

step() {
  CURRENT_STEP=$((CURRENT_STEP + 1))
  printf '\n%s[%d/%d]%s %s%s%s\n' \
    "$C_CYAN$C_BOLD" "$CURRENT_STEP" "$TOTAL_STEPS" "$C_RESET" \
    "$C_BOLD" "$1" "$C_RESET"
}

log_ok()   { printf '  %s✔%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
log_info() { printf '  %sℹ%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
log_warn() { printf '  %s⚠%s %s%s%s\n' "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$*" "$C_RESET"; }
log_skip() { printf '  %s↷%s %s%s%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$*" "$C_RESET"; }
log_run()  { printf '  %s▶%s %s...\n' "$C_CYAN" "$C_RESET" "$*"; }

# ==============================================================================
# 3. CABEÇALHO E RODAPÉ AUTOMÁTICO (TRAP)
# ==============================================================================
print_header() {
  printf '%s╭──────────────────────────────────────────────────────────────╮%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  printf '%s│  🚀 Rod Codespaces • Fase: %-33s │%s\n' "$C_CYAN$C_BOLD" "$PHASE" "$C_RESET"
  printf '%s╰──────────────────────────────────────────────────────────────╯%s\n' "$C_CYAN$C_BOLD" "$C_RESET"
  printf '%s  UTC: %s | User: %s | Repo: %s%s\n' \
    "$C_DIM" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(id -un)" "$REPO_DIR" "$C_RESET"
}

on_exit() {
  local status=$?
  printf '\n'
  if [[ $status -eq 0 ]]; then
    printf '%s✔ Fase "%s" concluída com sucesso (exit 0)%s\n' "$C_GREEN$C_BOLD" "$PHASE" "$C_RESET"
  else
    printf '%s✖ Fase "%s" falhou (exit %d)%s\n' "$C_RED$C_BOLD" "$PHASE" "$status" "$C_RESET"
  fi
  printf '%s  Log salvo em: %s%s\n\n' "$C_DIM" "$LOG_FILE" "$C_RESET"
  exit "$status"
}
trap on_exit EXIT

# ==============================================================================
# 4. ETAPAS DO CICLO DE VIDA (MODULARES)
# ==============================================================================

# Theme-only mode: never installs packages, plugins, services, or changes PATH.
install_theme_only() {
  local source_theme="$REPO_DIR/config/zsh/rod-prompt-neon.zsh"
  local source_config="$REPO_DIR/config/zsh/rod-prompt-neon.config.zsh"
  local config_dir="$HOME/.config/zsh"
  local rc="$HOME/.zshrc"
  local line='[[ -r "$HOME/.config/zsh/rod-prompt.zsh" ]] && source "$HOME/.config/zsh/rod-prompt.zsh"'
  [[ -f "$source_theme" ]] || { log_warn "Theme missing: $source_theme"; return 1; }
  command -v zsh >/dev/null || { log_warn "zsh is required"; return 1; }
  zsh -n "$source_theme" || return 1
  mkdir -p "$config_dir"
  install -m 0644 "$source_theme" "$config_dir/rod-prompt.zsh"
  if [[ -f "$source_config" && ! -e "$config_dir/rod-prompt-neon.config.zsh" ]]; then
    install -m 0644 "$source_config" "$config_dir/rod-prompt-neon.config.zsh"
  fi
  [[ -e "$rc" || -L "$rc" ]] || touch "$rc"
  if ! grep -Fqx "$line" "$rc"; then
    [[ ! -L "$rc" ]] || { log_warn "Refusing to edit symlinked .zshrc"; return 1; }
    cp -p "$rc" "$rc.backup-$(date -u +%Y%m%dT%H%M%SZ)"
    printf '\\n# Rod Prompt Neon (theme only)\\n%s\\n' "$line" >> "$rc"
  fi
  zsh -n "$rc" || return 1
  log_ok "Theme installed. Run: exec zsh"
}

# Etapa 1: Vincula o ~/.zshrc ao repositório fazendo backup de segurança
setup_zshrc() {
  step "Verificando Zsh (~/.zshrc)"
  local target_file="$HOME/.zshrc"
  # Never replace user dotfiles with symlinks during Codespaces lifecycle.
  # The shell installer owns the optional managed source line.
  if [[ -L "$target_file" ]]; then
    log_warn "~/.zshrc é symlink; preservado sem alterações."
  elif [[ -f "$target_file" ]]; then
    log_ok "~/.zshrc existente preservado."
  else
    touch "$target_file"
    log_ok "~/.zshrc inicializado."
  fi
}

# Etapa 2: Inicializa/reconecta o Tailscale se o script existir no checkout
setup_tailscale() {
  step "Verificando rede Tailscale"
  local ts_script="$REPO_DIR/scripts/tailscale.sh"

  if [[ ! -f "$ts_script" ]]; then
    log_skip "scripts/tailscale.sh ausente; pulando."
    return 0
  fi

  log_run "Executando tailscale.sh auto"
  if bash "$ts_script" auto; then
    log_ok "Tailscale configurado com sucesso."
  else
    log_warn "Daemon ou autenticação do Tailscale indisponível (não bloqueante)."
  fi
}

# Etapa 3: Instala o utilitário global rod-check no PATH do usuário
install_rod_check() {
  step "Instalando CLI rod-check"
  local src="$REPO_DIR/scripts/rod-check"
  local dest="$LOCAL_BIN/rod-check"

  if [[ ! -f "$src" ]]; then
    log_warn "scripts/rod-check ausente; pulando."
    return 0
  fi

  install -m 0755 "$src" "$dest"
  log_ok "Instalado em $dest"
}

# Etapa 4: Compila o rodlog localmente via Go (evita depender de releases remotas)
build_rodlog() {
  step "Compilando rodlog (Go)"
  local mod_dir="$REPO_DIR/packages/rodlog"
  local out_bin="$LOCAL_BIN/rodlog"

  if [[ "${RODLOG_BOOT_INSTALL:-1}" == "0" ]]; then
    log_skip "Desabilitado via RODLOG_BOOT_INSTALL=0."
    return 0
  fi

  if [[ ! -f "$mod_dir/go.mod" ]]; then
    log_skip "Código-fonte ausente em $mod_dir; pulando."
    return 0
  fi

  if ! command -v go >/dev/null 2>&1; then
    log_skip "Toolchain Go não disponível no ambiente; pulando."
    return 0
  fi

  log_run "Compilando $mod_dir/cmd/rodlog"
  if (cd "$mod_dir" && go build -o "$out_bin" ./cmd/rodlog); then
    log_ok "Binário instalado: $out_bin"
  else
    log_warn "Falha na compilação do rodlog (binário anterior preservado, se existir)."
  fi
}

# Install xi as a global command without running remote installers.
install_xi() {
  step "Installing xi universal installer"
  local src="$REPO_DIR/scripts/xi.sh"
  if [[ -f "$src" ]]; then
    install -m 0755 "$src" "$LOCAL_BIN/xi"
    log_ok "xi installed at $LOCAL_BIN/xi"
  else
    log_skip "scripts/xi.sh not present"
  fi
}

# Etapa 5: Executa diagnóstico do ambiente via mobile-doctor
run_health_check() {
  step "Executando diagnóstico (mobile-doctor)"

  # Garante que ~/.local/bin esteja no PATH durante a verificação
  export PATH="$LOCAL_BIN:$PATH"

  if ! command -v mobile-doctor >/dev/null 2>&1; then
    log_warn "mobile-doctor não encontrado no PATH."
    return 0
  fi

  if mobile-doctor; then
    log_ok "Todas as ferramentas verificadas com sucesso."
  else
    log_warn "mobile-doctor reportou ferramentas ausentes."
  fi
}

# ==============================================================================
# 5. EXECUÇÃO PRINCIPAL (ORQUESTRAÇÃO POR FASE)
# ==============================================================================
main() {
  print_header

  case "$PHASE" in
    create|start)
      setup_zshrc
      setup_tailscale
      install_rod_check
      install_xi
      build_rodlog
      run_health_check
      ;;
    --install-theme-only)
      install_theme_only
      ;;
    attach)
      log_info "Fase 'attach' não requer reconfiguração de sistema."
      ;;
  esac
}

main "$@"
