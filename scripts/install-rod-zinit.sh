#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
[[ -n "${HOME:-}" ]] || exit 1
command -v zsh >/dev/null || { echo 'Install zsh first'; exit 1; }
command -v git >/dev/null || { echo 'Install git first'; exit 1; }
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../config/zsh/rod-zinit.zshrc"
[[ -f "$SRC" ]] || { echo "Missing $SRC"; exit 1; }
TARGET="$HOME/.zshrc"
BACKUP="$TARGET.backup-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -f "$TARGET" ]] || cp -p "$TARGET" "$BACKUP"
echo "📦 Backup: $BACKUP"
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone --depth 1 https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
mkdir -p "$HOME/.config/zsh" "$HOME/.local/share/rod/codespaces/scripts"
cp "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rod-notify-debug.py" "$HOME/.local/share/rod/codespaces/scripts/rod-notify-debug.py"
cp "$SRC" "$TARGET.tmp"
zsh -n "$TARGET.tmp"
mv "$TARGET.tmp" "$TARGET"
# Preserve installed Rod Prompt and Rod Notify. Do not modify Relay credentials.
echo '💜 Installed. Run: exec zsh'
