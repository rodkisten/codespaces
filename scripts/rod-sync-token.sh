#!/usr/bin/env bash
# Renew the existing GitHub App installation token without printing credentials.
set -Eeuo pipefail
umask 077
[[ -n "${BOT_APP_ID:-}" && -n "${BOT_PRIVATE_KEY:-}" ]] || { echo "[FAIL] Missing BOT_APP_ID or BOT_PRIVATE_KEY" >&2; exit 1; }
for cmd in openssl jq curl; do command -v "$cmd" >/dev/null || { echo "[FAIL] Missing $cmd" >&2; exit 1; }; done
base64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | base64url)"
payload="$(printf '{"iat":%s,"exp":%s,"iss":"%s"}' "$((now-60))" "$((now+480))" "$BOT_APP_ID" | base64url)"
unsigned="$header.$payload"
signature="$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign <(printf '%s\n' "$BOT_PRIVATE_KEY") | base64url)"
jwt="$unsigned.$signature"
api=https://api.github.com
installation="$(curl -fsS --retry 2 -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" "$api/repos/rodkisten/ssh/installation" | jq -er '.id')"
token="$(curl -fsS --retry 2 -X POST -H "Authorization: Bearer $jwt" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" "$api/app/installations/$installation/access_tokens" -d '{"repositories":["ssh"],"permissions":{"contents":"write"}}' | jq -er '.token')"
dir="$HOME/.local/state/rod-ssh-sync"
mkdir -p "$dir"; chmod 700 "$dir"
tmp="$(mktemp "$dir/.token.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
printf '%s' "$token" > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$dir/token"
echo "[OK] Renewed scoped GitHub App token for rodkisten/ssh"
