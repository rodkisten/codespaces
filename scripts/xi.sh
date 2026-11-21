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
  xi git
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
 local repo="$1" version="$2" pattern="$3" json url name tmp arch
 repo_check "$repo"; need python3
 if [[ -z "$version" ]]; then json=$(gh_json "$repo" releases/latest); else
   version="${version#v}"; json=$(gh_json "$repo" "releases/tags/v$version" 2>/dev/null) || json=$(gh_json "$repo" "releases/tags/$version")
 fi
 arch=$(uname -m); [[ "$arch" == x86_64 ]] && arch=amd64
 local selection
 selection=$(printf '%s' "$json" | python3 -c 'import json,sys,re,os; d=json.load(sys.stdin); a=d.get("assets",[]); pat=os.environ.get("XI_ASSET",""); arch=os.environ.get("XI_ARCH",""); xs=[x for x in a if (not pat or re.search(pat,x["name"],re.I)) and (arch in x["name"].lower() or "universal" in x["name"].lower()) and x["name"].endswith((".deb",".tar.gz",".tgz",".zip"))]; print(xs[0]["browser_download_url"] if len(xs)==1 else "")' ) || :
 [[ -n "$selection" ]] || { say 'No unique compatible asset. Specify --asset REGEX'; return 1; }
 name="${selection##*/}"; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN
 say "Asset: $name"; confirm 'Download and install this release?' || return 1
 fetch -o "$tmp/$name" "$selection"
 case "$name" in
   *.deb) need dpkg; sudo dpkg -i "$tmp/$name" ;;
   *.tar.gz|*.tgz|*.zip) say "Downloaded to $tmp/$name; archive installation requires a manifest. No arbitrary binaries executed."; return 1 ;;
 esac
 record release "$repo@$version:$name"
}
main() {
 local action="${1:-help}" repo='' dir='' cmd=bash releases=0 version='' asset=''
 [[ "$action" == --yes ]] && { XI_YES=1; shift; action="${1:-help}"; }
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
    XI_ASSET="$asset" XI_ARCH="$(uname -m)" release_install "$repo" "$version" "$asset" ;;
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
  git) if command -v gum >/dev/null && [[ -t 0 ]]; then gum choose 'git status -sb' 'git log --oneline -10' 'git branch -vv' 'git fetch --prune' 'git diff --stat'; else printf '%s\n' 'git status -sb' 'git log --oneline -10' 'git branch -vv' 'git fetch --prune' 'git diff --stat'; fi ;;
  */*) install_repo "$action" '' bash '' ;;
  *) fail "Unknown command: $action";;
 esac
}
main "$@"
