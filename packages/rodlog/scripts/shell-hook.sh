#!/bin/sh
# Source in Bash or Zsh. Wrapping is opt-in; existing aliases/functions are untouched.
rlog() { rodlog exec -- "$@"; }
rlog-raw() { rodlog exec --mode raw -- "$@"; }
rlog-color() { rodlog exec --color always -- "$@"; }

_rodlog_wrap() {
  case "$1" in gcloud|docker|npm|tsc|wrangler) ;; *) return 0 ;; esac
  if alias "$1" >/dev/null 2>&1; then return 0; fi
  if ! command -v "$1" >/dev/null 2>&1; then return 0; fi
  if ! command -v rodlog >/dev/null 2>&1; then return 0; fi
  case "$(type "$1" 2>/dev/null)" in *"function"*) return 0 ;; esac
  eval "$1() { rodlog exec --tool=$1 -- $1 \"\$@\"; }"
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
