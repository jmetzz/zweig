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

# --- Resolve the control repo root (works from inside a linked worktree too) ---
# Uses git-common-dir, which always points at the main repo's .git, so the same
# root (and thus the same worktree dir) resolves no matter which worktree you're in.
zg__control_root() {
  local git_common_dir toplevel abs
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  toplevel="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  if [[ "$git_common_dir" == /* ]]; then
    abs="$git_common_dir"
  else
    abs="$toplevel/$git_common_dir"
  fi
  (cd "$abs/.." && pwd)
}

# --- Worktree directory: repo-local by default, override wins, $HOME as last resort ---
if [[ -n "${ZWEIG_WORKTREE_DIR:-}" ]]; then
  : # explicit override wins
elif _zg_control_root="$(zg__control_root)"; then
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
