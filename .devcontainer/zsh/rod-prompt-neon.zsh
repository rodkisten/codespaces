# Rod Prompt Neon · native Zsh, optional syntax highlighting
[[ -o interactive ]] || return 0
autoload -Uz add-zsh-hook
setopt PROMPT_PERCENT
: ${ROD_PROMPT_DOTS:=1}
: ${ROD_PROMPT_DOT_CHAR:=·}
: ${ROD_PROMPT_DIM_COLOR:=240}
: ${ROD_PROMPT_SHOW_USER:=1}
: ${ROD_PROMPT_USER_COLOR:=225}
: ${ROD_PROMPT_USER_BG:=54}
: ${ROD_PROMPT_DIR_MODE:=smart}
: ${ROD_PROMPT_DIR_MAX:=32}
: ${ROD_PROMPT_DIR_KEEP:=2}
: ${ROD_PROMPT_DIR_COLOR:=177}
: ${ROD_PROMPT_SHOW_BRANCH:=1}
: ${ROD_PROMPT_BRANCH_MODE:=smart}
: ${ROD_PROMPT_BRANCH_MAX:=24}
: ${ROD_PROMPT_BRANCH_ICON:=}
: ${ROD_PROMPT_BRANCH_COLOR:=123}
: ${ROD_PROMPT_GIT_DIRTY:=1}
: ${ROD_PROMPT_GIT_STAGED:=1}
: ${ROD_PROMPT_GIT_UNTRACKED:=1}
: ${ROD_PROMPT_GIT_SYNC:=1}
: ${ROD_PROMPT_GIT_CACHE_TTL:=60}
: ${ROD_PROMPT_GIT_SYNC_INTERVAL:=300}
: ${ROD_PROMPT_GIT_FETCH:=0}
: ${ROD_PROMPT_GIT_TIMEOUT:=2}
: ${ROD_PROMPT_SHOW_SUCCESS:=0}
: ${ROD_PROMPT_SHOW_ERROR:=1}
: ${ROD_PROMPT_ERROR_TEXT:=1}
: ${ROD_PROMPT_ERROR_POSITION:=center}
: ${ROD_PROMPT_SHOW_SEPARATOR:=1}
: ${ROD_PROMPT_SYMBOL:='$'}
: ${ROD_PROMPT_CORNER:=╰─}
typeset -gA _ROD_NEON_CACHE _ROD_NEON_TIME _ROD_NEON_FETCH_TIME
typeset -gi _ROD_NEON_LAST_RC=0 _ROD_NEON_RAN=0
_rod_neon_safe() { REPLY=${1//\%/%%}; }
_rod_neon_short() {
  local s=$1 mode=$2 max=$3 keep=$4
  [[ $max == <-> ]] || max=24
  (( max < 4 )) && max=4
  case $mode in
    basename) s=${s:t} ;;
    short) [[ $s == */* ]] && s="…/${s:t}" ;;
    smart)
      if (( ${#s} > max )) && [[ $s == */* ]]; then
        [[ $keep == <-> ]] || keep=2
        local -a a; a=("${(@s:/:)s}")
        s="…/${(j:/:)a[-$keep,-1]}"
      fi ;;
  esac
  if (( ${#s} > max )); then
    local left=$(( (max-1)/2 ))
    s="${s[1,$left]}…${s[-$((max-left-1)),-1]}"
  fi
  REPLY=$s
}
_rod_neon_git() {
  local root=$1 branch=$2 now=$EPOCHSECONDS key="${root}:${branch}"
  [[ $now == <-> ]] || now=$(date +%s)
  local cached=${_ROD_NEON_CACHE[$key]-} age=$(( now - ${_ROD_NEON_TIME[$key]:-0} ))
  if [[ -z $cached || $age -ge ${ROD_PROMPT_GIT_CACHE_TTL:-60} ]]; then
    local porcelain='' upstream='' ahead=0 behind=0 dirty=0 staged=0 untracked=0
    porcelain=$(GIT_OPTIONAL_LOCKS=0 command git -C "$root" status --porcelain=v1 -uno 2>/dev/null) || porcelain=''
    [[ -n $porcelain ]] && dirty=1
    [[ $porcelain == *$'\n'* ]] || true
    [[ $porcelain == [AMDRC]* || $porcelain == *$'\n'[AMDRC]* ]] && staged=1
    if (( ROD_PROMPT_GIT_UNTRACKED )); then
      local unknown
      unknown=$(GIT_OPTIONAL_LOCKS=0 command git -C "$root" ls-files --others --exclude-standard 2>/dev/null | head -n 1)
      [[ -n $unknown ]] && untracked=1
    fi
    if (( ROD_PROMPT_GIT_SYNC )); then
      upstream=$(command git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || upstream=''
      if [[ -n $upstream ]]; then
        local counts
        counts=$(command git -C "$root" rev-list --left-right --count "HEAD...${upstream}" 2>/dev/null) || counts=''
        local -a nums; nums=(${=counts})
        ahead=${nums[1]:-0}; behind=${nums[2]:-0}
      fi
    fi
    cached="$dirty:$staged:$untracked:$ahead:$behind"
    _ROD_NEON_CACHE[$key]=$cached
    _ROD_NEON_TIME[$key]=$now
  fi
  REPLY=$cached
  # Network is explicitly opt-in; background fetch never blocks prompt.
  if (( ROD_PROMPT_GIT_FETCH && ROD_PROMPT_GIT_SYNC )); then
    local last=${_ROD_NEON_FETCH_TIME[$root]:-0}
    if (( now-last >= ROD_PROMPT_GIT_SYNC_INTERVAL )); then
      _ROD_NEON_FETCH_TIME[$root]=$now
      ( command git -C "$root" -c credential.interactive=never fetch --quiet --no-tags --prune  </dev/null >/dev/null 2>&1 ) &!
    fi
  fi
}
_rod_neon_status_label() {
  local rc=$1
  case $rc in
    0) REPLY='✓ 0 · Sucesso' ;;
    1) REPLY='✕ 1 · Erro geral' ;;
    2) REPLY='✕ 2 · Uso inválido' ;;
    126) REPLY='✕ 126 · Sem permissão' ;;
    127) REPLY='✕ 127 · Comando não encontrado' ;;
    130) REPLY='✕ 130 · Ctrl+C' ;;
    137) REPLY='✕ 137 · Processo encerrado' ;;
    *) REPLY="✕ $rc · Falha" ;;
  esac
  (( ROD_PROMPT_ERROR_TEXT )) || REPLY=${REPLY%% · *}
}
_rod_neon_precmd() {
  local rc=$? width=${COLUMNS:-80} path="${(%):-%~}" branch='' root='' dir='' gitpart='' state='' info='' dots='' header='' status='' color='' pad='' left='' right=''
  (( width < 20 )) && width=20
  _ROD_NEON_LAST_RC=$rc
  _rod_neon_short "$path" "$ROD_PROMPT_DIR_MODE" "$ROD_PROMPT_DIR_MAX" "$ROD_PROMPT_DIR_KEEP"; dir=$REPLY
  if (( ROD_PROMPT_SHOW_BRANCH )) && (( $+commands[git] )); then
    root=$(command git rev-parse --show-toplevel 2>/dev/null) || root=''
    if [[ -n $root ]]; then
      branch=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=$(command git rev-parse --short HEAD 2>/dev/null) || branch=''
      local fullbranch=$branch
      _rod_neon_short "$branch" "$ROD_PROMPT_BRANCH_MODE" "$ROD_PROMPT_BRANCH_MAX" 1; branch=$REPLY
      _rod_neon_git "$root" "$fullbranch"; state=$REPLY
      local -a fields; fields=("${(@s/:/)state}")
      local dot='●' dotcolor=240
      if (( fields[3] && ROD_PROMPT_GIT_UNTRACKED )); then dotcolor=203
      elif (( fields[2] && ROD_PROMPT_GIT_STAGED )); then dotcolor=84
      elif (( fields[1] && ROD_PROMPT_GIT_DIRTY )); then dotcolor=221; fi
      _rod_neon_safe "$ROD_PROMPT_BRANCH_ICON $branch"; gitpart="%F{$ROD_PROMPT_BRANCH_COLOR}$REPLY%f %F{$dotcolor}$dot%f"
      (( fields[4] > 0 )) && gitpart+=" %F{177}↑${fields[4]}%f"
      (( fields[5] > 0 )) && gitpart+=" %F{177}↓${fields[5]}%f"
    fi
  fi
  local userpart='' username=${(%):-%n}
  if (( ROD_PROMPT_SHOW_USER )); then
    _rod_neon_safe "$username"
    userpart="%K{$ROD_PROMPT_USER_BG}%F{$ROD_PROMPT_USER_COLOR} $REPLY %f%k "
  fi
  local budget=$(( width - ${#username} - ${#branch} - 14 ))
  if (( budget < 6 )); then
    _rod_neon_short "$dir" smart "$(( width / 3 ))" 1; dir=$REPLY
  fi
  _rod_neon_safe "$dir"; header="${userpart}%F{$ROD_PROMPT_DIR_COLOR}$REPLY%f"
  [[ -n $gitpart ]] && header+=" $gitpart"
  local plainlen=$(( ${#username} + ${#dir} + ${#branch} + 7 ))
  local fill=$(( width-plainlen ))
  (( fill < 0 )) && fill=0
  if (( ROD_PROMPT_DOTS && fill > 0 )); then
    dots="${(l:$fill::$ROD_PROMPT_DOT_CHAR:)}"
    header+=" %F{$ROD_PROMPT_DIM_COLOR}$dots%f"
  fi
  local statusline=''
  if (( _ROD_NEON_RAN && (rc != 0 || ROD_PROMPT_SHOW_SUCCESS) )); then
    if (( rc != 0 && ROD_PROMPT_SHOW_ERROR || rc == 0 && ROD_PROMPT_SHOW_SUCCESS )); then
      _rod_neon_status_label "$rc"; status=$REPLY
      local size=${#status} free=$(( width-size-2 ))
      (( free < 0 )) && free=0
      case $ROD_PROMPT_ERROR_POSITION in
        hidden) statusline='' ;;
        inline) header+=" %F{203}$status%f" ;;
        left) statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$free::$ROD_PROMPT_DOT_CHAR:)}%f" ; statusline="%F{203}$status%f $statusline" ;;
        right) statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$free::$ROD_PROMPT_DOT_CHAR:)}%f %F{203}$status%f" ;;
        *) left=$((free/2)); right=$((free-left)); statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$left::$ROD_PROMPT_DOT_CHAR:)}%f %F{203}$status%f %F{$ROD_PROMPT_DIM_COLOR}${(l:$right::$ROD_PROMPT_DOT_CHAR:)}%f" ;;
      esac
    fi
  elif (( _ROD_NEON_RAN && ROD_PROMPT_SHOW_SEPARATOR && ROD_PROMPT_DOTS )); then
    statusline="%F{$ROD_PROMPT_DIM_COLOR}${(l:$width::$ROD_PROMPT_DOT_CHAR:)}%f"
  fi
  _ROD_NEON_RAN=1
  local symbolcolor=84
  (( rc )) && symbolcolor=203
  PROMPT="${statusline:+$statusline$'\n'}$header
%F{177}$ROD_PROMPT_CORNER%f %F{$symbolcolor}$ROD_PROMPT_SYMBOL%f "
  RPROMPT=''
}
add-zsh-hook precmd _rod_neon_precmd
