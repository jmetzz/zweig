#!/usr/bin/env bash
# Zweig shell shim - source this file so zg commands that move you (cd/switch,
# root, main, select, create -s, create from-pr) change the current shell's
# directory (a subprocess can't change the parent shell's directory).

# Runs zg with ZG_CD_FILE pointing at a fresh temp file; a command that wants
# to move the shell writes the target directory there, and we cd to it after a
# successful run.
__zg_run() {
  local cd_file dir rc=0
  cd_file="$(mktemp "${TMPDIR:-/tmp}/zg-cd.XXXXXX")" || return 1
  ZG_CD_FILE="$cd_file" command zg "$@" || rc=$?
  dir="$(cat "$cd_file")"
  rm -f "$cd_file"
  if [[ $rc -eq 0 && -n "$dir" ]]; then
    cd "$dir" || rc=$?
  fi
  return $rc
}

zg() {
  if [[ "$1" == "cd" || "$1" == "switch" ]]; then
    local target="${2:-}"
    if [[ -z "$target" ]]; then
      echo "usage: zg cd <worktree|branch>" >&2
      return 2
    fi
    local dir
    dir="$(command zg path "$target")" || return $?
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

    __zg_run create "${args[@]}" || return $?

    if [[ "$switch_after" == "true" && -n "$target" ]]; then
      local dir
      if dir="$(command zg path "$target")"; then
        cd "$dir" || return
      fi
    fi
  else
    __zg_run "$@"
  fi
}