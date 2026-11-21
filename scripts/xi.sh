#!/usr/bin/env bash
# ==============================================================================
# xi • Ultra-Fast, Zero-Python Universal Installer & GitHub Actions CLI
#
# Architecture Highlights:
#   - Zero Python dependency (Pure Bash + jq/awk + native tar/unzip).
#   - Single-pass capability probing at startup (zero repeated command -v forks).
#   - Out-of-band microsecond telemetry via BASH_XTRACEFD (--debug).
#   - Bi-directional Zsh Line Editor (ZLE) integration via state signal files.
# ==============================================================================

set -Eeuo pipefail

# ==============================================================================
# 1. XDG Base Directories & Global Constants
# ==============================================================================
readonly XI_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/xi"
readonly XI_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/xi"
readonly XI_BIN="$HOME/.local/bin"
readonly CONFIG="$XI_HOME/xirc.sh"
readonly INVENTORY="$XI_STATE/inventory.tsv"
readonly ZINIT_RELOAD_FLAG="$XI_STATE/.reload_zinit"
readonly DEBUG_LOG="$XI_STATE/debug.log"

# Bootstrap directories in a single mkdir syscall
mkdir -p "$XI_HOME" "$XI_STATE" "$XI_BIN"
[[ -f "$CONFIG" ]] || printf 'XI_AUTOUPDATE=false\nXI_ZSH_PKG=zinit\n' > "$CONFIG"

# ==============================================================================
# 2. Out-of-Band Debug Telemetry (--debug or XI_DEBUG=1)
#    Routes xtrace to a dedicated file descriptor (BASH_XTRACEFD) so TUI
#    renders (gum) and stdout pipes remain completely uncorrupted.
# ==============================================================================
XI_DEBUG="${XI_DEBUG:-0}"
for _arg in "$@"; do
  [[ "$_arg" == "--debug" ]] && XI_DEBUG=1
done

enable_debug() {
  exec {XI_XTRACE_FD}>"$DEBUG_LOG"
  export BASH_XTRACEFD="$XI_XTRACE_FD"
  # EPOCHREALTIME is a Bash 5+ built-in yielding microsecond precision at 0 CPU cost
  export PS4='+ [${EPOCHREALTIME}] (${BASH_SOURCE##*/}:${LINENO}:${FUNCNAME[0]:-main}) '
  set -x
}
(( XI_DEBUG )) && enable_debug

# ==============================================================================
# 3. Startup Capability Detection (Cached once; eliminates repeated forks)
# ==============================================================================
HAS_GUM=0; command -v gum >/dev/null 2>&1 && HAS_GUM=1
HAS_GH=0;  command -v gh  >/dev/null 2>&1 && HAS_GH=1
HAS_JQ=0;  command -v jq  >/dev/null 2>&1 && HAS_JQ=1
IS_TTY_IN=0;  [[ -t 0 ]] && IS_TTY_IN=1
IS_TTY_OUT=0; [[ -t 1 ]] && IS_TTY_OUT=1

