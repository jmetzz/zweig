#!/usr/bin/env bash
# Zweig shell shim - source this file to enable 'zg cd'/'zg switch' and 'zg create -s'
# in the current shell (a subprocess can't change the parent shell's directory).

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
  elif [[ "$1" == "create" ]]; then
    shift
    local switch_after="false"
    local args=()
    local arg
    for arg in "$@"; do
      if [[ "$arg" == "-s" ]]; then
        switch_after="true"
      else
        args+=("$arg")
      fi
    done

    command zg create "${args[@]}" || return $?

    if [[ "$switch_after" == "true" && ${#args[@]} -gt 0 ]]; then
      local target="${args[$(( ${#args[@]} - 1 ))]}"
      local dir
      if dir="$(command zg path "$target")"; then
        cd "$dir" || return
      fi
    fi
  else
    command zg "$@"
  fi
}