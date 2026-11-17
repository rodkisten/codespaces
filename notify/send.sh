#!/usr/bin/env bash
set -euo pipefail
CONFIG="${HOME}/.config/rod-notify/config"
[[ -f "$CONFIG" ]] && source "$CONFIG"
: "${ROD_NOTIFY_URL:=}"
: "${ROD_NOTIFY_TOKEN:=}"
[[ -n "$ROD_NOTIFY_URL" && -n "$ROD_NOTIFY_TOKEN" ]] || exit 0
[[ "$ROD_NOTIFY_URL" == https://* ]] || exit 0
command -v curl >/dev/null || exit 0
command -v python3 >/dev/null || exit 0
export ROD_N_COMMAND="${1:-command}" ROD_N_DIR="${2:-}" ROD_N_DURATION="${3:-0}" ROD_N_EXIT="${4:-0}"
payload="$(python3 - <<'PY'
import json,os
e=os.environ
rc=int(e["ROD_N_EXIT"])
print(json.dumps({"title":("✅ Comando concluído" if rc==0 else "❌ Comando falhou"),"message":f'{e["ROD_N_COMMAND"][:80]} · {e["ROD_N_DIR"][:80]} · {float(e["ROD_N_DURATION"]):.1f}s · exit {rc}'},ensure_ascii=False))
PY
)"
# Token via stdin/config, not in shell command history; curl process arguments still contain auth header.
curl --silent --show-error --fail --max-time 8 --retry 1 --retry-delay 1 \
  -H "Authorization: Bearer $ROD_NOTIFY_TOKEN" \
  -H 'Content-Type: application/json' \
  --data-binary "$payload" "$ROD_NOTIFY_URL" >/dev/null
