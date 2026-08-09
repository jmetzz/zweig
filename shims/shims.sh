#!/usr/bin/env bash
# Zweig shell shim - source this file to enable 'zg cd'/'zg switch' in the current shell.

zg() {
  if [[ "$1" == "cd" || "$1" == "switch" ]]; then
    local target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: zg cd <worktree|branch>" >&2
      return 2
    fi
    local dir
    if ! dir="$(command zg path "$target")"; then
      return $?
    fi
    cd "$dir" || return
  else
    command zg "$@"
  fi
}