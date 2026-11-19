# @bin
#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'HELP'
Usage: gh-env-sync --file .env [--type secret|variable] [--scope repo|env] [--environment production] [--limit N] [--refresh-cache] [--cache-ttl SECONDS] [--owner USER] [--repo OWNER/NAME ...] [--dry-run] [--yes]
Defaults: secret, repo, all non-archived repositories sorted by most recent push. Cache TTL: 24 hours.
HELP
}

file=''; type=''; scope=''; environment=''; limit=0; owner=''
dry_run=false; yes=false; refresh_cache=false; cache_ttl=86400
repos=(); tmux_inner=false; no_tmux=false

while (($#)); do
  case "$1" in
    --file) file=${2:?}; shift 2;;
    --type) type=${2:?}; shift 2;;
    --scope) scope=${2:?}; shift 2;;
    --environment|--env) environment=${2:?}; shift 2;;
    --limit) limit=${2:?}; shift 2;;
    --refresh-cache) refresh_cache=true; shift;;
    --tmux-inner) tmux_inner=true; shift;;
    --no-tmux) no_tmux=true; shift;;
    --cache-ttl) cache_ttl=${2:?}; shift 2;;
    --owner) owner=${2:?}; shift 2;;
    --repo) repos+=("${2:?}"); shift 2;;
    --dry-run) dry_run=true; shift;;
    --yes) yes=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2;;
  esac
done

# Fail fast before opening tmux or fzf prompts
[[ -f "$file" ]] || { echo 'Missing --file or file does not exist' >&2; exit 2; }
[[ $limit =~ ^[0-9]+$ ]] || { echo 'Invalid --limit (must be a non-negative integer)' >&2; exit 2; }
[[ $cache_ttl =~ ^[0-9]+$ ]] || { echo 'Invalid --cache-ttl (must be a non-negative integer)' >&2; exit 2; }

for cmd in gh python3; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo 'Run gh auth login first' >&2; exit 1; }

# Launch split-pane tmux studio if running interactively outside tmux
if [[ $tmux_inner == false && $no_tmux == false && -t 0 && -z ${TMUX:-} ]] && command -v tmux >/dev/null; then
  session="gh-env-$(date +%s)-$$"
  log_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gh-env-sync/sessions"
  mkdir -p "$log_dir" && chmod 700 "$log_dir"
  log_file="$log_dir/$session.log"; : > "$log_file"; chmod 600 "$log_file"
  printf -v quoted "%q " "$0" "$@" --tmux-inner
  tmux new-session -d -s "$session" -c "$PWD" -e "GH_ENV_STUDIO_LOG=$log_file" "bash -lc $(printf %q "$quoted")"
  tmux split-window -t "$session":0 -v -l 35% -c "$PWD" "tail -n +1 -f $(printf %q "$log_file")"
  tmux select-pane -t "$session":0.0
  exec tmux attach-session -t "$session"
fi

studio_log() {
  [[ -n ${GH_ENV_STUDIO_LOG:-} ]] || return 0
  printf "%s\n" "$*" >> "$GH_ENV_STUDIO_LOG"
}

studio_event() {
  local color=$1 label=$2 message=$3
  printf "\033[48;5;%sm\033[38;5;16m %-8s \033[0m %s\n" "$color" "$label" "$message"
  studio_log "[$label] $message"
}

# Interactive prompts via fzf if available
if [[ -t 0 ]] && command -v fzf >/dev/null; then
  pick_one() { printf '%s\n' "$@" | fzf --reverse --height=~10 --border=rounded --color='border:magenta,prompt:cyan'; }
  pick_many() { printf '%s\n' "$@" | fzf --multi --reverse --height=~70% --border=rounded --bind='ctrl-a:select-all' --header='TAB toggle · Ctrl-A select all · Enter confirm' --color='border:magenta,prompt:cyan,pointer:magenta,header:yellow'; }
  [[ -n $type ]] || type=$(pick_one secret variable) || exit 0
  studio_event 99 TYPE "$type"
  [[ -n $scope ]] || scope=$(pick_one repo env) || exit 0
  studio_event 99 SCOPE "$scope"
  if [[ $scope == env && -z $environment ]]; then
    read -r -p '🌐 Environment: ' environment
  fi
  [[ $scope != env ]] || studio_event 99 ENV "$environment"
else
  type=${type:-secret}
  scope=${scope:-repo}
fi

[[ $type == secret || $type == variable ]] || { echo 'Invalid --type (expected secret or variable)' >&2; exit 2; }
[[ $scope == repo || $scope == env ]] || { echo 'Invalid --scope (expected repo or env)' >&2; exit 2; }
[[ $scope != env || -n $environment ]] || { echo 'Environment name required for --scope env' >&2; exit 2; }

tmp=$(mktemp)
chmod 600 "$tmp"
trap 'rm -f "$tmp" "$tmp.current" "$tmp.output" "$tmp.error"' EXIT