# ==============================================================================
# 4. Pure-Bash Core Primitives (Zero Subshells / Zero External Spawns)
# ==============================================================================
say()  { printf '  %s\n' "$*"; }
fail() { printf 'xi: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"; }

# Reads KEY=VALUE from xirc.sh using parameter expansion (replaces sed + tail)
config_get() {
  local target="$1" line val=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$target="* ]] && val="${line#*=}"
  done < "$CONFIG"
  printf '%s\n' "$val"
}

# Atomically updates KEY=VALUE in memory (replaces mktemp + grep + mv)
config_set() {
  local key="$1" val="$2" line out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" == "$key="* || -z "$line" ]] && continue
    out+="$line"$'\n'
  done < "$CONFIG"
  printf '%s%s=%s\n' "$out" "$key" "$val" > "$CONFIG"
}

# Idempotently appends a line only if not already present (replaces touch + grep)
append_unique_line() {
  local file="$1" target="$2" line
  if [[ -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == "$target" ]] && return 0
    done < "$file"
  fi
  printf '\n%s\n' "$target" >> "$file"
}

# Interactive confirmation gate bypassed only when XI_YES=1 (--yes)
confirm() {
  [[ "${XI_YES:-0}" == 1 ]] && return 0
  (( IS_TTY_IN )) || fail 'Confirmation required (use --yes)'
  if (( HAS_GUM )); then
    gum confirm "$1"
  else
    local ans
    read -r -p "$1 [y/N] " ans
    [[ "$ans" == [yY]* ]]
  fi
}

# Appends audit log row using Bash 4.2+ built-in strftime (replaces `date` binary)
record() {
  local ts
  printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1
  printf '%s\t%s\t%s\n' "$1" "$2" "$ts" >> "$INVENTORY"
}

fetch() {
  need curl
  curl --fail --location --silent --show-error --retry 3 "$@"
}

repo_check() {
  [[ "$1" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail 'Expected OWNER/REPO'
}

# ==============================================================================
# 5. GitHub API & JSON Extraction Layer (Zero-Python)
# ==============================================================================
github_api() {
  fetch -H 'Accept: application/vnd.github+json' \
        -H 'User-Agent: xi-installer' \
        "https://api.github.com/repos/$1/$2"
}

gh_json() {
  if (( HAS_GH )) && gh auth status >/dev/null 2>&1; then
    gh api "repos/$1/$2"
  else
    github_api "$1" "$2"
  fi
}

# Extracts top-level .tag_name from release JSON via jq (~2ms) or pure AWK
json_extract_tag() {
  if (( HAS_JQ )); then
    jq -r '.tag_name // empty'
  else
    awk '
      BEGIN { RS="," }
      /"tag_name"[[:space:]]*:/ {
        match($0, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"/)
        if (RSTART) {
          s = substr($0, RSTART, RLENGTH)
          sub(/.*:[[:space:]]*"/, "", s)
          sub(/"$/, "", s)
          print s
          exit
        }
      }
    '
  fi
}

# ==============================================================================
# 6. Installation Providers (Repo Scripts, Binary Releases, Zinit, Git)
# ==============================================================================

# Provider A: Shallow-clones a repository and executes a reviewed installer script
install_repo() {
  local repo="$1" dir="$2" cmd="$3" ref="$4" tmp candidate
  repo_check "$repo"
  need git

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  if [[ -n "$ref" ]]; then
    git clone --quiet --depth 1 --branch "$ref" "https://github.com/$repo.git" "$tmp/repo" || fail 'Cannot clone release ref'
  else
    git clone --quiet --depth 1 "https://github.com/$repo.git" "$tmp/repo" || fail 'Cannot clone repository'
  fi

  if [[ -z "$dir" ]]; then
    for candidate in install.sh scripts/install.sh scripts/bootstrap.sh bootstrap.sh; do
      [[ -f "$tmp/repo/$candidate" ]] && { dir="$candidate"; break; }
    done
  fi

  [[ -n "$dir" && -f "$tmp/repo/$dir" ]] || fail 'No known installer found. Specify --dir PATH'
  # Security check: ensure resolved script stays inside the cloned directory
  [[ "$(realpath -m "$tmp/repo/$dir")" == "$tmp/repo/"* ]] || fail 'Installer must be inside checkout'

  say "Repository: $repo | script: $dir | runner: $cmd"
  confirm "Execute reviewed repository installer?" || return 1
  (cd "$tmp/repo" && "$cmd" "$dir")
  record github "$repo${ref:+@$ref}:$dir"
}

# Provider B: Downloads architecture-matched release binaries & safely unpacks them
release_install() {
  local repo="$1" version="$2" pattern="$3" json selection name url resolved_tag tmp arch arch_re choice
  repo_check "$repo"

  if [[ -z "$version" ]]; then
    json=$(gh_json "$repo" releases/latest)
  else
    version="${version#v}"
    json=$(gh_json "$repo" "releases/tags/v$version" 2>/dev/null) || json=$(gh_json "$repo" "releases/tags/$version")
  fi

  arch=$(uname -m)
  case "${arch,,}" in
    x86_64|amd64)  arch_re='(x86_64|amd64|x64|universal|all\.|noarch)' ;;
    aarch64|arm64) arch_re='(aarch64|arm64|universal|all\.|noarch)' ;;
    *)             arch_re="(${arch,,}|universal|all\.|noarch)" ;;
  esac

  if (( HAS_JQ )); then
    selection=$(printf '%s' "$json" | jq -r \
      --arg arch_re "$arch_re" \
      --arg pat "$pattern" '
      .tag_name as $tag |
      .assets[]? |
      select(.name | test("\\.(deb|tar\\.gz|tgz|zip)$"; "i")) |
      select(.name | test($arch_re; "i")) |
      select($pat == "" or (.name | test($pat; "i"))) |
      [.name, .browser_download_url, $tag] | @tsv
    ')
  else
    selection=$(printf '%s' "$json" | awk -v arch_re="$arch_re" -v pat="$pattern" '
      BEGIN { RS=","; tag="" }
      /"tag_name"/ && tag == "" {
        match($0, /"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"/)
        if (RSTART) { s = substr($0, RSTART, RLENGTH); sub(/.*:[[:space:]]*"/, "", s); sub(/"$/, "", s); tag = s }
      }
      /"name"[[:space:]]*:/ {
        match($0, /"name"[[:space:]]*:[[:space:]]*"[^"]+"/)
        if (RSTART) { s = substr($0, RSTART, RLENGTH); sub(/.*:[[:space:]]*"/, "", s); sub(/"$/, "", s); name = s }
      }
      /"browser_download_url"[[:space:]]*:/ {
        match($0, /"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"/)
        if (RSTART) {
          s = substr($0, RSTART, RLENGTH); sub(/.*:[[:space:]]*"/, "", s); sub(/"$/, "", s); url = s
          low = tolower(name)
          if (low ~ /\.(deb|tar\.gz|tgz|zip)$/ && low ~ arch_re && (pat == "" || low ~ tolower(pat))) {
            print name "\t" url "\t" tag
          }
          name = ""; url = ""
        }
      }
    ')
  fi

  [[ -n "$selection" ]] || fail 'No compatible release asset. Try --asset REGEX'

  if [[ "$selection" == *$'\n'* ]]; then
    if (( HAS_GUM && IS_TTY_IN )); then
      choice=$(printf '%s\n' "$selection" | cut -f1 | gum choose --header 'Select release asset')
    elif (( IS_TTY_IN )); then
      select choice in $(printf '%s\n' "$selection" | cut -f1); do [[ -n "$choice" ]] && break; done
    else
      fail 'Multiple assets match. Use --asset REGEX to select one'
    fi
    selection=$(printf '%s\n' "$selection" | awk -F '\t' -v n="$choice" '$1==n {print; exit}')
  fi

  IFS=$'\t' read -r name url resolved_tag <<< "$selection"
  [[ -z "$version" ]] && version="$resolved_tag"

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN

  say "Selected: $repo | $name"
  confirm 'Download this release asset?' || return 1
  fetch -o "$tmp/$name" "$url"

  case "$name" in
    *.deb)
      need dpkg
      confirm "Install Debian package $name with sudo?" || return 1
      sudo dpkg -i "$tmp/$name"
      ;;
    *.tar.gz|*.tgz)
      need tar
      # Audit archive entries: block symlinks (^l) and path traversal (.. or leading /)
      if tar -tvzf "$tmp/$name" | awk '$1 ~ /^l/ || $NF ~ /(^\/|\.\.)/ { exit 1 }'; then
        mkdir -p "$XI_HOME/downloads/$repo"
        tar --no-same-owner -xzf "$tmp/$name" -C "$XI_HOME/downloads/$repo"
        say "Archive extracted to $XI_HOME/downloads/$repo"
      else
        fail 'Unsafe archive blocked (symlinks or path traversal detected)'
      fi
      ;;
    *.zip)
      need unzip
      # Audit zip entries against path traversal and Windows backslashes
      if unzip -Z1 "$tmp/$name" | awk '/(^\/|\.\.|\\)/ { exit 1 }'; then
        mkdir -p "$XI_HOME/downloads/$repo"
        unzip -q -o "$tmp/$name" -d "$XI_HOME/downloads/$repo"
        say "Archive extracted to $XI_HOME/downloads/$repo"
      else
        fail 'Unsafe zip archive blocked (path traversal detected)'
      fi
      ;;
  esac
  record release "$repo@$version:$name"
}

# Provider C: Persists Zinit plugins & signals ZLE widget for instant parent-shell reload
xi_zinit() {
  local plugin="${1:?Missing OWNER/PLUGIN}" file="$XI_HOME/zinit-plugins.zsh"
  repo_check "$plugin"
  need zsh
  [[ "$(config_get XI_ZSH_PKG)" == zinit ]] || fail 'Set xi config --zsh-pkg zinit'

  confirm "Persist Zinit plugin $plugin?" || return 1
  append_unique_line "$file" "zinit light '$plugin'"
  append_unique_line "$HOME/.zshrc" "[[ -f $file ]] && source $file"
  touch "$ZINIT_RELOAD_FLAG"
  record zinit "$plugin"
  say "Plugin configured. Reload with: exec zsh (or Alt+X ZLE hot-reload)"
}

# Provider D: Safe curated Git operational shortcuts
git_snippets() {
  local entries selected
  entries=$'status — git status -sb\nlog — git log --oneline -10\nbranches — git branch -vv\nfetch — git fetch --prune\ndiff — git diff --stat\nremotes — git remote -v'
  if [[ "${1:-}" == run ]]; then
    (( IS_TTY_IN )) || fail 'Interactive terminal required'
    if (( HAS_GUM )); then
      selected=$(printf '%s\n' "$entries" | gum choose --header 'Git snippets')
    else
      printf '%s\n' "$entries"
      read -r -p 'Enter snippet name: ' selected
    fi
    case "${selected%% *}" in
      status)   git status -sb ;;
      log)      git log --oneline -10 ;;
      branches) git branch -vv ;;
      fetch)    confirm 'Fetch remote refs?' && git fetch --prune ;;
      diff)     git diff --stat ;;
      remotes)  git remote -v ;;
      *)        fail 'Unknown snippet' ;;
    esac
  else
    printf '%s\n' "$entries"
  fi
}

