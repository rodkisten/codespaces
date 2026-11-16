#!/usr/bin/env bash
# Private SSH/SFTP diagnostics. No credentials, dotfiles or sync configuration are read.
set -Eeuo pipefail

usage() {
  cat <<'HELP'
Usage: bash scripts/private-ssh.sh doctor [host] [user]
       bash scripts/private-ssh.sh ssh HOST USER
       bash scripts/private-ssh.sh sftp HOST USER
       bash scripts/private-ssh.sh tailscale

HOST should be a Tailscale IP (100.x.y.z) or MagicDNS name.
This helper never enables SSH servers, copies keys, or modifies ~/.ssh/config.
Authentication uses the existing OpenSSH agent or an interactive prompt.
HELP
}
action="${1:-doctor}"
case "$action" in
  doctor)
    printf '🔐 Private SSH/SFTP doctor\n'
    for tool in ssh sftp ssh-keygen tailscale; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '  ✓ %-12s %s\n' "$tool" "$(command -v "$tool")"
      else
        printf '  ! %-12s unavailable\n' "$tool"
      fi
    done
    if command -v tailscale >/dev/null 2>&1; then
      tailscale status || printf '  ! Tailscale not connected\n'
    fi
    if [[ -n "${2:-}" ]]; then
      host="$2"
      if [[ ! "$host" =~ ^[a-zA-Z0-9._:-]+$ || "$host" == -* ]]; then
        echo 'Invalid host' >&2; exit 2
      fi
      echo "Checking TCP port 22 on $host"
      if timeout 6 bash -c 'exec 3<>/dev/tcp/"$1"/22' _ "$host" 2>/dev/null; then
        echo '  ✓ TCP/22 reachable'
      else
        echo '  ! TCP/22 unavailable (ACL, firewall, sshd or network)'
      fi
    fi
    ;;
  tailscale)
    command -v tailscale >/dev/null || { echo 'Tailscale CLI not installed' >&2; exit 1; }
    tailscale status
    ;;
  ssh|sftp)
    [[ $# == 3 ]] || { usage >&2; exit 2; }
    host="$2"; user="$3"
    [[ "$host" =~ ^[a-zA-Z0-9._:-]+$ && "$host" != -* ]] || { echo 'Invalid host' >&2; exit 2; }
    [[ "$user" =~ ^[a-zA-Z_][a-zA-Z0-9_.-]*$ ]] || { echo 'Invalid user' >&2; exit 2; }
    # StrictHostKeyChecking=ask preserves verification on first connection.
    # BatchMode=no permits interactive authentication without copying keys.
    exec "$action" -o StrictHostKeyChecking=ask -o ConnectTimeout=10 -o ServerAliveInterval=20 -- "$user@$host"
    ;;
  *) usage >&2; exit 2 ;;
esac
