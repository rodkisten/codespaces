#!/bin/sh
set -eu

REPO="${RODLOG_REPO:-rodkisten/codespaces}"
WORKFLOW="rodlog.yml"
ARTIFACT="rodlog-main-binaries"
DEST="${RODLOG_INSTALL_DIR:-$HOME/.local/bin}"
HOOK="${RODLOG_INSTALL_HOOK:-none}"
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
case "$OS" in
  linux|darwin) ;;
  *) echo "Unsupported operating system: $OS" >&2; exit 1 ;;
esac
case "$HOOK" in
  none|bash|zsh|both) ;;
  *) echo "RODLOG_INSTALL_HOOK must be none, bash, zsh or both" >&2; exit 1 ;;
esac

command -v gh >/dev/null 2>&1 || {
  echo "GitHub CLI (gh) is required to download GitHub Actions artifacts." >&2
  echo "Install gh and authenticate using 'gh auth login'." >&2
  exit 1
}
command -v unzip >/dev/null 2>&1 || {
  echo "unzip is required" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

echo "🔎 Finding the latest successful main build for $REPO..."
RUN_ID="$(gh api -X GET "repos/$REPO/actions/workflows/$WORKFLOW/runs" \
  -f branch=main -f status=success -f event=push -f per_page=30 \
  --jq '.workflow_runs[] | select(.head_branch == "main") | .id' | head -n 1)"
[ -n "$RUN_ID" ] || {
  echo "No successful main build found. Merge rodlog into main first." >&2
  exit 1
}

echo "📦 Downloading artifact $ARTIFACT from run $RUN_ID..."
gh run download "$RUN_ID" -R "$REPO" -n "$ARTIFACT" -D "$TMP"

NAME="rodlog_${OS}_${ARCH}"
[ -f "$TMP/$NAME" ] && [ -f "$TMP/checksums.txt" ] || {
  echo "Missing binary or checksums in GitHub artifact" >&2
  exit 1
}

EXPECTED="$(awk -v f="$NAME" '$2==f {print $1}' "$TMP/checksums.txt")"
[ -n "$EXPECTED" ] || { echo "Missing checksum for $NAME" >&2; exit 1; }
if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$TMP/$NAME" | awk '{print $1}')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "$TMP/$NAME" | awk '{print $1}')"
else
  echo "sha256sum or shasum is required" >&2
  exit 1
fi
[ "$EXPECTED" = "$ACTUAL" ] || { echo "Checksum mismatch" >&2; exit 1; }

mkdir -p "$DEST"
install -m 755 "$TMP/$NAME" "$DEST/rodlog"
echo "🌈 Installed $DEST/rodlog (main build $RUN_ID)"

if [ "$HOOK" != none ]; then
  HOOKFILE="$HOME/.config/rodlog/hook.sh"
  mkdir -p "$HOME/.config/rodlog"
  gh api "repos/$REPO/contents/packages/rodlog/scripts/shell-hook.sh?ref=main" \
    -H "Accept: application/vnd.github.raw+json" > "$TMP/hook.sh"
  install -m 644 "$TMP/hook.sh" "$HOOKFILE"
  for shell in bash zsh; do
    case "$HOOK:$shell" in "$shell:$shell"|both:*) ;; *) continue ;; esac
    if [ "$shell" = bash ]; then rc="$HOME/.bashrc"; else rc="$HOME/.zshrc"; fi
    marker='# rodlog shell hook'
    if ! { [ -f "$rc" ] && grep -Fq "$marker" "$rc"; }; then
      printf '\n%s\n[ -f "$HOME/.config/rodlog/hook.sh" ] && . "$HOME/.config/rodlog/hook.sh"\n' "$marker" >> "$rc"
    fi
    echo "🪝 Hook installed in $rc"
  done
fi
echo "Run: $DEST/rodlog version"
