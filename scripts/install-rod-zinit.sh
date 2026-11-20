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
cp "$(dirname "$SRC")/rod-prompt-neon.zsh" "$HOME/.config/zsh/rod-prompt.zsh"
if [[ ! -f "$HOME/.config/zsh/rod-prompt-neon.config.zsh" ]]; then
  cp "$(dirname "$SRC")/rod-prompt-neon.config.zsh" "$HOME/.config/zsh/rod-prompt-neon.config.zsh"
fi
zsh -n "$HOME/.config/zsh/rod-prompt.zsh"
# Preserve the user's .zshrc. A managed source line is idempotent.
# Existing aliases, environment variables and customisations remain intact.
SOURCE_LINE='[[ -r "$HOME/.config/zsh/rod-zinit.zshrc" ]] && source "$HOME/.config/zsh/rod-zinit.zshrc"'
cp "$SRC" "$HOME/.config/zsh/rod-zinit.zshrc"
zsh -n "$HOME/.config/zsh/rod-zinit.zshrc"
touch "$TARGET"
if ! grep -Fqx "$SOURCE_LINE" "$TARGET"; then
  printf '\n# Rod Codespaces · managed Zinit configuration\n%s\n' "$SOURCE_LINE" >> "$TARGET"
fi
zsh -n "$TARGET"
# Preserve installed Rod Prompt and Rod Notify. Do not modify Relay credentials.
echo '💜 Zinit + Rod Prompt Neon installed. Run: exec zsh'
