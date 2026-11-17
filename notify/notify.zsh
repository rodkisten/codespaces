# Rod Notify: lightweight native Zsh hooks.
[[ -o interactive ]] || return 0
zmodload zsh/datetime || return 0
autoload -Uz add-zsh-hook
typeset -g _ROD_NOTIFY_START='' _ROD_NOTIFY_CMD='' _ROD_NOTIFY_DIR=''
: ${ROD_NOTIFY_THRESHOLD:=10}
: ${ROD_NOTIFY_SUCCESS:=1}
: ${ROD_NOTIFY_FAILURE:=1}
: ${ROD_NOTIFY_IGNORE_INTERACTIVE:=1}
: ${ROD_NOTIFY_HOSTNAME:=1}
typeset -ga ROD_NOTIFY_IGNORED
ROD_NOTIFY_IGNORED=(ssh sftp vim vi nvim micro nano less more top htop btop watch tmux screen)
_rod_notify_preexec() {
  _ROD_NOTIFY_START=$EPOCHREALTIME
  _ROD_NOTIFY_CMD=$1
  _ROD_NOTIFY_DIR=$PWD
}
_rod_notify_precmd() {
  local rc=$? started=$_ROD_NOTIFY_START cmd=$_ROD_NOTIFY_CMD dir=$_ROD_NOTIFY_DIR
  _ROD_NOTIFY_START=''
  [[ -n $started ]] || return 0
  local elapsed=$(( EPOCHREALTIME - started ))
  (( elapsed >= ROD_NOTIFY_THRESHOLD )) || return 0
  if (( rc == 0 )); then
    (( ROD_NOTIFY_SUCCESS )) || return 0
  else
    (( ROD_NOTIFY_FAILURE )) || return 0
  fi
  local first=${${(z)cmd}[1]}
  if (( ROD_NOTIFY_IGNORE_INTERACTIVE )) && (( ${ROD_NOTIFY_IGNORED[(Ie)$first]} )); then
    return 0
  fi
  # Never send command arguments: they may contain passwords, tokens or private data.
  # Only the executable name, working directory basename, duration and exit code.
  [[ -n $first ]] || first=command
  local sender="$HOME/.config/rod-notify/send.sh"
  [[ -x $sender ]] || return 0
  ( "$sender" "$first" "$dir:t" "${elapsed}" "$rc" ) </dev/null >/dev/null 2>&1 &!
  return 0
}
add-zsh-hook preexec _rod_notify_preexec
add-zsh-hook precmd _rod_notify_precmd
