#!/usr/bin/env bash
set -euo pipefail

REPO="${ROD_REPO:-rodkisten/codespaces}"
ORIG_PWD="$PWD"

# Guarda todas as flags originais passadas para este script (ex: --force, --shell, --bootstrap)
FORWARD_ARGS=("$@")

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rod-release.XXXXXXXX")"
trap 'rm -rf -- "$TMP_DIR"' EXIT

download_latest_release() {
  local repo="$1"
  local dest_dir="$2"

  # 1. Se o gh CLI estiver instalado e autenticado, usa ele direto (suporta repos privados)
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh release download --repo "$repo" \
      --pattern "*.tar.gz" \
      --pattern "*.zip" \
      --dir "$dest_dir"
    return 0
  fi

  # 2. Fallback universal via API do GitHub + curl (não exige gh CLI)
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local auth_header=()
  if [[ -n "${GITHUB_TOKEN:-${GH_TOKEN:-}}" ]]; then
    auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN:-$GH_TOKEN}")
  fi

  local release_json
  release_json="$(curl -fsSL "${auth_header[@]}" "$api_url")"

  # Extrai a URL do primeiro asset .tar.gz ou .zip
  local asset_url asset_name
  if command -v jq >/dev/null 2>&1; then
    asset_url="$(printf '%s' "$release_json" | jq -r '.assets[] | select(.name | test("\\.(tar\\.gz|zip)$")) | .browser_download_url' | head -n 1)"
  else
    asset_url="$(printf '%s' "$release_json" | grep -oE '"browser_download_url":\s*"[^"]+\.(tar\.gz|zip)"' | head -n 1 | cut -d'"' -f4)"
  fi

  [[ -n "$asset_url" ]] || {
    printf '\033[31m[erro]\033[0m Nenhum asset .tar.gz ou .zip encontrado na última release de %s.\n' "$repo" >&2
    exit 1
  }

  asset_name="$(basename "$asset_url")"
  curl -fsSL "${auth_header[@]}" "$asset_url" -o "$dest_dir/$asset_name"
}

# 1. Baixa o pacote da última release
download_latest_release "$REPO" "$TMP_DIR"

# 2. Localiza e extrai o arquivo (.tar.gz ou .zip)
ARCHIVE="$(find "$TMP_DIR" -maxdepth 1 -type f \( -name "*.tar.gz" -o -name "*.zip" \) | head -n 1)"
[[ -n "$ARCHIVE" ]] || { echo "Arquivo compactado não encontrado em $TMP_DIR" >&2; exit 1; }

EXTRACT_DIR="$TMP_DIR/extracted"
mkdir -p "$EXTRACT_DIR"

case "$ARCHIVE" in
  *.tar.gz)
    tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"
    ;;
  *.zip)
    command -v unzip >/dev/null 2>&1 || { echo "Comando 'unzip' ausente para extrair $ARCHIVE" >&2; exit 1; }
    unzip -q "$ARCHIVE" -d "$EXTRACT_DIR"
    ;;
esac

# 3. Localiza o installer.sh dentro da pasta extraída (mesmo se houver pasta raiz aninhada)
INSTALLER_NAME="installer.sh"
FOUND_PATH="$(find "$EXTRACT_DIR" -maxdepth 2 -type f -name "$INSTALLER_NAME" | head -n 1)"

if [[ -z "$FOUND_PATH" ]]; then
  echo "$INSTALLER_NAME não encontrado dentro da release." >&2
  echo "Conteúdos da pasta ($EXTRACT_DIR):" >&2
  ls -la "$EXTRACT_DIR" >&2
  exit 1
fi

# Converte para o caminho absoluto completo
INSTALLER="$(realpath "$FOUND_PATH")"

chmod +x "$INSTALLER"
# 4. Preserva o diretório original caso --target não tenha sido passado explicitamente
HAS_TARGET=0
for arg in "${FORWARD_ARGS[@]}"; do
  [[ "$arg" == "--target" || "$arg" == --target=* ]] && HAS_TARGET=1
done
(( HAS_TARGET )) || FORWARD_ARGS+=(--target "$ORIG_PWD")

# 5. Executa o instalador real propagando todas as flags
cd "$(dirname "$INSTALLER")" || exit 1
exec "$INSTALLER" --mode real-install "${FORWARD_ARGS[@]}"

