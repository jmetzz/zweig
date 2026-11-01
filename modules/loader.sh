#!/usr/bin/env bash
set -euo pipefail

# --- Detect Zweig Root ---
ZWEIG_ROOT="$(cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ZWEIG_ROOT
export ZWEIG_DEFAULT_BRANCH="${ZWEIG_DEFAULT_BRANCH:-main}"
export ZWEIG_DEFAULT_SYNC_SCOPE="${ZWEIG_DEFAULT_SYNC_SCOPE:-current}"

# Local (usually gitignored) files/dirs copied into every newly created worktree,
# relative to the repo root. Space-separated; override to add or drop entries.
export ZWEIG_COPY_ON_CREATE="${ZWEIG_COPY_ON_CREATE:-.env .env.local .env.development .env.test .env.production AGENTS.md CLAUDE.md GEMINI.md .claude .cursor .codex .antigravity}"

# Return codes of zg__control_root.
# (Guarded: re-sourcing the loader in one shell must not hit a readonly error.)
if [[ -z "${ZG_ROOT_NOT_IN_TREE:-}" ]]; then
  readonly ZG_ROOT_NOT_IN_TREE=1   # not in a work tree (e.g. inside a bare repo's git dir)
  readonly ZG_ROOT_UNKNOWN=2       # in a work tree, but the root can't be determined
fi

