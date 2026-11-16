#!/bin/sh
set -eu
REPO="rodkisten/codespaces"
VERSION="${RODLOG_VERSION:-latest}"
DEST="${RODLOG_INSTALL_DIR:-$HOME/.local/bin}"
HOOK="${RODLOG_INSTALL_HOOK:-none}"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in x86_64) ARCH=amd64;; aarch64|arm64) ARCH=arm64;; *) echo "unsupported architecture: $ARCH" >&2; exit 1;; esac
case "$OS" in linux|darwin) :;; *) echo "unsupported operating system: $OS" >&2; exit 1;; esac
case "$HOOK" in none|bash|zsh|both) :;; *) echo "RODLOG_INSTALL_HOOK must be none, bash, zsh or both" >&2; exit 1;; esac
if [ "$VERSION" = latest ]; then BASE="https://github.com/$REPO/releases/latest/download"; else BASE="https://github.com/$REPO/releases/download/$VERSION"; fi
NAME="rodlog_${OS}_${ARCH}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
download() {
 if command -v curl >/dev/null 2>&1; then curl -fLsS "$1" -o "$2"
 elif command -v wget >/dev/null 2>&1; then wget -qO "$2" "$1"
 else echo "curl or wget is required" >&2; exit 1; fi
}
download "$BASE/$NAME" "$TMP/$NAME"
download "$BASE/checksums.txt" "$TMP/checksums.txt"
EXPECTED="$(awk -v f="$NAME" '$2==f {print $1}' "$TMP/checksums.txt")"
[ -n "$EXPECTED" ] || { echo "checksum not found" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then ACTUAL="$(sha256sum "$TMP/$NAME" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then ACTUAL="$(shasum -a 256 "$TMP/$NAME" | awk '{print $1}')"
else echo "sha256sum or shasum required" >&2; exit 1; fi
[ "$EXPECTED" = "$ACTUAL" ] || { echo "checksum mismatch" >&2; exit 1; }
mkdir -p "$DEST"
install -m 755 "$TMP/$NAME" "$DEST/rodlog"
echo "🌈 Installed $DEST/rodlog"
if [ "$HOOK" != none ]; then
 HOOKFILE="$HOME/.config/rodlog/hook.sh"
 mkdir -p "$HOME/.config/rodlog"
 download "https://raw.githubusercontent.com/$REPO/${RODLOG_HOOK_REF:-main}/packages/rodlog/scripts/shell-hook.sh" "$TMP/hook.sh"
 install -m 644 "$TMP/hook.sh" "$HOOKFILE"
 for shell in bash zsh; do
  case "$HOOK:$shell" in "$shell:$shell"|both:*) :;; *) continue;; esac
  if [ "$shell" = bash ]; then rc="$HOME/.bashrc"; else rc="$HOME/.zshrc"; fi
  marker='# rodlog shell hook'
  if ! { [ -f "$rc" ] && grep -Fq "$marker" "$rc"; }; then
   printf '\n%s\n[ -f "$HOME/.config/rodlog/hook.sh" ] && . "$HOME/.config/rodlog/hook.sh"\n' "$marker" >> "$rc"
  fi
  echo "Hook installed in $rc"
 done
fi
echo "Add $DEST to PATH and run: rodlog exec -- npm run build"