# Parse .env file into NUL-delimited key/value pairs
python3 - "$file" "$tmp" <<'PY'
import pathlib, re, sys

source = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8-sig')
lines = source.splitlines(keepends=True)
entries = []
i = 0

while i < len(lines):
    line = lines[i].strip()
    i += 1
    if not line or line.startswith('#'):
        continue
    m = re.match(r'(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)', line, re.S)
    if not m:
        raise SystemExit(f'Invalid dotenv assignment at line {i}')
    key, raw = m.groups()
    if raw.startswith(('"', "'")):
        quote = raw[0]
        while not re.search(r'(?<!\\)' + re.escape(quote) + r'\s*(?:#.*)?$', raw):
            if i >= len(lines):
                raise SystemExit(f'Unterminated quoted value: {key}')
            raw += '\n' + lines[i].rstrip('\r\n')
            i += 1
        if quote == '"':
            raw = re.sub(
                r'\\([nrt\\"])',
                lambda m: {'n': '\n', 'r': '\r', 't': '\t', '\\': '\\', '"': '"'}[m[1]],
                raw[1:raw.rfind('"')],
            )
        else:
            raw = raw[1:raw.rfind("'")]
    else:
        raw = re.split(r'\s+#', raw, maxsplit=1)[0].rstrip()
    if '\x00' in raw:
        raise SystemExit(f'NUL byte not supported: {key}')
    entries.append((key, raw))

if not entries:
    raise SystemExit('No variables found')

with open(sys.argv[2], 'wb') as out:
    for key, value in entries:
        out.write(key.encode() + b'\0' + value.encode() + b'\0')

print(f'Parsed {len(entries)} assignments', file=sys.stderr)
PY

# Fetch or load cached repositories if --repo was not explicitly provided
if (("${#repos[@]}" == 0)); then
  owner=${owner:-$(gh api user --jq .login)}
  cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gh-env-sync"
  mkdir -p "$cache_dir" && chmod 700 "$cache_dir"
  cache_file="$cache_dir/repos-$owner.tsv"
  cache_fresh=false

  if [[ -s $cache_file && $refresh_cache == false ]]; then
    if python3 - "$cache_file" "$cache_ttl" <<'PY'
import os, sys, time
sys.exit(0 if time.time() - os.path.getmtime(sys.argv[1]) < int(sys.argv[2]) else 1)
PY
    then
      cache_fresh=true
    fi
  fi

  if [[ $cache_fresh == false ]]; then
    printf '\033[38;5;51m◐ Loading repositories from GitHub...\033[0m\n' >&2
    cache_tmp=$(mktemp "$cache_dir/.repos.XXXXXX")
    gh repo list "$owner" --limit 10000 --json nameWithOwner,pushedAt,isArchived,isFork > "$cache_tmp.json" 2>"$cache_tmp.error" &
    fetch_pid=$!; frame=0; frames=('◐' '◓' '◑' '◒')
    if [[ -t 2 ]]; then
      while kill -0 "$fetch_pid" 2>/dev/null; do
        printf '\r\033[K\033[48;5;57m\033[38;5;231m %s FETCH \033[0m %s · repositories' "${frames[frame%4]}" "$owner" >&2
        frame=$((frame + 1)); sleep .12
      done
      printf '\r\033[K' >&2
    fi
    if wait "$fetch_pid"; then
      python3 - "$cache_tmp.json" "$cache_tmp" <<'PY'
import json, pathlib, sys
items = json.load(open(sys.argv[1]))
items = sorted((r for r in items if not r['isArchived']), key=lambda r: r.get('pushedAt') or '', reverse=True)
pathlib.Path(sys.argv[2]).write_text(''.join(f"{r['nameWithOwner']}\n" for r in items))
PY
      mv -f "$cache_tmp" "$cache_file"
      chmod 600 "$cache_file"
      rm -f "$cache_tmp.json" "$cache_tmp.error"
      studio_event 34 CACHE "Refreshed repositories for $owner"
    else
      head -n 3 "$cache_tmp.error" >&2
      rm -f "$cache_tmp" "$cache_tmp.json" "$cache_tmp.error"
      if [[ ! -s $cache_file ]]; then
        echo 'Cannot load repositories and no cache exists' >&2
        exit 1
      fi
      echo '⚠ GitHub unavailable; using stale repository cache' >&2
    fi
  else
    studio_event 34 CACHE "Using cached repository list"
  fi

  mapfile -t repos < "$cache_file"
  studio_event 45 FOUND "${#repos[@]} repositories available"
  if ((limit > 0)); then
    repos=("${repos[@]:0:limit}")
  fi
fi

(("${#repos[@]}")) || { echo 'No repositories found' >&2; exit 1; }

if declare -F pick_many >/dev/null; then
  selected=$(pick_many "${repos[@]}") || exit 0
  [[ -n $selected ]] || exit 0
  mapfile -t repos <<< "$selected"
  studio_event 45 REPOS "${#repos[@]} selected"
  for chosen_repo in "${repos[@]}"; do studio_event 45 SELECT "$chosen_repo"; done