# ==============================================================================
# 7. Zsh Line Editor (ZLE) Widget Generator
#    Outputs Zsh code to bind Alt+X in the user's active Zsh session.
# ==============================================================================
xi_zle_init() {
  cat <<'ZSH'
# xi ZLE integration — add `eval "$(xi zle-init)"` to ~/.zshrc
_xi_zle_widget() {
  local saved_buffer="$BUFFER"
  local saved_cursor="$CURSOR"
  BUFFER=""
  zle redisplay

  # If prompt is empty, open TUI menu; otherwise pass current line directly to xi
  if [[ -z "$saved_buffer" ]]; then
    xi menu </dev/tty
  else
    xi ${=saved_buffer} </dev/tty
  fi

  # Check if xi persisted a new Zinit plugin and hot-reload it in the parent shell
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/xi"
  local cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/xi"
  if [[ -f "$state_dir/.reload_zinit" ]]; then
    rm -f "$state_dir/.reload_zinit"
    [[ -f "$cfg_dir/zinit-plugins.zsh" ]] && source "$cfg_dir/zinit-plugins.zsh"
    zle -M "xi: Zinit plugins hot-reloaded in active shell"
  fi

  BUFFER="$saved_buffer"
  CURSOR="$saved_cursor"
  zle reset-prompt
}
zle -N _xi_zle_widget
bindkey '^[x' _xi_zle_widget
ZSH
}

