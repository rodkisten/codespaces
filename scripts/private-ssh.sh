#!/usr/bin/env bash
# SSH/SFTP through the Tailscale userspace daemon, without a TUN device.
set -Eeuo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/rod-codespaces/tailscale"
socket="$state_dir/tailscaled.sock"
usage() {
  cat <<'HELP'
Usage: bash scripts/private-ssh.sh doctor [HOST]
       bash scripts/private-ssh.sh ssh HOST USER
       bash scripts/private-ssh.sh sftp HOST USER
       bash scripts/private-ssh.sh tailscale
SSH and SFTP use Tailscale's userspace TCP proxy (tailscale nc).
First login: bash scripts/tailscale.sh up
HELP
}
valid_host() {
  [[ "$1" =~ ^[a-zA-Z0-9._:-]+$ && "$1" != -* ]]
}
action="${1:-doctor}"
case "$action" in
  doctor)
    printf '🔐 SSH/SFTP through Tailscale userspace\n'
    for tool in ssh sftp tailscale tailscaled; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '  ✓ %s available\n' "$tool"
      else
        printf '  ! %s unavailable\n' "$tool"
      fi
    done
    if [[ -S "$socket" ]]; then
      tailscale --socket="$socket" status || true
    else
      echo '  ! Tailscale daemon socket missing'
    fi
    if [[ -n "${2:-}" ]]; then
      valid_host "$2" || { echo 'Invalid host' >&2; exit 2; }
      tailscale --socket="$socket" ping "$2"
    fi
    ;;
  tailscale)
    exec bash "$repo_dir/tailscale.sh" status
    ;;
  ssh|sftp)
    [[ $# == 3 ]] || { usage >&2; exit 2; }
    host="$2"; user="$3"
    valid_host "$host" || { echo 'Invalid host' >&2; exit 2; }
    [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] || { echo 'Invalid user' >&2; exit 2; }
    bash "$repo_dir/tailscale.sh" start
    tailscale --socket="$socket" status >/dev/null || {
      echo 'Tailscale is not connected. Run: bash scripts/tailscale.sh up' >&2
      exit 1
    }
    # ProxyCommand uses Tailscale's own TCP dialer, so no system TUN is needed.
    # %h and %p are expanded by OpenSSH; strict host-key checks stay enabled.
    proxy="tailscale --socket=$socket nc %h %p"
    exec "$action" -o "ProxyCommand=$proxy" -o StrictHostKeyChecking=ask \
      -o ConnectTimeout=15 -o ServerAliveInterval=20 -- "$user@$host"
    ;;
  *) usage >&2; exit 2 ;;
esac
