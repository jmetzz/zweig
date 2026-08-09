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
    # This file is sourced as-is by both bash and zsh, and zsh's arrays are
    # 1-indexed by default (unlike bash's 0-indexed ones), so array indexing
    # here is deliberately avoided in favor of tracking the last positional
    # arg as we go - that works identically in either shell.
    shift
    local switch_after="false"
    local args=()
    local target=""
    local arg
    for arg in "$@"; do
      if [[ "$arg" == "-s" ]]; then
        switch_after="true"
      else
        args+=("$arg")
        target="$arg"
      fi
    done

    command zg create "${args[@]}" || return $?

    if [[ "$switch_after" == "true" && -n "$target" ]]; then
      local dir
      if dir="$(command zg path "$target")"; then
        cd "$dir" || return
      fi
    fi
  else
    command zg "$@"
  fi
}