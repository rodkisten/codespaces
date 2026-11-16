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

daemon_running() {
  [[ -S "$socket" ]] || return 1
  # A logged-out daemon is alive even when 'tailscale status' exits nonzero.
  # Check for a meaningful response instead of requiring an authenticated status.
  local output
  output="$(timeout 3 tailscale --socket="$socket" status 2>&1)" && return 0
  [[ "$output" == *"Logged out."* || "$output" == *"NeedsLogin"* ]]
}
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
    if daemon_running; then
      echo "Tailscale userspace daemon ready"
      return 0
    fi
    sleep 0.25
  done
  echo "Tailscale failed to start; inspect $log" >&2
  tail -n 25 "$log" >&2 || true
  return 1
}
is_connected() {
  [[ "$(tailscale --socket="$socket" status --json 2>/dev/null | jq -r '.BackendState // empty')" == "Running" ]]
}
auto_login() {
  start_daemon
  if is_connected; then
    echo "Tailscale already connected"
    return 0
  fi
  if [[ -z "${TAILSCALE_AUTHKEY:-}" ]]; then
    echo "Tailscale auth key not set; run: bash scripts/tailscale.sh up"
    return 0
  fi
  local key_file
  key_file="$(mktemp "$state_dir/authkey.XXXXXXXX")"
  chmod 600 "$key_file"
  trap 'rm -f "$key_file"' RETURN
  printf '%s' "$TAILSCALE_AUTHKEY" >"$key_file"
  # file: avoids exposing the key in argv and logs.
  if timeout 45 tailscale --socket="$socket" up --auth-key="file:$key_file" >/dev/null 2>&1 && is_connected; then
    echo "Tailscale authenticated via Codespaces secret"
  else
    echo "WARN: Tailscale authentication failed (key may be expired or invalid)" >&2
    return 1
  fi
}
doctor() {
  printf 'Tailscale userspace diagnostic\\n'
  command -v tailscale >/dev/null || { echo "ERROR: tailscale CLI missing"; return 1; }
  command -v tailscaled >/dev/null || { echo "ERROR: tailscaled missing"; return 1; }
  if ! daemon_running; then
    echo "ERROR: daemon unavailable"
    echo "Log: $log"
    return 1
  fi
  echo "Daemon: running"
  if is_connected; then
    echo "Tailnet: connected"
    tailscale --socket="$socket" ip -4 || true
  else
    echo "Tailnet: disconnected or login required"
    [[ -n "${TAILSCALE_AUTHKEY:-}" ]] && echo "Codespaces auth secret: present" || echo "Codespaces auth secret: missing"
    return 1
  fi
}
case "${1:-start}" in
  auto) auto_login ;;
  doctor) doctor ;;
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
    echo "Usage: $0 {start|auto|up|status|ip|ping HOST|doctor|logs}" >&2
    exit 2
    ;;
esac
