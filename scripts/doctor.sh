#!/usr/bin/env bash
set -uo pipefail
failed=0
printf '\n🩺 Rod environment doctor\n'
for tool in zsh bash git gh curl wget awk jq go node npm pnpm docker gcloud wrangler python uv ssh rsync fzf rg micro tailscale tailscaled; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  ✓ %-12s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  ✗ %s missing\n' "$tool"
    failed=$((failed+1))
  fi
done
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then echo '  ✓ Docker daemon reachable'; else echo '  ! Docker daemon unavailable (check socket/permissions)'; fi
  if docker compose version >/dev/null 2>&1; then echo '  ✓ Docker Compose available'; else echo '  ! Docker Compose unavailable'; fi
fi
if [[ -L "$HOME/.zshrc" ]]; then echo '  ✓ ~/.zshrc linked to repository'; else echo '  ! ~/.zshrc not symlinked'; fi
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then echo '  ✓ nvm available'; else echo '  ! nvm not installed'; fi
if command -v tailscale >/dev/null 2>&1; then
  if [[ -S "${XDG_STATE_HOME:-$HOME/.local/state}/rod-codespaces/tailscale/tailscaled.sock" ]]; then
    echo '  ✓ Tailscale userspace daemon socket available'
  else
    echo '  ! Tailscale userspace daemon not started'
  fi
fi
printf '\nMissing required commands: %s\n' "$failed"
((failed == 0))
