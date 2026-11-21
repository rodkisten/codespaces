#!/usr/bin/env bash
# xi • universal installer for Rod Codespaces
set -Eeuo pipefail
XI_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/xi"
XI_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/xi"
XI_BIN="$HOME/.local/bin"
mkdir -p "$XI_HOME" "$XI_STATE" "$XI_BIN"
CONFIG="$XI_HOME/xirc.sh"
[[ -f "$CONFIG" ]] || printf 'XI_AUTOUPDATE=false\nXI_ZSH_PKG=zinit\n' > "$CONFIG"
# Only load known, literal config values; never source arbitrary configuration.
config_get() { sed -n "s/^$1=//p" "$CONFIG" | tail -1; }
config_set() { local key="$1" val="$2" tmp; tmp=$(mktemp); grep -v "^$key=" "$CONFIG" > "$tmp" || :; printf '%s=%s\n' "$key" "$val" >> "$tmp"; mv "$tmp" "$CONFIG"; }
say() { printf '  %s\n' "$*"; }
fail() { printf 'xi: %s\n' "$*" >&2; exit 1; }
confirm() { [[ "${XI_YES:-0}" == 1 ]] && return 0; [[ -t 0 ]] || fail 'Confirmation required (use --yes)'; if command -v gum >/dev/null; then gum confirm "$1"; else read -r -p "$1 [y/N] " ans; [[ "$ans" == [yY]* ]]; fi; }
run() { if command -v gum >/dev/null && [[ -t 1 ]]; then gum spin --spinner dot --title "$1" -- "${@:2}"; else say "$1"; "${@:2}"; fi; }
need() { command -v "$1" >/dev/null || fail "Missing dependency: $1"; }
record() { printf '%s\t%s\t%s\n' "$1" "$2" "$(date -u +%FT%TZ)" >> "$XI_STATE/inventory.tsv"; }
fetch() { need curl; curl --fail --location --silent --show-error --retry 3 "$@"; }
usage() { cat <<'HELP'
xi [--yes] <command>
  xi OWNER/REPO                      Discover an installer from GitHub
  xi github [--releases] OWNER/REPO [--dir PATH] [--cmd bash]
  xi releases OWNER/REPO [-v VERSION] [--asset REGEX]
  xi zinit OWNER/PLUGIN
  xi zshrc add "line"
  xi config [--autoupdate true|false] [--zsh-pkg zinit] [zinit]
  xi inventory
  xi update [--all]
  xi git [run]                      Browse or execute safe Git snippets
  xi self-update
HELP
}
github_api() { fetch -H 'Accept: application/vnd.github+json' -H 'User-Agent: xi-installer' "https://api.github.com/repos/$1/$2"; }
gh_json() { if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then gh api "repos/$1/$2"; else github_api "$1" "$2"; fi; }
repo_check() { [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Expected OWNER/REPO'; }
install_repo() {
 local repo="$1" dir="$2" cmd="$3" ref="$4" tmp candidate
 repo_check "$repo"; need git; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
 if [[ -n "$ref" ]]; then git clone --quiet --depth 1 --branch "$ref" "https://github.com/$repo.git" "$tmp/repo" || fail 'Cannot clone release ref'
 else git clone --quiet --depth 1 "https://github.com/$repo.git" "$tmp/repo" || fail 'Cannot clone repository'; fi
 if [[ -z "$dir" ]]; then
   for candidate in install.sh scripts/install.sh scripts/bootstrap.sh bootstrap.sh; do
     [[ -f "$tmp/repo/$candidate" ]] && { dir="$candidate"; break; }
   done
 fi
 [[ -n "$dir" && -f "$tmp/repo/$dir" ]] || fail 'No known installer found. Specify --dir PATH'
 [[ "$(realpath -m "$tmp/repo/$dir")" == "$tmp/repo/"* ]] || fail 'Installer must be inside checkout'
 say "Repository: $repo | script: $dir | runner: $cmd"
 confirm "Execute reviewed repository installer?" || return 1
 (cd "$tmp/repo" && "$cmd" "$dir")
 record github "$repo@$ref:$dir"
}
release_install() {
 local repo="$1" version="$2" pattern="$3" json selection name url tmp arch choice
 repo_check "$repo"; need python3
 if [[ -z "$version" ]]; then json=$(gh_json "$repo" releases/latest); else
   version="${version#v}"
   json=$(gh_json "$repo" "releases/tags/v$version" 2>/dev/null) || json=$(gh_json "$repo" "releases/tags/$version")
 fi
 arch=$(uname -m)
 selection=$(XI_ASSET="$pattern" XI_ARCH="$arch" python3 -c '
import json,sys,re,os
data=json.load(sys.stdin); arch=os.environ["XI_ARCH"].lower()
aliases={"x86_64":("x86_64","amd64","x64"),"aarch64":("aarch64","arm64")}.get(arch,(arch,))
pattern=os.environ["XI_ASSET"]
for asset in data.get("assets",[]):
 name=asset["name"]; low=name.lower()
 if pattern and not re.search(pattern,name,re.I): continue
 if not low.endswith((".deb",".tar.gz",".tgz",".zip")): continue
 if not any(a in low for a in aliases) and not any(a in low for a in ("universal","all.","noarch")): continue
 print(name+chr(9)+asset["browser_download_url"])
' <<< "$json")
 [[ -n "$selection" ]] || fail 'No compatible release asset. Try --asset REGEX'
 if [[ $(printf '%s\n' "$selection" | wc -l) -gt 1 ]]; then
   if command -v gum >/dev/null && [[ -t 0 ]]; then
     choice=$(printf '%s\n' "$selection" | cut -f1 | gum choose --header 'Select release asset')
   elif [[ -t 0 ]]; then
     select choice in $(printf '%s\n' "$selection" | cut -f1); do [[ -n "$choice" ]] && break; done
   else fail 'Multiple assets match. Use --asset REGEX to select one'; fi
   selection=$(printf '%s\n' "$selection" | awk -F '\t' -v n="$choice" '$1==n {print;exit}')
 fi
 name=${selection%%$'\t'*}; url=${selection#*$'\t'}
 tmp=$(mktemp -d)
 say "Selected: $repo | $name"
 confirm 'Download this release asset?' || { rm -rf "$tmp"; return 1; }
 fetch -o "$tmp/$name" "$url"
 case "$name" in
  *.deb)
    need dpkg
    confirm "Install Debian package $name with sudo?" || { rm -rf "$tmp"; return 1; }
    sudo dpkg -i "$tmp/$name" ;;
  *.tar.gz|*.tgz|*.zip)
    need python3
    mkdir -p "$XI_HOME/downloads/$repo"
    # Validate archive paths and reject links before extracting.
    python3 - "$tmp/$name" "$XI_HOME/downloads/$repo" <<'PY'
import pathlib,sys,tarfile,zipfile
src=pathlib.Path(sys.argv[1]); dest=pathlib.Path(sys.argv[2]).resolve()
def safe(name):
 p=pathlib.PurePosixPath(name)
 if p.is_absolute() or ".." in p.parts or not name or "\\\\" in name:
  raise ValueError("Unsafe archive member: "+name)
 return p
if src.name.endswith(".zip"):
 with zipfile.ZipFile(src) as z:
  for i in z.infolist():
   safe(i.filename)
   if (i.external_attr >> 16) & 0o170000 == 0o120000: raise ValueError("Symlinks prohibited")
  z.extractall(dest)
else:
 with tarfile.open(src,"r:gz") as t:
  for m in t.getmembers():
   safe(m.name)
   if not (m.isfile() or m.isdir()): raise ValueError("Links and special files prohibited")
  t.extractall(dest,filter="data")
print("Archive extracted to",dest)
PY
    say 'Archive extracted only. Review files before installing binaries.' ;;
 esac
 record release "$repo@$version:$name"
 rm -rf "$tmp"
}
git_snippets() {
 local entries selected
 entries=$'status — git status -sb\nlog — git log --oneline -10\nbranches — git branch -vv\nfetch — git fetch --prune\ndiff — git diff --stat\nremotes — git remote -v'
 if [[ "${1:-}" == run ]]; then
   [[ -t 0 ]] || fail 'Interactive terminal required'
   if command -v gum >/dev/null; then selected=$(printf '%s\n' "$entries" | gum choose --header 'Git snippets')
   else printf '%s\n' "$entries"; read -r -p 'Enter snippet name: ' selected; fi
   case "${selected%% *}" in
     status) git status -sb;; log) git log --oneline -10;; branches) git branch -vv;;
     fetch) confirm 'Fetch remote refs?' && git fetch --prune;;
     diff) git diff --stat;; remotes) git remote -v;;
     *) fail 'Unknown snippet';;
   esac
 else printf '%s\n' "$entries"; fi
}

