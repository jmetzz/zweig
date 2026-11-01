#!/usr/bin/env bash
# Zweig shell shim - source this file so zg commands that move you (cd/switch,
# root, main, select, create -s, create from-pr) change the current shell's
# directory (a subprocess can't change the parent shell's directory).

# Directory handoff: zg moves the shell by writing the target directory (one
# line, an absolute path) to the file named in ZG_CD_FILE, which we set in
# zg's environment only; we cd there after a successful run. One file per shell
# session, created here so subshells share it, recreated if a tmp cleaner
# removed it, and emptied around every run so a path left by an interrupted or
# failed run never moves you later. Overlapping runs (zg ... &) share it: a
# background run can empty or overwrite the path a foreground run left, so the
# shell may not move, or move where the other run pointed. The zg-cd. name
# prefix is checked by zg_helpers_request_cd; keep the two in sync.
__ZG_CD_FILE="$(mktemp "${TMPDIR:-/tmp}/zg-cd.XXXXXX" 2>/dev/null)" || __ZG_CD_FILE=""

__zg_run_with_cd() {
  local dir="" rc=0
  if [[ -z "$__ZG_CD_FILE" || ! -f "$__ZG_CD_FILE" ]]; then
    __ZG_CD_FILE="$(mktemp "${TMPDIR:-/tmp}/zg-cd.XXXXXX" 2>/dev/null)" || __ZG_CD_FILE=""
  fi
  if [[ -z "$__ZG_CD_FILE" ]] || ! : 2>/dev/null > "$__ZG_CD_FILE"; then
    # Degraded mode, no usable temp file: still run zg; commands that move you
    # print the path (and the "source the shim" hint) instead.
    command zg "$@"
    return
  fi
  ZG_CD_FILE="$__ZG_CD_FILE" command zg "$@" || rc=$?
  IFS= read -r dir 2>/dev/null < "$__ZG_CD_FILE" || true
  : 2>/dev/null > "$__ZG_CD_FILE"
  if [[ -n "$dir" ]]; then
    if [[ $rc -ne 0 ]]; then
      echo "zg: not changing directory (zg exited $rc)" >&2
    else
      cd "$dir" || rc=$?
    fi
  fi
  return $rc
}

# cd/switch and create -s predate the handoff and still look the target up
# with `zg path`; every other command goes through __zg_run_with_cd. For
# create from-pr -s both apply and land in the same directory.
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

    __zg_run_with_cd create "${args[@]}" || return $?

    if [[ "$switch_after" == "true" && -n "$target" ]]; then
      local dir
      if dir="$(command zg path "$target")"; then
        cd "$dir" || return
      fi
    fi
  else
    __zg_run_with_cd "$@"
  fi
}