fi

mapfile -d '' -t entries < "$tmp"
keys=()
for ((i = 0; i < ${#entries[@]}; i += 2)); do
  keys+=("${entries[i]}")
done

if declare -F pick_many >/dev/null; then
  selected=$(pick_many "${keys[@]}") || exit 0
  [[ -n $selected ]] || exit 0
  mapfile -t keys <<< "$selected"
  studio_event 141 KEYS "${#keys[@]} selected"
  for chosen_key in "${keys[@]}"; do studio_event 141 SELECT "$chosen_key"; done
fi

printf '\033[38;5;213m✦ GH ENV STUDIO ✦\033[0m\n'
studio_event 99 TARGET "$type / $scope ${environment:-}"
printf 'Scope: %s %s | Type: %s | Repositories: %s | Keys: %s\n' "$scope" "$environment" "$type" "${#repos[@]}" "${#keys[@]}"
printf 'Keys: %s\n' "${keys[*]}"
printf 'Repositories:\n'
printf '  %s\n' "${repos[@]}"

if [[ $dry_run == true ]]; then
  echo 'DRY RUN: preview only'
fi

if [[ $yes != true && $dry_run != true ]]; then
  read -r -p 'Apply all changes? Type YES: ' confirmation
  [[ $confirmation == YES ]] || { echo 'Cancelled'; exit 1; }
fi

success=0; failure=0; skipped=0

for repo in "${repos[@]}"; do
  studio_event 27 REPO "$repo"

  if [[ $scope == env && $dry_run != true ]]; then
    if ! gh api -X PUT "repos/$repo/environments/$environment" >/dev/null; then
      echo "  ERROR creating environment" >&2
      failure=$((failure + ${#keys[@]}))
      continue
    fi
  fi

  if [[ $type == variable ]]; then
    args=(variable list --repo "$repo" --json name,value)
    [[ $scope == env ]] && args+=(--env "$environment")
    if ! gh "${args[@]}" > "$tmp.current"; then
      echo "Cannot inspect variables in $repo; skipping" >&2
      skipped=$((skipped + ${#keys[@]}))
      continue
    fi
  fi

  for ((i = 0; i < ${#entries[@]}; i += 2)); do
    key=${entries[i]}
    value=${entries[i+1]}

    selected=false
    for chosen in "${keys[@]}"; do
      [[ $chosen == "$key" ]] && selected=true
    done
    [[ $selected == true ]] || continue

    if [[ $type == variable ]]; then
      result=$(python3 - "$tmp.current" "$key" "$value" <<'PY'
import json, sys
items = json.load(open(sys.argv[1]))
old = next((x.get('value', '') for x in items if x['name'] == sys.argv[2]), None)
new = sys.argv[3]
if old is None:
    print('NEW')
elif old == new:
    print('SAME')
else:
    print('CHANGE')
    print('  current: ' + repr(old))
    print('  next:    ' + repr(new))
PY
)
      state=$(printf '%s\n' "$result" | head -n 1)
      if [[ $state == SAME ]]; then
        printf '  ⊘ %s: SAME (skipped)\n' "$key"
        skipped=$((skipped + 1))
        continue
      elif [[ $state == NEW ]]; then
        printf '\033[38;5;46m+ %s\033[0m (new variable)\n' "$key"
      else
        printf '\033[38;5;51m↻ %s\033[0m\n%s\n' "$key" "$result"
      fi
    fi

    args=("$type" set "$key" --repo "$repo")
    [[ $scope == env ]] && args+=(--env "$environment")

    if [[ $dry_run == true ]]; then
      studio_event 33 PREVIEW "$repo · $key"
      continue
    fi

    # Pass value via stdin instead of --body to avoid leaking secrets in `ps`
    printf '%s' "$value" | gh "${args[@]}" > "$tmp.output" 2>"$tmp.error" &
    pid=$!; frame=0; frames=('◐' '◓' '◑' '◒')
    if [[ -t 2 ]]; then
      while kill -0 "$pid" 2>/dev/null; do
        printf '\r\033[K\033[38;5;213m%s\033[0m %s · %s' "${frames[frame%4]}" "$repo" "$key" >&2
        frame=$((frame + 1)); sleep .12
      done
      printf '\r\033[K' >&2
    fi

    if wait "$pid"; then
      studio_event 34 PASS "$repo · $key"
      success=$((success + 1))
    else
      studio_event 196 FAIL "$repo · $key"
      head -n 3 "$tmp.error" >&2
      failure=$((failure + 1))
    fi
  done
done

studio_log "[DONE] successful=$success failed=$failure skipped=$skipped"
printf '\033[38;5;213m✦ Finished:\033[0m %d successful, %d failed, %d skipped\n' "$success" "$failure" "$skipped"
((failure == 0))