main() {
 local action="${1:-help}" repo='' dir='' cmd=bash releases=0 version='' asset=''
 if [[ "$action" == --yes ]]; then XI_YES=1; shift; action="${1:-help}"; fi
 [[ $# -gt 0 ]] && shift || :
 case "$action" in
  help|-h|--help) usage ;;
  github)
    while (($#)); do case "$1" in --releases) releases=1;; --dir) dir="${2:?}"; shift;; --cmd) cmd="${2:?}"; shift;; *) repo="$1";; esac; shift; done
    [[ -n "$repo" ]] || fail 'Missing repository'
    if ((releases)); then
      need python3
      local tag; tag=$(gh_json "$repo" releases/latest | python3 -c 'import json,sys;print(json.load(sys.stdin)["tag_name"])')
      install_repo "$repo" "$dir" "$cmd" "$tag"
    else install_repo "$repo" "$dir" "$cmd" ''; fi ;;
  releases)
    repo="${1:?Missing repository}"; shift
    while (($#)); do case "$1" in -v|--version) version="${2:?}"; shift;; --asset) asset="${2:?}"; shift;; *) fail "Unknown option: $1";; esac; shift; done
    XI_ASSET="$asset" XI_ARCH="$(uname -m | sed s/x86_64/amd64/)" release_install "$repo" "$version" "$asset" ;;
  zinit) need zsh; [[ "$(config_get XI_ZSH_PKG)" == zinit ]] || fail 'Set xi config --zsh-pkg zinit'; repo_check "${1:?}"; confirm "Install Zinit plugin $1?" && zsh -ic "zinit light '$1'" && record zinit "$1" ;;
  zshrc)
    [[ "${1:-}" == add && $# -eq 2 ]] || fail 'Usage: xi zshrc add "line"'
    touch "$HOME/.zshrc"; grep -Fxq -- "$2" "$HOME/.zshrc" || printf '\n%s\n' "$2" >> "$HOME/.zshrc"; say 'zshrc updated (idempotent)' ;;
  config)
    case "${1:-}" in
      --autoupdate) [[ "${2:-}" == true || "${2:-}" == false ]] || fail 'Use true or false'; config_set XI_AUTOUPDATE "$2";;
      --zsh-pkg) [[ "${2:-}" == zinit ]] || fail 'Only zinit supported'; config_set XI_ZSH_PKG "$2";;
      zinit) say 'Zinit settings: ~/.config/zsh and ~/.zshrc';;
      '') cat "$CONFIG";;
      *) fail 'Unknown config option';;
    esac ;;
  inventory) if [[ -f "$XI_STATE/inventory.tsv" ]]; then if command -v column >/dev/null; then column -ts $'\t' "$XI_STATE/inventory.tsv"; else cat "$XI_STATE/inventory.tsv"; fi; else say 'No managed installations'; fi ;;
  update) [[ "${1:-}" == --all ]] || fail 'Use xi update --all'; say 'Managed update checks: manual review required for GitHub scripts and release assets.'; [[ "$(config_get XI_AUTOUPDATE)" == true ]] && say 'Auto-update enabled for future verified providers; no blind execution.'; ;;
  self-update) local url="https://raw.githubusercontent.com/rodkisten/codespaces/main/scripts/xi.sh" tmp; tmp=$(mktemp); fetch -o "$tmp" "$url"; bash -n "$tmp"; confirm 'Replace local xi with verified Bash script?' && install -m 755 "$tmp" "$XI_BIN/xi"; rm -f "$tmp" ;;
  git) git_snippets "${1:-}" ;;
  */*) install_repo "$action" '' bash '' ;;
  *) fail "Unknown command: $action";;
 esac
}
main "$@"
