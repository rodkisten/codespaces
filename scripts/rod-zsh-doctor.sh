#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
RC="$HOME/.zshrc"
DIR="$HOME/.config/zsh"
MODE="${1:---repair}"
[[ "$MODE" == --repair || "$MODE" == --check ]] || { echo 'Usage: rod-zsh-doctor.sh [--check|--repair]'; exit 2; }
command -v zsh >/dev/null || { echo 'zsh missing' >&2; exit 1; }
[[ -f "$RC" ]] || { echo '~/.zshrc missing' >&2; exit 1; }
zsh -n "$RC"
echo '💜 Rod Zsh Doctor'
if [[ "$MODE" == --check ]]; then
  grep -nE 'rod-prompt|rod-notify|exec 2>|XTRACE' "$RC" || true
  echo 'Read-only check complete'
  exit 0
fi
mkdir -p "$DIR"
BACKUP="$RC.backup-$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$RC" "$BACKUP"
echo "📦 Backup: $BACKUP"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
# Remove only obsolete emergency prompt block and duplicated Rod source directives.
python3 - "$RC" "$TMP" <<'PY'
import pathlib, re, sys
data=pathlib.Path(sys.argv[1]).read_bytes()
lines=data.decode('utf-8','surrogateescape').splitlines(keepends=True)
out=[]
skip=False
for line in lines:
    if not skip and re.match(r'^\s*_rod_prompt\(\)\s*\{\s*$',line):
        skip=True
        continue
    if skip:
        if line.strip()=='}': skip=False
        continue
    if re.match(r'^\s*add-zsh-hook\s+(?:-d\s+)?precmd\s+_rod_prompt\s*$',line): continue
    if re.match(r'^\s*source\s+["\x27]?\$HOME/\.config/zsh/rod-(?:prompt|notify)\.zsh',line): continue
    out.append(line)
pathlib.Path(sys.argv[2]).write_bytes(''.join(out).encode('utf-8','surrogateescape'))
PY
cat > "$DIR/rod-prompt.zsh" <<'ZSH'
[[ -o interactive ]] || return 0
autoload -Uz add-zsh-hook
setopt PROMPT_PERCENT
_rod_prompt_safe() {
  local rc=$?
  local dir="${(%):-%~}" branch='' dots=''
  local status='%F{82}❯%f'
  (( rc != 0 )) && status="%F{203}❯ $rc%f"
  if (( $+commands[git] )); then
    branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=''
  fi
  local n=$(( ${COLUMNS:-40} - ${#dir} - ${#branch} - 8 ))
  (( n < 0 )) && n=0
  (( n > 200 )) && n=200
  local i
  for (( i=0; i<n; i++ )); do dots+='·'; done
  PROMPT="%F{177}╭─ 📁 ${dir//\%/%%}%f"
  [[ -n "$branch" ]] && PROMPT+=" %F{81}⎇ ${branch//\%/%%}%f"
  PROMPT+=$'\n'
  PROMPT+="%F{242}$dots%f"
  PROMPT+=$'\n'
  PROMPT+="%F{177}╰─%f $status "
  RPROMPT=''
  return 0
}
add-zsh-hook -d precmd _rod_prompt_safe 2>/dev/null || true
add-zsh-hook precmd _rod_prompt_safe
ZSH
cat >> "$TMP" <<'ZSH'

# Rod modules: notify first, prompt last.
[[ -r "$HOME/.config/zsh/rod-notify.zsh" ]] && source "$HOME/.config/zsh/rod-notify.zsh"
[[ -r "$HOME/.config/zsh/rod-prompt.zsh" ]] && source "$HOME/.config/zsh/rod-prompt.zsh"
ZSH
zsh -n "$TMP"
zsh -n "$DIR/rod-prompt.zsh"
chmod --reference="$RC" "$TMP"
cat "$TMP" > "$RC"
echo '✅ Repaired. Secrets and Notify sender unchanged.'
echo 'Test: zsh -ic "command rod_missing_123; print -r -- STATUS:\$?"'
echo 'Restart: exec zsh'