# ==============================================================================
# 8. Diagnostics, Inventory & Atomic Self-Update
# ==============================================================================
xi_path_doctor() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  case ":$PATH:" in
    *":$XI_BIN:"*) ;;
    *) export PATH="$XI_BIN:$PATH" ;;
  esac
  append_unique_line "$HOME/.zshrc" "$line"
}

inventory_view() {
  [[ -s "$INVENTORY" ]] || { say 'No managed installations'; return 0; }
  if command -v column >/dev/null 2>&1; then
    { printf 'PROVIDER\tITEM\tINSTALLED_AT\n'; sort -u "$INVENTORY"; } | column -ts $'\t'
  else
    cat "$INVENTORY"
  fi
}

xi_updates() {
  say "Tracked installations (updates require explicit confirmation):"
  inventory_view
  [[ "$(config_get XI_AUTOUPDATE)" == true ]] && say 'Auto-update enabled for future verified providers; no blind execution.'
}

self_update() {
  local url="https://raw.githubusercontent.com/rodkisten/codespaces/main/scripts/xi.sh" tmp
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' RETURN
  fetch -o "$tmp" "$url"
  bash -n "$tmp" || fail 'Downloaded script failed syntax validation'
  confirm 'Replace local xi with verified Bash script?' && install -m 755 "$tmp" "$XI_BIN/xi"
}

# ==============================================================================
# 9. GitHub Actions Control Plane
# ==============================================================================
xi_gh_repo() {
  local repo="${1:-}"
  if [[ -z "$repo" ]]; then
    repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || fail "Provide OWNER/REPO outside a Git checkout"
  fi
  repo_check "$repo"
  printf "%s\n" "$repo"
}