# Prints the physical git dir that <dir>/.git leads to: a directory, a symlink,
# or a gitfile ("gitdir: <path>", relative to <dir>). Fails when <dir>/.git is
# missing, is a file that isn't a gitfile, or leads nowhere.
zg__dot_git_target() {
  local dir="$1" line target
  if [[ -d "$dir/.git" ]]; then
    (cd "$dir/.git" && pwd -P)
  elif [[ -f "$dir/.git" ]]; then
    IFS= read -r line <"$dir/.git" || [[ -n "$line" ]] || return 1
    line="${line%"${line##*[![:space:]]}"}"   # trailing \r / whitespace
    [[ "$line" == "gitdir: "* ]] || return 1
    target="${line#gitdir: }"
    [[ "$target" == /* ]] || target="$dir/$target"
    (cd "$target" 2>/dev/null && pwd -P)
  else
    return 1
  fi
}

# --- Resolve the control repo root ---
# Prints a physical path. The same root (and thus the same worktree dir)
# resolves from the main checkout, any subfolder of it, or a linked worktree
# that lives inside the repo. In order:
#   1. GIT_WORK_TREE set: that work tree is the root (git's own top level).
#   2. The nearest directory, from the current top level upwards (inclusive),
#      whose .git (directory, symlink or gitfile: submodule, --separate-git-dir)
#      resolves to the repo's git dir. A linked worktree's gitfile points into
#      <git dir>/worktrees, so it never matches and the walk continues.
#   3. The parent of the git dir, if <parent>/.git is that git dir, or if the
#      main repo is bare (a bare main repo has no checkout; its parent is the
#      root for its linked worktrees). This is what resolves a linked worktree
#      outside a normal repo.
# Git keeps no pointer back to the main checkout, so a linked worktree outside
# a repo whose .git is a symlink or gitfile can't be resolved. Known residual:
# if that repo's git dir itself sits in a directory named .git elsewhere, step 3
# picks that directory's parent.
# Returns ZG_ROOT_NOT_IN_TREE outside a work tree, ZG_ROOT_UNKNOWN when none of
# the above finds a root. It never guesses.
zg__control_root() {
  local common_dir git_dir top_raw work_top dir
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return "$ZG_ROOT_NOT_IN_TREE"
  # Only inside a work tree (not a bare repo's git dir).
  top_raw="$(git rev-parse --show-toplevel 2>/dev/null)" || return "$ZG_ROOT_NOT_IN_TREE"
  if [[ "$common_dir" != /* ]]; then
    # A relative git-common-dir (e.g. "../.git" from a subfolder of the main
    # checkout) is relative to the current directory, not the top level.
    common_dir="$(pwd -P)/$common_dir"
  fi
  # pwd -P resolves symlinks, so symlinked prefixes (macOS /var) can't give one
  # repo two roots.
  git_dir="$(cd "$common_dir" 2>/dev/null && pwd -P)" || return "$ZG_ROOT_UNKNOWN"
  work_top="$(cd "$top_raw" 2>/dev/null && pwd -P)" || return "$ZG_ROOT_UNKNOWN"

  if [[ -n "${GIT_WORK_TREE:-}" ]]; then
    echo "$work_top"
    return 0
  fi
  dir="$work_top"
  while :; do
    if [[ "$(zg__dot_git_target "$dir")" == "$git_dir" ]]; then
      echo "$dir"
      return 0
    fi
    [[ "$dir" != / ]] || break
    dir="$(dirname "$dir")"
  done
  dir="$(dirname "$git_dir")"
  if [[ "$(git --git-dir="$git_dir" rev-parse --is-bare-repository 2>/dev/null)" == true ]] \
    || [[ "$(zg__dot_git_target "$dir")" == "$git_dir" ]]; then
    echo "$dir"
    return 0
  fi
  return "$ZG_ROOT_UNKNOWN"
}

# --- Worktree directory: repo-local by default, override wins, $HOME as last resort ---
# The root is resolved once here; the dispatcher reuses the result while the
# working directory is unchanged (a sourced loader can outlive a `cd`).
_zg_wt_dir_explicit=0
[[ -z "${ZWEIG_WORKTREE_DIR:-}" ]] || _zg_wt_dir_explicit=1
_zg_root_rc=0
_zg_control_root="$(zg__control_root)" || _zg_root_rc=$?
_zg_root_pwd="$PWD"
if ((_zg_wt_dir_explicit)); then
  : # explicit override wins
elif ((_zg_root_rc == 0)); then
  ZWEIG_WORKTREE_DIR="$_zg_control_root/.worktrees"
else
  ZWEIG_WORKTREE_DIR="$HOME/.worktrees"
fi
unset _zg_control_root
export ZWEIG_WORKTREE_DIR
# Not created here: resolving the path must have no filesystem side effects.
# `git worktree add` creates missing parent directories on demand. The directory
# may therefore not exist yet; every caller must tolerate that (nullglob for
# loops, a -d check before find/ls).

# --- Aliases normalization ---
zg__normalize_cmd() {
  case "$1" in
    cd) echo "switch" ;;
    rm) echo "remove" ;;
    rebase) echo "sync" ;;   # alias: rebase → sync current
    *) echo "$1" ;;
  esac
}

# --- Source all modules (except loader itself) ---
for mod in helpers core maintenance extensions; do
  # shellcheck disable=SC1090
  source "$ZWEIG_ROOT/modules/$mod.sh"
done

# --- Map command -> module ---
zg__route_module() {
  case "$1" in
    list|root|switch|create|remove|finalize|rebuild|main|path) echo core ;;
    status|sync|migrate|protect|unprotect|prune)          echo maintenance ;;
    help|version)                                  echo helpers ;;
    select)                                               echo extensions ;;
    *) echo "" ;;
  esac
}

# --- Capability checks for extensions ---
zg__has() { declare -F "$1" >/dev/null 2>&1; }

zg__ext_from_pr_available() {
  zg__has zg_extensions_from_pr && command -v gh >/dev/null 2>&1
}

zg__ext_select_available() {
  zg__has zg_extensions_select && command -v fzf >/dev/null 2>&1
}

# --- Allowed subcommands (used for help + autocomplete) ---
zg__allowed_subs_for() {
  case "$1" in
    create)
      local subs="from"
      if zg__ext_from_pr_available; then
        subs+=" from_pr"
      fi
      echo "$subs" ;;
    remove) echo "merged" ;;
    prune)  echo "metadata trees" ;;
    sync)   echo "all current" ;;
    *)      echo "" ;;
  esac
}


# --- Main dispatcher ---
zg() {

  local cmd="${1:-}"; shift || true
  cmd="$(zg__normalize_cmd "$cmd")"

  # commands that don't require a repo
  case "$cmd" in
    help|version) ;;  # allowed outside repos
    *) if ! zg_helpers_inside_git_repo; then
         echo "❌ Not inside a Git repository"; return 1
       fi
       # Refuse rather than put worktrees in a wrong place. Not needed with an
       # explicit ZWEIG_WORKTREE_DIR. ZG_ROOT_NOT_IN_TREE (a bare repo's git
       # dir) is left to each command, which falls back to its own top level.
       if ((! _zg_wt_dir_explicit)); then
         local root_rc
         if [[ "$_zg_root_pwd" == "$PWD" ]]; then
           root_rc="$_zg_root_rc"
         else
           root_rc=0
           zg__control_root >/dev/null || root_rc=$?
         fi
         if ((root_rc == ZG_ROOT_UNKNOWN)); then
           echo "❌ Cannot determine the repository root." >&2
           echo "   git dir:   $(git rev-parse --git-common-dir 2>/dev/null)" >&2
           echo "   work tree: $(git rev-parse --show-toplevel 2>/dev/null)" >&2
           if [[ -n "${GIT_DIR:-}" ]]; then
             echo "   GIT_DIR is set: unset it, or also set GIT_WORK_TREE." >&2
           else
             echo "   No directory from the work tree upwards has a .git that leads to that git dir." >&2
             echo "   Run zg from the main checkout, or set ZWEIG_WORKTREE_DIR." >&2
           fi
           return 1
         fi
       fi ;;
  esac

  if [[ "$cmd" == "select" ]] && ! zg__ext_select_available; then
    echo "❌ 'select' is unavailable. Install fzf to enable this command." >&2
    return 1
  fi

  local mod; mod="$(zg__route_module "$cmd")"
  if [[ -z "$mod" ]]; then
    echo "❌ Unknown command: $cmd" >&2
    zg_helpers_help
    return 1
  fi

  # Handle subcommands
  local sub=""; local norm_sub
  if [[ -n "${1:-}" ]]; then
    for s in $(zg__allowed_subs_for "$cmd"); do
      norm_sub="${1//-/_}"
      if [[ "$norm_sub" == "$s" ]]; then
        sub="$s"
        shift || true
        break
      fi
    done
  fi

  # Special gate: create from-pr (extension)
  if [[ "$cmd" == "create" && "$sub" == "from_pr" ]]; then
    if zg__ext_from_pr_available; then
      [[ "${ZG_TRACE:-0}" == "1" ]] && echo "→ zg_extensions_from_pr $*"
      zg_extensions_from_pr "$@"
      return
    else
      echo "❌ 'create from-pr' is unavailable. Install GitHub CLI (gh) to enable this command." >&2
      return 1
    fi
  fi

  # Compute target function
  local fn="zg_${mod}_${cmd}"
  [[ -n "$sub" ]] && fn+="_${sub//-/_}"

  # Trace mode
  [[ "${ZG_TRACE:-0}" == "1" ]] && echo "→ $fn $*"

  if ! declare -F "$fn" >/dev/null 2>&1; then
    echo "❌ Not implemented: $fn" >&2
    return 127
  fi
  "$fn" "$@"
}
