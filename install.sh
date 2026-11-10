#!/usr/bin/env bash
# Rod Mobile Codespaces | Instalador autocontido.
# Gerado por tools/build-installer.sh. Não edite o conteúdo EMBEDDED manualmente.
set -euo pipefail

PROGRAM_NAME='Rod Mobile Codespaces'
MODE='devcontainer'
TARGET="$PWD"
FORCE=0
DRY_RUN=0

usage() {
  cat <<'USAGE'
Rod Mobile Codespaces

Uso:
  curl -fsSL https://raw.githubusercontent.com/rodkisten/codespaces/main/install.sh | bash
  curl -fsSL URL/install.sh | bash -s -- --force
  curl -fsSL URL/install.sh | bash -s -- --shell --force

Opções:
  --devcontainer        Copia .devcontainer/ para o repositório atual (padrão).
  --shell               Instala somente Zsh/Oh My Zsh/tema/Nano no ambiente atual.
                        Não instala Node, Python, gcloud ou outras CLIs do Dockerfile.
  --both                Instala .devcontainer e configuração do shell atual.
  --target DIR          Diretório do projeto, quando usar --devcontainer/--both.
  --force               Faz backup e substitui configurações existentes.
  --dry-run             Só mostra o que seria alterado.
  --help                Mostra esta mensagem.

As CLIs completas são instaladas ao reconstruir o devcontainer.
USAGE
}

log() { printf '\033[36m%s\033[0m %s\n' '[rod-mobile]' "$*" >&2; }
warn() { printf '\033[33m%s\033[0m %s\n' '[aviso]' "$*" >&2; }
fail() { printf '\033[31m%s\033[0m %s\n' '[erro]' "$*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --devcontainer) MODE='devcontainer' ;;
    --shell) MODE='shell' ;;
    --both) MODE='both' ;;
    --target)
      (($# >= 2)) || fail 'Faltou o caminho depois de --target.'
      TARGET="$2"
      shift
      ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --help|-h) usage; exit 0 ;;
    *) fail "Opção desconhecida: $1 (use --help)" ;;
  esac
  shift
done

for cmd in base64 tar mktemp cp mv mkdir; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Comando obrigatório ausente: $cmd"
done

TARGET="$(cd -- "$TARGET" 2>/dev/null && pwd -P)" || fail 'Diretório --target inexistente.'
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/rod-mobile.XXXXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT

# Arquivo embutido: não depende de branch, release, tarball remoto nem GitHub API.
# Uma única solicitação HTTP baixa tudo o que é necessário para copiar o devcontainer.
log 'Extraindo pacote embutido...'
base64 -d <<'ROD_MOBILE_EMBEDDED_ARCHIVE' | tar -xz -C "$STAGING"
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
pz8Ak+FeFwB4AAA=
ROD_MOBILE_EMBEDDED_ARCHIVE

test -f "$STAGING/.devcontainer/Dockerfile" || fail 'Pacote incompleto: Dockerfile ausente.'
test -f "$STAGING/.devcontainer/devcontainer.json" || fail 'Pacote incompleto: devcontainer.json ausente.'

# Backups com nome único, no mesmo diretório do arquivo substituído.
backup_existing() {
  local path="$1" backup stamp
  [[ -e "$path" || -L "$path" ]] || return 0
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup="${path}.backup-${stamp}"
  local n=0
  while [[ -e "$backup" || -L "$backup" ]]; do
    n=$((n + 1))
    backup="${path}.backup-${stamp}-${n}"
  done
  mv -- "$path" "$backup"
  log "Backup: $backup"
}

preflight_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]] && (( !FORCE )); then
    fail "Já existe: $path. Use --force para fazer backup e substituir."
  fi
}

install_devcontainer() {
  local target_path="$TARGET/.devcontainer"
  preflight_path "$target_path"
  if (( DRY_RUN )); then
    log "Simulação: copiaria .devcontainer/ para $target_path"
    return
  fi
  backup_existing "$target_path"
  cp -a -- "$STAGING/.devcontainer" "$target_path"
  log "Devcontainer instalado em $target_path"
  log 'Próximo passo: reconstruir o Codespace (Codespaces: Rebuild Container).'
}

install_shell() {
  local home="${HOME:?HOME não configurado}"
  local plugin_root="$home/.oh-my-zsh/custom/plugins"
  local theme_path="$home/.oh-my-zsh/custom/themes/rod-mobile.zsh-theme"
  local zshrc="$home/.zshrc"
  local nanorc="$home/.nanorc"
  local doctor="$home/.local/bin/mobile-doctor"

  command -v git >/dev/null 2>&1 || fail 'Git é necessário para instalar Oh My Zsh e plugins.'
  command -v zsh >/dev/null 2>&1 || fail 'Zsh não encontrado. Use --devcontainer ou instale o pacote zsh primeiro.'
  if [[ -e "$home/.oh-my-zsh" && ! -f "$home/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    fail "Existe ~/.oh-my-zsh, mas parece incompleto. Verifique manualmente antes de continuar."
  fi
  for path in "$theme_path" "$zshrc" "$nanorc" "$doctor"; do
    preflight_path "$path"
  done
  if (( DRY_RUN )); then
    log "Simulação: instalaria Oh My Zsh e plugins se necessários; copiaria arquivos para $home"
    return
  fi
  if [[ ! -f "$home/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    log 'Instalando Oh My Zsh sem executar instaladores remotos...'
    git clone --quiet --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$home/.oh-my-zsh"
  fi
  mkdir -p -- "$plugin_root" "$home/.oh-my-zsh/custom/themes" "$home/.local/bin"
  local entries=(
    'zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions.git'
    'zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git'
    'zsh-completions|https://github.com/zsh-users/zsh-completions.git'
  )
  local entry name url
  for entry in "${entries[@]}"; do
    name="${entry%%|*}"
    url="${entry#*|}"
    if [[ ! -e "$plugin_root/$name" ]]; then
      log "Plugin: $name"
      git clone --quiet --depth=1 "$url" "$plugin_root/$name"
    fi
  done
  for path in "$theme_path" "$zshrc" "$nanorc" "$doctor"; do
    backup_existing "$path"
  done
  cp -- "$STAGING/.devcontainer/zsh/zshrc" "$zshrc"
  cp -- "$STAGING/.devcontainer/nano/nanorc" "$nanorc"
  cp -- "$STAGING/.devcontainer/zsh/rod-mobile.zsh-theme" "$theme_path"
  cp -- "$STAGING/.devcontainer/scripts/doctor.sh" "$doctor"
  chmod 0755 "$doctor"
  zsh -n "$zshrc"
  zsh -n "$theme_path"
  log 'Configuração do shell instalada. Execute: exec zsh'
  warn 'O modo --shell não instala as CLIs do Dockerfile. Para todas as ferramentas, use --devcontainer e reconstrua.'
}

case "$MODE" in
  devcontainer) install_devcontainer ;;
  shell) install_shell ;;
  both)
    # Preflight combinado para evitar uma instalação parcial por conflito de dotfiles.
    preflight_path "$TARGET/.devcontainer"
    install_shell
    install_devcontainer
    ;;
esac
log 'Concluído.'