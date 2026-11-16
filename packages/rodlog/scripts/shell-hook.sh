#!/bin/sh
# rodlog hook. Compatible with bash and zsh when sourced.
rlog() { rodlog exec -- "$@"; }
rlog-raw() { rodlog exec --mode raw -- "$@"; }
rlog-color() { rodlog exec --color always -- "$@"; }
