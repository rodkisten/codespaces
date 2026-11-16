#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/rodlog" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$RODLOG_CAPTURE"
exit "${RODLOG_EXIT_CODE:-0}"
SH
cat > "$tmp/gcloud" <<'SH'
#!/bin/sh
echo original
SH
chmod +x "$tmp/rodlog" "$tmp/gcloud"
export PATH="$tmp:$PATH" RODLOG_CAPTURE="$tmp/capture"
export RODLOG_WRAP_COMMANDS=gcloud
source "$here/shell-hook.sh"
gcloud run services list
grep -Fxq 'exec' "$RODLOG_CAPTURE"
grep -Fxq -- '--tool=gcloud' "$RODLOG_CAPTURE"
grep -Fxq "$tmp/gcloud" "$RODLOG_CAPTURE"
grep -Fxq 'services' "$RODLOG_CAPTURE"
export RODLOG_EXIT_CODE=17
if gcloud run; then echo 'exit code not preserved' >&2; exit 1; else
  status=$?
  test "$status" -eq 17
fi
unset RODLOG_EXIT_CODE
bash -c '
  set -eu
  alias gcloud="printf aliased"
  export RODLOG_WRAP_COMMANDS=gcloud
  source "$1"
  alias gcloud | grep -q aliased
' _ "$here/shell-hook.sh"
bash -c '
  set -eu
  gcloud() { printf function; }
  export RODLOG_WRAP_COMMANDS=gcloud
  source "$1"
  test "$(gcloud)" = function
' _ "$here/shell-hook.sh"
bash -c '
  set -eu
  unset RODLOG_WRAP_COMMANDS
  source "$1"
  ! declare -F gcloud >/dev/null
' _ "$here/shell-hook.sh"
echo 'shell hook checks passed'
