#!/bin/sh
# Source this file from Bash or Zsh, or evaluate its output.
rlog() {
  rodlog exec -- "$@"
}
rlog-raw() {
  rodlog exec --mode raw -- "$@"
}
rlog-color() {
  rodlog exec --color always -- "$@"
}
