#!/usr/bin/env bash
set -euo pipefail
BASE="https://raw.githubusercontent.com/rodkisten/codespaces/main"
DIR="${HOME}/.config/rod-notify"
mkdir -p "$DIR" "${HOME}/.config/zsh"
chmod 700 "$DIR"
curl -fsSL "$BASE/notify/notify.zsh" -o "${HOME}/.config/zsh/rod-notify.zsh"
curl -fsSL "$BASE/notify/send.sh" -o "$DIR/send.sh"
chmod 700 "$DIR/send.sh"
touch "$DIR/config"
chmod 600 "$DIR/config"
touch "${HOME}/.zshrc"
if ! grep -Fq 'source "$HOME/.config/zsh/rod-notify.zsh"' "${HOME}/.zshrc"; then
  printf '\n# Rod Notify (Zsh command duration)\nsource "$HOME/.config/zsh/rod-notify.zsh"\n' >> "${HOME}/.zshrc"
fi
printf 'Rod Notify instalado. Configure ~/.config/rod-notify/config e execute: exec zsh\n'
