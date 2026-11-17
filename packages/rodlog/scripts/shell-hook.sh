#!/bin/sh
# Source in Bash or Zsh. External executable wrapping is explicitly opt-in.
rlog() { rodlog exec -- "$@"; }
rlog-raw() { rodlog exec --mode raw -- "$@"; }
rlog-color() { rodlog exec --color always -- "$@"; }

_rodlog_wrap() {
  case "$1" in gcloud|docker|npm|tsc|wrangler) ;; *) return 0 ;; esac
  # Never replace existing aliases, shell functions, or unavailable commands.
  if alias "$1" >/dev/null 2>&1; then return 0; fi
  if ! command -v rodlog >/dev/null 2>&1; then return 0; fi
  case "$(type "$1" 2>/dev/null)" in
    *"function"*|*"alias"*) return 0 ;;
  esac
  # An external executable must exist; builtins and shell functions are not safe.
  _rodlog_executable=$(command -v "$1") || return 0
  case "$_rodlog_executable" in /*) ;; *) return 0 ;; esac
  # The allowlist above prevents arbitrary code injection through eval.
  eval "$1() { rodlog exec -- \"$_rodlog_executable\" \"\$@\"; }"
  unset _rodlog_executable
}

if [ -n "${RODLOG_WRAP_COMMANDS:-}" ]; then
  _rodlog_old_ifs=$IFS
  IFS=,
  for _rodlog_candidate in $RODLOG_WRAP_COMMANDS; do
    _rodlog_wrap "$_rodlog_candidate"
  done
  IFS=$_rodlog_old_ifs
  unset _rodlog_candidate _rodlog_old_ifs
fi
