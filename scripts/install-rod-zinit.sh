#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ -n "${HOME:-}" ]] || exit 1
command -v zsh >/dev/null || { echo 'Install zsh first' >&2; exit 1; }
command -v git >/dev/null || { echo 'Install git first' >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC_DIR="$(cd -- "$SCRIPT_DIR/../config/zsh" && pwd)"
SRC="$CONFIG_SRC_DIR/rod-zinit.zshrc"
[[ -f "$SRC" ]] || { echo "Missing $SRC" >&2; exit 1; }

# 1. Backup condicional (só gera se já houver .zshrc)
TARGET="$HOME/.zshrc"
if [[ -f "$TARGET" ]]; then
  BACKUP="$TARGET.backup-$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$TARGET" "$BACKUP"
  echo "📦 Backup: $BACKUP"
fi

# 2. Instala Zinit e corrige permissões (evita erro de insecure directories no compinit)
ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
  mkdir -p "$(dirname "$ZINIT_HOME")"
  git clone --depth 1 --quiet https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
chmod -R go-w "$(dirname "$ZINIT_HOME")" 2>/dev/null || true

# 3. Copia arquivos de configuração e scripts auxiliares
ZSH_CFG_DIR="$HOME/.config/zsh"
SCRIPTS_DIR="$HOME/.local/share/rod/codespaces/scripts"
mkdir -p "$ZSH_CFG_DIR" "$SCRIPTS_DIR"

cp "$SCRIPT_DIR/rod-notify-debug.py" "$SCRIPTS_DIR/rod-notify-debug.py"
cp "$CONFIG_SRC_DIR/rod-prompt-neon.zsh" "$ZSH_CFG_DIR/rod-prompt.zsh"
cp "$SRC" "$ZSH_CFG_DIR/rod-zinit.zsh"

if [[ ! -f "$ZSH_CFG_DIR/rod-prompt-neon.config.zsh" ]]; then
  cp "$CONFIG_SRC_DIR/rod-prompt-neon.config.zsh" "$ZSH_CFG_DIR/rod-prompt-neon.config.zsh"
fi

# 4. Injeta linha de carregamento idempotente no ~/.zshrc
SOURCE_LINE='[[ -r "$HOME/.config/zsh/rod-zinit.zsh" ]] && source "$HOME/.config/zsh/rod-zinit.zsh"'
touch "$TARGET"
if ! grep -Fqx "$SOURCE_LINE" "$TARGET"; then
  printf '\n# Rod Codespaces · managed Zinit configuration\n%s\n' "$SOURCE_LINE" >> "$TARGET"
fi

# 5. Valida sintaxe e pré-compila bytecode (.zwc) para boot instantâneo
zsh -n "$TARGET" "$ZSH_CFG_DIR/rod-zinit.zsh" "$ZSH_CFG_DIR/rod-prompt.zsh"
zsh -c '
  for f in "$HOME/.zshrc" "$HOME/.config/zsh/"*.zsh; do
    [[ -r "$f" ]] && zcompile "$f" 2>/dev/null || true
  done
'

echo '💜 Zinit + Rod Prompt Neon installed. Run: exec zsh'
