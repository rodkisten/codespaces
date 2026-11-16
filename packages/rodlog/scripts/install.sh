#!/bin/sh
set -eu
REPO="rodkisten/codespaces"
VERSION="${RODLOG_VERSION:-latest}"
DEST="${RODLOG_INSTALL_DIR:-$HOME/.local/bin}"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; *) echo "unsupported arch: $ARCH" >&2; exit 1;; esac
case "$OS" in linux|darwin) :;; *) echo "unsupported OS: $OS" >&2; exit 1;; esac
if [ "$VERSION" = latest ]; then BASE="https://github.com/$REPO/releases/latest/download"; else BASE="https://github.com/$REPO/releases/download/$VERSION"; fi
NAME="rodlog_${OS}_${ARCH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
download() { if command -v curl >/dev/null 2>&1; then curl -fLsS "$1" -o "$2"; elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"; else echo "curl or wget required" >&2; exit 1; fi; }
download "$BASE/$NAME" "$TMP/$NAME"
download "$BASE/checksums.txt" "$TMP/checksums.txt"
EXPECTED="$(awk -v f="$NAME" '$2==f {print $1}' "$TMP/checksums.txt")"
[ -n "$EXPECTED" ] || { echo "checksum missing" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then ACTUAL="$(sha256sum "$TMP/$NAME" | awk '{print $1}')"; else ACTUAL="$(shasum -a 256 "$TMP/$NAME" | awk '{print $1}')"; fi
[ "$EXPECTED" = "$ACTUAL" ] || { echo "checksum mismatch" >&2; exit 1; }
mkdir -p "$DEST"
install -m 755 "$TMP/$NAME" "$DEST/rodlog"
echo "🌈 Installed $DEST/rodlog"
echo "Add $DEST to PATH, then use: rodlog exec -- npm run build"
