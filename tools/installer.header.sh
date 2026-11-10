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