xi_gh_checks() {
  need gh
  local repo sha
  repo=$(xi_gh_repo "${1:-}")
  sha="${2:-}"
  if [[ -z "$sha" ]]; then
    sha=$(gh api "repos/$repo/commits/HEAD" --jq .sha) || return 1
  fi
  say "Commit $sha"
  gh api "repos/$repo/commits/$sha/check-runs" --jq '.check_runs[] | [.name,.status,.conclusion,.html_url] | @tsv' || return 1
  say "Recent workflow runs:"
  gh run list -R "$repo" --limit 10
}

xi_gh_runs() {
  need gh
  local repo
  repo=$(xi_gh_repo "${1:-}")
  gh run list -R "$repo" --limit 20
}

xi_gh_watch() {
  need gh
  local repo runid
  repo=$(xi_gh_repo "${1:-}")
  runid="${2:-}"
  if [[ -z "$runid" ]]; then
    runid=$(gh run list -R "$repo" --limit 10 --json databaseId,displayTitle,status --jq '.[] | [.databaseId,.status,.displayTitle] | @tsv' | {
      xi_select_stream "Select run"
    }) || return 1
    runid="${runid%%$'\t'*}"
  fi
  [[ "$runid" =~ ^[0-9]+$ ]] || fail "Invalid run ID"
  gh run watch "$runid" -R "$repo" --exit-status
}

xi_gh_logs() {
  need gh
  local repo runid
  repo=$(xi_gh_repo "${1:-}")
  runid="${2:-}"
  if [[ -z "$runid" ]]; then
    runid=$(gh run list -R "$repo" --limit 20 --json databaseId,status,conclusion,displayTitle --jq '.[] | [.databaseId,.status,.conclusion,.displayTitle] | @tsv' | {
      xi_select_stream "Choose run for logs"
    }) || return 1
    runid="${runid%%$'\t'*}"
  fi
  [[ "$runid" =~ ^[0-9]+$ ]] || fail "Invalid run ID"
  gh run view "$runid" -R "$repo" --log-failed
}

xi_gh_pick_ref() {
  local repo="$1" ref
  if (( HAS_GUM && IS_TTY_IN )); then
    ref=$(gh api "repos/$repo/branches?per_page=100" --jq '.[].name' | xi_select_stream "Branch or ref") || return 1
  else
    read -r -p "Branch or ref [main]: " ref
  fi
  printf "%s\n" "${ref:-main}"
}

xi_gh_dispatch() {
  need gh
  local repo workflow ref input workflow_row
  repo=$(xi_gh_repo "${1:-}")
  workflow="${2:-}"; ref="${3:-}"
  if [[ -z "$workflow" ]]; then
    workflow_row=$(gh workflow list -R "$repo" --json name,path --jq '.[] | [.name,.path] | @tsv' | {
      xi_select_stream "Select workflow"
    }) || return 1
    [[ "$workflow_row" == *$'\t'* ]] || { say "No workflow selected"; return 1; }
    workflow="${workflow_row#*$'\t'}"
  fi
  [[ -n "$workflow" ]] || fail "Missing workflow"
  if [[ -z "$ref" ]]; then ref=$(xi_gh_pick_ref "$repo") || return 1; fi
  local -a args=()
  if (( IS_TTY_IN )); then
    say "Workflow inputs: enter key=value, one per line. Leave blank to continue."
    while true; do
      if (( HAS_GUM && IS_TTY_OUT )); then input=$(gum input --placeholder "input=value (Enter when done)") || return 1
      else read -r -p "Input key=value (blank to finish): " input || return 1; fi
      [[ -n "$input" ]] || break
      [[ "$input" == *=* && "${input%%=*}" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || { say "Invalid input name; expected key=value"; continue; }
      args+=(-f "$input")
    done
  fi
  say "Repository: $repo"
  say "Workflow: $workflow"
  say "Ref: $ref"
  say "Inputs: ${#args[@]} CLI arguments"
  confirm "Dispatch this workflow?" || return 1
  gh workflow run "$workflow" -R "$repo" --ref "$ref" "${args[@]}" || return 1
  say "Workflow dispatch accepted. GitHub may take a moment to create its run."
  if (( IS_TTY_IN )); then
    if confirm "Open recent runs now?"; then xi_gh_runs "$repo"; fi
  fi
}
xi_gh_menu() {
  need gh
  local choice repo
  repo=$(xi_gh_repo "${1:-}")
  while true; do
    choice=$(xi_choice "Commit checks" "Workflow runs" "Watch a run" "Failed logs" "Trigger workflow" "Back") || return 0
    case "$choice" in
      "Commit checks")    xi_gh_checks "$repo" ;;
      "Workflow runs")    xi_gh_runs "$repo" ;;
      "Watch a run")      xi_gh_watch "$repo" ;;
      "Failed logs")      xi_gh_logs "$repo" ;;
      "Trigger workflow") xi_gh_dispatch "$repo" ;;
      Back)               return 0 ;;
    esac
  done
}

