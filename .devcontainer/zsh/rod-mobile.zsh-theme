# Rod Prompt Neon · fast native Zsh · no git status or external prompt engine.
# Source via Oh My Zsh theme loader or directly from ~/.zshrc.
autoload -Uz add-zsh-hook
setopt PROMPT_PERCENT
typeset -g ROD_PROMPT_LAST_EXIT=0
: ${ROD_PROMPT_DOTS:=1}
: ${ROD_PROMPT_SHOW_BRANCH:=1}
: ${ROD_PROMPT_SHOW_REPO:=1}

_rod_prompt_neon_precmd() {
  local rc=$? directory branch='' root='' repo='' label dots='' suffix=''
  local width=${COLUMNS:-80}
  ROD_PROMPT_LAST_EXIT=$rc

  directory="${(%):-%~}"
  if (( ROD_PROMPT_SHOW_REPO || ROD_PROMPT_SHOW_BRANCH )) && (( $+commands[git] )); then
    root=$(command git rev-parse --show-toplevel 2>/dev/null) || root=''
    if [[ -n $root ]]; then
      repo=${root:t}
      if (( ROD_PROMPT_SHOW_BRANCH )); then
        branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) ||
          branch=$(command git rev-parse --short HEAD 2>/dev/null) || branch=''
      fi
    fi
  fi

  # Avoid duplicate repo name when the directory already identifies it.
  label="$directory"
  if (( ROD_PROMPT_SHOW_REPO )) && [[ -n $repo && ${directory:t} != $repo ]]; then
    label+=" · $repo"
  fi
  [[ -n $branch ]] && label+=" · $branch"

  # Keep room for the divider on very narrow iPhone terminals.
  local available=$(( width - 4 ))
  (( available < 8 )) && available=8
  if (( ${#label} > available )); then
    label="…${label[-$(( available - 1 )),-1]}"
  fi
  local remaining=$(( width - ${#label} - 2 ))
  (( remaining < 0 )) && remaining=0
  if (( ROD_PROMPT_DOTS )); then
    dots="${(l:$remaining::·:)}"
  fi

  # Escape '%' from directory and branch names before Zsh prompt expansion.
  local safe_dir="${directory//\%/%%}" safe_repo="${repo//\%/%%}" safe_branch="${branch//\%/%%}"
  local colored="%B%F{177}$safe_dir%f%b"
  if (( ROD_PROMPT_SHOW_REPO )) && [[ -n $repo && ${directory:t} != $repo ]]; then
    colored+=" %F{240}·%f %B%F{81}$safe_repo%f%b"
  fi
  [[ -n $branch ]] && colored+=" %F{240}·%f %B%F{123}$safe_branch%f%b"
  # If long, fall back to a short, safely escaped label.
  if (( ${#label} < ${#directory} )) || (( ${#label} >= available )); then
    colored="%B%F{177}${label//\%/%%}%f%b"
  fi

  if (( rc )); then
    suffix="%B%F{203}\\$ ✕ $rc%f%b"
  else
    suffix="%B%F{84}\\$%f%b"
  fi
  PROMPT="${colored} %F{242}${dots}%f
%F{177}╰─%f ${suffix} "
  RPROMPT=''
}
add-zsh-hook precmd _rod_prompt_neon_precmd
