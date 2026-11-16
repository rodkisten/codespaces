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
  if tailscale --socket="$socket" up --auth-key="file:$key_file" >/dev/null 2>&1; then
    echo "Tailscale authenticated via Codespaces secret"
  else
    echo "WARN: Tailscale authentication failed (key may be expired or invalid)" >&2
    return 1
  fi
}
case "${1:-start}" in
  auto) auto_login ;;
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