xi_gh() {
  local action="${1:-menu}"
  [[ $# -eq 0 ]] || shift
  case "$action" in
    menu)     xi_gh_menu "${1:-}" ;;
    checks)   xi_gh_checks "${1:-}" "${2:-}" ;;
    runs)     xi_gh_runs "${1:-}" ;;
    watch)    xi_gh_watch "${1:-}" "${2:-}" ;;
    logs)     xi_gh_logs "${1:-}" "${2:-}" ;;
    dispatch) xi_gh_dispatch "${1:-}" "${2:-}" "${3:-}" ;;
    *)        fail "Usage: xi gh [menu|checks|runs|watch|logs|dispatch] [OWNER/REPO] [ARG]" ;;
  esac
}

# ==============================================================================
# 10. Interactive TUI Menu Engine
# ==============================================================================
xi_gum_supports() {
  (( HAS_GUM )) || return 1
  gum --help 2>/dev/null | grep -Eq "(^|[[:space:]])$1([[:space:]]|$)"
}
xi_select_stream() {
  local prompt="$1" selected line index=1
  local -a options=()
  while IFS= read -r line; do options+=("$line"); done
  ((${#options[@]})) || return 1
  if (( IS_TTY_IN && IS_TTY_OUT )) && xi_gum_supports filter; then
    printf "%s\n" "${options[@]}" | gum filter --placeholder "$prompt"
  elif (( IS_TTY_IN && IS_TTY_OUT )) && xi_gum_supports choose; then
    printf "%s\n" "${options[@]}" | gum choose --header "$prompt"
  elif (( IS_TTY_IN )); then
    printf "%s\n" "$prompt" >&2
    for line in "${options[@]}"; do printf "%d) %s\n" "$index" "$line" >&2; index=$((index+1)); done
    read -r -p "Choose number: " selected </dev/tty
    [[ "$selected" =~ ^[0-9]+$ ]] && (( selected>=1 && selected<=${#options[@]} )) || return 1
    printf "%s\n" "${options[selected-1]}"
  else printf "%s\n" "${options[0]}"; fi
}
xi_choice() {
  printf "%s\n" "$@" | xi_select_stream "Search xi actions"
}
xi_settings() {
  local choice
  choice=$(xi_choice "Enable update checks" "Disable update checks" "Show config" "Show debug log path" "Back") || return 0
  case "$choice" in
    "Enable update checks")  config_set XI_AUTOUPDATE true ;;
    "Disable update checks") config_set XI_AUTOUPDATE false ;;
    "Show config")           cat "$CONFIG" ;;
    "Show debug log path")   say "Debug log: $DEBUG_LOG" ;;
  esac
}

xi_menu() {
  (( IS_TTY_IN )) || { usage; return 0; }
  local choice repo version
  while true; do
    if (( HAS_GUM && IS_TTY_OUT )); then
      gum style --border rounded --padding "1 3" "⚡ xi · Universal Installer" "GitHub · Releases · Zinit · Updates"
    else
      printf "\n╭── xi · Universal Installer ──╮\n╰──────────────────────────────╯\n"
    fi
    choice=$(xi_choice "GitHub Actions" "GitHub installer" "GitHub releases" "Zinit plugin" "Inventory" "Check updates" "Git snippets" "Settings" "PATH doctor" "Exit") || return 0
    case "$choice" in
      "GitHub Actions")   xi_gh_menu ;;
      "GitHub installer") read -r -p "OWNER/REPO: " repo; [[ -n "$repo" ]] && install_repo "$repo" "" bash "" ;;
      "GitHub releases")  read -r -p "OWNER/REPO: " repo; [[ -z "$repo" ]] && continue; read -r -p "Version (blank for latest): " version; release_install "$repo" "$version" "" ;;
      "Zinit plugin")     read -r -p "OWNER/PLUGIN: " repo; [[ -n "$repo" ]] && xi_zinit "$repo" ;;
      Inventory)          inventory_view ;;
      "Check updates")    xi_updates ;;
      "Git snippets")     git_snippets run ;;
      Settings)           xi_settings ;;
      "PATH doctor")      xi_path_doctor; say "PATH OK: $XI_BIN" ;;
      Exit)               return 0 ;;
    esac
  done
}

