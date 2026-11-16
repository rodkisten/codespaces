#!/usr/bin/env bash
# Synchronize an allowlisted personal Zsh file with private rodkisten/ssh main.
set -Eeuo pipefail
umask 077
action="${1:-status}"
remote="${ROD_SYNC_REPO:-rodkisten/ssh}"
branch=main
dir="$HOME/.local/share/rod-ssh-sync"
source_file="$HOME/.zshrc.local"
target=dotfiles/zshrc.local
log() { printf '[%s] %-5s %s\n' "$(date -u +%FT%TZ)" "$1" "$2"; }
fail() { log FAIL "$1" >&2; exit 1; }
[[ "$remote" =~ ^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$ ]] || fail "Invalid repository"
command -v git >/dev/null || fail "git not installed"
[[ -n "${SSH_SYNC_TOKEN:-}" ]] || { log SKIP "SSH_SYNC_TOKEN not configured; remote sync disabled"; exit 0; }
# Credentials only in environment, never in remote URL, command arguments or logs.
askpass="$(mktemp)"
trap 'rm -f "$askpass"' EXIT
cat > "$askpass" <<'ASKPASS'
#!/usr/bin/env bash
case "$1" in
  *Username*) printf '%s\n' x-access-token ;;
  *Password*) printf '%s\n' "$SSH_SYNC_TOKEN" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$askpass"
export GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0
url="https://github.com/$remote.git"
prepare() {
  mkdir -p "$(dirname "$dir")"
  if [[ ! -d "$dir/.git" ]]; then
    if [[ -e "$dir" ]]; then
      [[ -z "$(ls -A "$dir")" ]] || fail "Non-Git directory already exists: $dir"
      rmdir "$dir"
    fi
    log RUN "git clone $remote ($branch)"
    git clone -q --single-branch --branch "$branch" "$url" "$dir" || fail "Clone failed (check token Contents permission)"
    log OK "Repository cloned"
  fi
  git -C "$dir" config user.name "Rod SSH Sync"
  git -C "$dir" config user.email "rod-ssh-sync@users.noreply.github.com"
  git -C "$dir" remote set-url origin "$url"
}
restore() {
  prepare
  log RUN "git fetch origin $branch"
  git -C "$dir" fetch -q origin "$branch" || fail "Fetch failed"
  if [[ -f "$source_file" && -s "$source_file" ]]; then
    log SKIP "Existing local configuration preserved; use rod-sync restore to replace it manually"
    return
  fi
  git -C "$dir" reset -q --hard "origin/$branch"
  if [[ -f "$dir/$target" ]]; then
    install -m 600 "$dir/$target" "$source_file"
    log OK "Restored $source_file"
  else
    touch "$source_file"; chmod 600 "$source_file"
    log SKIP "No remote Zsh preferences yet"
  fi
}
sync_now() {
  prepare
  [[ -f "$source_file" ]] || { log SKIP "No $source_file"; return; }
  # Do not sync symlinks, large files, or obvious credentials.
  [[ ! -L "$source_file" ]] || fail "Refusing symlink"
  [[ "$(wc -c < "$source_file")" -le 65536 ]] || fail "File exceeds 64 KiB limit"
  if grep -Eiq '(-----BEGIN .*PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|(TOKEN|PASSWORD|SECRET|API_KEY)[[:space:]]*=)' "$source_file"; then
    fail "Potential credential found; not syncing"
  fi
  mkdir -p "$dir/dotfiles"
  install -m 600 "$source_file" "$dir/$target"
  git -C "$dir" add -- "$target"
  if git -C "$dir" diff --cached --quiet; then
    log SKIP "No new file changes; checking pending commits"
  else
    log RUN "git commit $target"
    git -C "$dir" commit -qm "chore(zsh): sync personal shell settings" || fail "Commit failed"
  fi
  git -C "$dir" fetch -q origin "$branch" || fail "Fetch failed"
  if [[ "$(git -C "$dir" rev-parse HEAD)" == "$(git -C "$dir" rev-parse "origin/$branch")" ]]; then
    log SKIP "Remote already up to date"
    return
  fi
  log RUN "git push origin $branch"
  if git -C "$dir" push -q origin "HEAD:$branch"; then
    log OK "Synced to $remote/$branch"
  else
    log FAIL "Push rejected; preserving local commit for manual resolution"
    return 1
  fi
}
case "$action" in
  init) restore ;;
  now) sync_now ;;
  status)
    if [[ -d "$dir/.git" ]]; then git -C "$dir" status -sb; else log SKIP "Not initialized"; fi
    ;;
  restore)
    prepare
    git -C "$dir" fetch -q origin "$branch"
    git -C "$dir" reset -q --hard "origin/$branch"
    [[ -f "$dir/$target" ]] || fail "Remote file missing"
    [[ -f "$source_file" ]] && cp -p "$source_file" "$source_file.backup.$(date -u +%Y%m%d%H%M%S)"
    install -m 600 "$dir/$target" "$source_file"
    log OK "Restored remote configuration; previous file backed up"
    ;;
  *) fail "Usage: rod-sync {init|now|status|restore}" ;;
esac
