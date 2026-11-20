#!/usr/bin/env bash
# Rod Debian installer: immutable GitHub Release asset, never main archive.
set -Eeuo pipefail
REPO="rodkisten/codespaces"
VERSION="__ROD_VERSION__"
ASSET="rod-debian.zip"
API="https://api.github.com/repos/$REPO/releases"
usage() { printf 'Usage: bash installer [--check|--self-update|--dry-run] [Debian installer options]\n'; }
die() { printf 'rod-debian: %s\n' "$*" >&2; exit 1; }
for cmd in curl python3 unzip sha256sum mktemp; do command -v "$cmd" >/dev/null || die "Missing $cmd"; done
MODE=install
ARGS=()
for arg in "$@"; do
  case "$arg" in --check) MODE=check;; --self-update) MODE=update;; --help|-h) usage; exit 0;; *) ARGS+=("$arg");; esac
done
[[ "$MODE" == update ]] && VERSION=latest
api_get() { curl -fsSL --retry 2 --connect-timeout 10 --max-time 40 -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$1"; }
release_url="$API/latest"
if [[ "$VERSION" != latest ]]; then
  [[ "$VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Invalid release version: $VERSION"
  release_url="$API/tags/$VERSION"
fi
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
api_get "$release_url" > "$tmp/release.json" || die "Release unavailable: $VERSION"
python3 - "$tmp/release.json" "$ASSET" > "$tmp/metadata" <<'PY'
import json,sys
data=json.load(open(sys.argv[1]))
assets=[a for a in data.get("assets",[]) if a.get("name")==sys.argv[2]]
if len(assets)!=1: sys.exit("Missing unique ZIP asset")
asset=assets[0]
digest=asset.get("digest","")
if not digest.startswith("sha256:") or len(digest)!=71: sys.exit("Missing SHA256 digest")
print(data["tag_name"])
print(asset["browser_download_url"])
print(digest.removeprefix("sha256:"))
PY
mapfile -t metadata < "$tmp/metadata"
tag="${metadata[0]}"
url="${metadata[1]}"
digest="${metadata[2]}"
printf 'Rod Debian release: %s\n' "$tag"
installed_version_file="/var/lib/rod-debian/version"
current="$(cat "$installed_version_file" 2>/dev/null || true)"
if [[ "$MODE" == check || "$MODE" == update ]]; then
  printf 'Installed: %s | Available: %s\n' "${current:-unknown}" "$tag"
  [[ "$MODE" == check || "$current" == "$tag" ]] && exit 0
fi
curl -fL --retry 2 --connect-timeout 10 --max-time 180 "$url" -o "$tmp/release.zip"
printf '%s  %s\n' "$digest" "$tmp/release.zip" | sha256sum -c - >/dev/null || die 'SHA256 mismatch'
python3 - "$tmp/release.zip" <<'PY'
import sys,zipfile,pathlib
with zipfile.ZipFile(sys.argv[1]) as z:
    for entry in z.infolist():
        p=pathlib.PurePosixPath(entry.filename)
        if p.is_absolute() or '..' in p.parts or entry.filename.startswith('\\'):
            sys.exit('Unsafe ZIP path')
        if (entry.external_attr >> 16) & 0o170000 == 0o120000:
            sys.exit('ZIP symlink not allowed')
PY
mkdir -p "$tmp/unpacked"
unzip -q "$tmp/release.zip" -d "$tmp/unpacked"
[[ -f "$tmp/unpacked/debian/install.sh" ]] || die 'Missing debian/install.sh in release'
bash -n "$tmp/unpacked/debian/install.sh" || die 'Invalid Debian installer syntax'
if [[ "$EUID" -ne 0 ]]; then
  die "Run as root with sudo; downloaded ZIP was verified but not installed"
fi
ROD_RELEASE_ROOT="$tmp/unpacked" bash "$tmp/unpacked/debian/install.sh" "${ARGS[@]}"
if [[ " ${ARGS[*]} " != *" --dry-run "* ]]; then
  mkdir -p /var/lib/rod-debian
  printf '%s\n' "$tag" > "$installed_version_file"
fi
printf 'Rod Debian installed: %s\n' "$tag"
