#!/usr/bin/env bash
# Tailscale in userspace networking mode for unprivileged Codespaces.
set -Eeuo pipefail
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/rod-codespaces/tailscale"
socket="$state_dir/tailscaled.sock"
state="$state_dir/tailscaled.state"
log="$state_dir/tailscaled.log"
mkdir -p "$state_dir"
chmod 700 "$state_dir"
export TS_SOCKET="$socket"

daemon_running() { [[ -S "$socket" ]] && tailscale --socket="$socket" status >/dev/null 2>&1; }
start_daemon() {
  command -v tailscaled >/dev/null || { echo "tailscaled not installed" >&2; return 1; }
  if daemon_running; then
    echo "Tailscale daemon already running"
    return 0
  fi
  # A stale socket can survive a crashed daemon; remove only when inactive.
  rm -f "$socket"
  nohup tailscaled --tun=userspace-networking --socket="$socket" --state="$state" >>"$log" 2>&1 </dev/null &
  local i
  for i in {1..40}; do
    [[ -S "$socket" ]] && { echo "Tailscale userspace daemon ready"; return 0; }
    sleep 0.25
  done
  echo "Tailscale failed to start; inspect $log" >&2
  return 1
}
case "${1:-start}" in
  start) start_daemon ;;
  up)
    start_daemon
    shift
    # No automatic auth keys. Login URL is shown interactively on first use.
    tailscale --socket="$socket" up "$@"
    ;;
  status)
    tailscale --socket="$socket" status
    ;;
  ip)
    tailscale --socket="$socket" ip -4
    ;;
  ping)
    [[ $# == 2 ]] || { echo "Usage: $0 ping HOST" >&2; exit 2; }
    tailscale --socket="$socket" ping "$2"
    ;;
  logs) tail -n 80 "$log" ;;
  *)
    echo "Usage: $0 {start|up|status|ip|ping HOST|logs}" >&2
    exit 2
    ;;
esac