# ==============================================================================
# 11. CLI Router & Entrypoint
# ==============================================================================
usage() {
  cat <<'HELP'
xi [--yes] [--debug] <command>
  xi OWNER/REPO                      Discover an installer from GitHub
  xi github [--releases] OWNER/REPO [--dir PATH] [--cmd bash]
  xi releases OWNER/REPO [-v VERSION] [--asset REGEX]
  xi zinit OWNER/PLUGIN
  xi zshrc add "line"
  xi zle-init                        Print Zsh ZLE widget integration (Alt+X)
  xi config [--autoupdate true|false] [--zsh-pkg zinit] [zinit]
  xi inventory
  xi update [--all]
  xi git [run]                      Browse or execute safe Git snippets
  xi gh [menu|checks|runs|watch|logs|dispatch] [OWNER/REPO] [ARG]
  xi menu
  xi doctor
  xi self-update
HELP
}

main() {
  # Strip global flags (--yes, --debug) regardless of position
  local -a args=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      --yes)   XI_YES=1 ;;
      --debug) ;; # Already activated in bootstrap phase
      *)       args+=("$arg") ;;
    esac
  done
  set -- "${args[@]}"

  local action="${1:-menu}" repo="" dir="" cmd="bash" releases=0 version="" asset=""
  [[ $# -eq 0 ]] || shift

  case "$action" in
    help|-h|--help) usage ;;
    menu)           xi_menu ;;
    doctor)         xi_path_doctor; say "PATH checked: $XI_BIN" ;;
    zle-init)       xi_zle_init ;;
    gh)             xi_gh "$@" ;;
    github)
      while (($#)); do
        case "$1" in
          --releases) releases=1 ;;
          --dir)      dir="${2:?Missing --dir path}"; shift ;;
          --cmd)      cmd="${2:?Missing --cmd runner}"; shift ;;
          *)          repo="$1" ;;
        esac
        shift
      done
      [[ -n "$repo" ]] || fail 'Missing repository'
      if (( releases )); then
        local tag
        tag=$(gh_json "$repo" releases/latest | json_extract_tag)
        [[ -n "$tag" ]] || fail 'Could not resolve latest release tag'
        install_repo "$repo" "$dir" "$cmd" "$tag"
      else
        install_repo "$repo" "$dir" "$cmd" ""
      fi
      ;;
    releases)
      repo="${1:?Missing repository}"; shift
      while (($#)); do
        case "$1" in
          -v|--version) version="${2:?Missing version}"; shift ;;
          --asset)      asset="${2:?Missing asset regex}"; shift ;;
          *)            fail "Unknown option: $1" ;;
        esac
        shift
      done
      release_install "$repo" "$version" "$asset"
      ;;
    zinit)
      xi_zinit "${1:?Missing OWNER/PLUGIN}"
      ;;
    zshrc)
      [[ "${1:-}" == add && $# -eq 2 ]] || fail 'Usage: xi zshrc add "line"'
      append_unique_line "$HOME/.zshrc" "$2"
      say 'zshrc updated (idempotent)'
      ;;
    config)
      case "${1:-}" in
        --autoupdate) [[ "${2:-}" == true || "${2:-}" == false ]] || fail 'Use true or false'; config_set XI_AUTOUPDATE "$2" ;;
        --zsh-pkg)    [[ "${2:-}" == zinit ]] || fail 'Only zinit supported'; config_set XI_ZSH_PKG "$2" ;;
        zinit)        say 'Zinit settings: ~/.config/zsh and ~/.zshrc' ;;
        '')           cat "$CONFIG" ;;
        *)            fail 'Unknown config option' ;;
      esac
      ;;
    inventory)   inventory_view ;;
    update)      [[ "${1:-}" == --all ]] || fail 'Use xi update --all'; xi_updates ;;
    self-update) self_update ;;
    git)         git_snippets "${1:-}" ;;
    */*)         install_repo "$action" "" bash "" ;;
    *)           fail "Unknown command: $action" ;;
  esac
}

# Bootstrap PATH and dispatch
xi_path_doctor
main "$@"
