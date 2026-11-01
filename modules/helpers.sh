#!/usr/bin/env bash
# Zweig Helpers Module - helpers.sh
# Provides reusable helper functions for the other modules.
# Requires: bash 4.3+ (namerefs: zg_helpers_split_worktree_line,
# zg_helpers_load_worktrees, zg_helpers_load_report_worktrees,
# zg_helpers_report_mark). zg_helpers_load_report_worktrees also calls
# zg__control_root from loader.sh.

set -u

zg_helpers_inside_git_repo() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1
}

zg_helpers_inside_control_repo() {
    local git_dir
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        echo "❌ Not a git repo"
        return 1
    fi
    git_dir="$(git rev-parse --git-dir)"
    if [[ "$git_dir" == *worktrees* ]]; then
        echo "❌ You are inside a worktree"
        return 1
    fi
    return 0
}

zg_helpers_has_origin() {
    git remote get-url origin >/dev/null 2>&1
}

# Fetch origin safely (used by status/sync/prune). Quiet by default.
zg_helpers_fetch_origin() {
    # Ensure we're inside a Git repository
    git rev-parse --git-dir >/dev/null 2>&1 || {
        echo "❌ Error: Not inside a Git repository." >&2
        return 1
    }

    # If 'origin' is configured, fetch from it; otherwise, skip gracefully
    if zg_helpers_has_origin; then
        git fetch origin --prune --quiet || {
            echo "❌ Error: Failed to fetch from origin. Check network/credentials." >&2
            return 1
        }
    else
        echo "ℹ️ No 'origin' remote configured; skipping fetch."
    fi
}

zg_helpers_branch_exists() {
    git show-ref --quiet refs/heads/"$1" || git show-ref --quiet refs/remotes/origin/"$1"
}

# Only checks for a directory under ZWEIG_WORKTREE_DIR. To look a worktree up
# by name or branch wherever it lives, use zg_helpers_resolve_worktree.
zg_helpers_worktree_exists() {
    [ -d "$ZWEIG_WORKTREE_DIR/$1" ]
}

# --- Print the path git has registered for a branch's worktree ---
# The path is printed even if that directory no longer exists. Returns 1 if the
# branch isn't checked out in any worktree, 2 if git can't list worktrees (so
# callers don't mistake a git failure for "not checked out").
zg_helpers_branch_worktree_path() {
    local branch="$1" listing line
    [[ -n "$branch" ]] || return 1
    listing="$(zg_helpers_list_worktrees --all)" || return 2
    # line_head is filled by the split but not needed here.
    # shellcheck disable=SC2034
    local line_branch line_head line_path
    while IFS= read -r line; do
        zg_helpers_split_worktree_line "$line" line_branch line_head line_path
        if [[ "$line_branch" == "$branch" ]]; then
            printf '%s\n' "$line_path"
            return 0
        fi
    done <<<"$listing"
    return 1
}

# --- Split a zg_helpers_list_worktrees line into named variables ---
# Usage: zg_helpers_split_worktree_line <line> <branch-var> <head-var> <path-var>
zg_helpers_split_worktree_line() {
    local -n _zg_split_branch="$2" _zg_split_head="$3" _zg_split_path="$4"
    local _zg_split_rest="${1#*$'\t'}"
    _zg_split_branch="${1%%$'\t'*}"
    _zg_split_head="${_zg_split_rest%%$'\t'*}"
    _zg_split_path="${_zg_split_rest#*$'\t'}"
}

# --- List every linked worktree of the repo, wherever it lives on disk ---
# Usage: zg_helpers_list_worktrees [--all]
# Prints one "<branch>\t<head>\t<path>" line per worktree, skipping bare entries
# and, unless --all is given, the main worktree (always the first porcelain
# record, wherever it's run from).
# The branch is empty for a detached HEAD; <head> is the short (7-char) commit
# id. Paths are printed even if the directory no longer exists. Returns 1 if
# git can't list worktrees.
#
# Neither refs nor commit ids contain a tab, so callers split with
# zg_helpers_split_worktree_line (paths containing a tab or newline are not
# supported). Not `IFS=$'\t' read`: tab is IFS whitespace, so read would drop
# an empty (detached) branch field.
zg_helpers_list_worktrees() {
    local porcelain first=2
    case "${1:-}" in
        "") ;;
        --all) first=1 ;;
        *) echo "❌ Internal error: zg_helpers_list_worktrees got '$1'." >&2; return 1 ;;
    esac
    porcelain="$(git worktree list --porcelain)" || return 1
    # substr($0, 10), not $2: worktree paths may contain spaces, and
    # 10 = length("worktree ") + 1.
    # n counts records; record 1 is the main worktree, printed only with --all.
    awk -v first="$first" '
        function flush() { if (n >= first && wt != "" && !bare) printf "%s\t%s\t%s\n", br, hd, wt }
        $1=="worktree" {flush(); n++; wt=substr($0, 10); br=""; hd=""; bare=0}
        $1=="HEAD"     {hd=substr($2, 1, 7)}
        $1=="branch"   {br=$2; sub("^refs/heads/","",br)}
        $1=="bare"     {bare=1}
        END            {flush()}
    ' <<<"$porcelain"
}

# --- Load the linked worktrees for a bulk sweep into arrays ---
# Usage: zg_helpers_load_worktrees <branches-array> <dirs-array> [<heads-array>] [--all]
# Fills the named arrays in parallel, one element per worktree from
# zg_helpers_list_worktrees (branch empty for a detached HEAD; heads are short
# commit ids). With --all the main checkout is included, first. A worktree whose
# directory is missing is left out with a warning on stderr.
# Returns 0 when all were loaded; 2 when some were left out (already warned
# about, so callers decide whether that is a failure); 1 when git can't list
# worktrees (fatal: callers return 1).
zg_helpers_load_worktrees() {
    local -n _zg_branches="$1" _zg_dirs="$2"
    local _zg_load_heads="" _zg_load_all="" _zg_load_arg
    for _zg_load_arg in "${@:3}"; do
        if [[ "$_zg_load_arg" == --all ]]; then _zg_load_all=--all; else _zg_load_heads="$_zg_load_arg"; fi
    done
    # A throwaway target keeps the loop below simple when heads aren't wanted.
    local _zg_load_no_heads=()
    local -n _zg_heads="${_zg_load_heads:-_zg_load_no_heads}"
    local listing line branch head dir rc=0
    _zg_branches=() _zg_dirs=() _zg_heads=()
    # list_worktrees rejects anything but --all (a typo must not silently
    # drop the main checkout); its error is on stderr already.
    if ! listing="$(zg_helpers_list_worktrees "$_zg_load_all")"; then
        echo "❌ Error: Could not list worktrees." >&2
        return 1
    fi
    [[ -n "$listing" ]] || return 0
    while IFS= read -r line; do
        zg_helpers_split_worktree_line "$line" branch head dir
        if [[ -d "$dir" ]]; then
            _zg_branches+=("$branch") _zg_dirs+=("$dir") _zg_heads+=("$head")
        else
            echo "⚠️ Skipping $(zg_helpers_worktree_short_label "$branch" "$dir"): directory missing ($dir). Try: zg prune metadata" >&2
            rc=2
        fi
    done <<<"$listing"
    return "$rc"
}

# --- Name a worktree in messages (warnings, skip and sync lines) ---
# Its branch, or its directory name if detached: short, and points at the path.
# See also zg_helpers_worktree_report_name, used by list, status and select.
zg_helpers_worktree_short_label() {
    local branch="$1" dir="$2"
    if [[ -n "$branch" ]]; then printf '%s\n' "$branch"; else basename "$dir"; fi
}

# --- Name a worktree in reports (list, status, select) ---
# Usage: zg_helpers_worktree_report_name <branch> <dir> [<sha7>]
# Its branch, or "(detached: <sha7>)" for a detached HEAD; the commit is looked
# up when not given. See also zg_helpers_worktree_short_label, for messages.
zg_helpers_worktree_report_name() {
    local branch="$1" dir="$2" sha7="${3:-}"
    if [[ -n "$branch" ]]; then
        printf '%s\n' "$branch"
        return 0
    fi
    [[ -n "$sha7" ]] || sha7="$(git -C "$dir" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
    printf '(detached: %s)\n' "$sha7"
}

# --- Load every worktree for a report: main checkout first, the rest by name ---
# Usage: zg_helpers_load_report_worktrees <names-array> <dirs-array> <heads-array> <current-var>
# Names come from zg_helpers_worktree_report_name; heads are short (7-char)
# commit ids. <current-var> gets the index of the worktree the user is in, or
# -1. Rows with equal names keep path order. Same return codes and missing
# directory warnings as zg_helpers_load_worktrees.
zg_helpers_load_report_worktrees() {
    local -n _zg_names="$1" _zg_rdirs="$2" _zg_rheads="$3" _zg_current="$4"
    # Every local is prefixed: an unprefixed one (say "dirs") would shadow the
    # caller's variable of that name, which the namerefs above point at.
    local _zg_rep_branches _zg_rep_dirs _zg_rep_heads _zg_rep_i _zg_rep_line
    local _zg_rep_name _zg_rep_main _zg_rep_top _zg_rep_sorted="" _zg_rep_rc=0
    _zg_names=() _zg_rdirs=() _zg_rheads=() _zg_current=-1
    zg_helpers_load_worktrees _zg_rep_branches _zg_rep_dirs _zg_rep_heads --all || _zg_rep_rc=$?
    [[ $_zg_rep_rc -ne 1 ]] || return 1

    # 1/3 The main checkout leads, unsorted. With --all it is the first row,
    # unless the main entry is a bare repo (never listed) or its directory is
    # missing (skipped): then row 0 is just the first linked worktree, so it
    # only counts if it is the control root.
    _zg_rep_main=""
    if ((${#_zg_rep_dirs[@]} > 0)) && _zg_rep_main="$(zg__control_root)"; then
        _zg_rep_main="$(cd "$_zg_rep_main" 2>/dev/null && pwd -P)" || _zg_rep_main=""
    fi

    # 2/3 Sort the rest as "<name>\t<head>\t<dir>": none of the three can hold
    # a tab, so lines split cleanly, and equal names fall back to path order.
    for ((_zg_rep_i = 0; _zg_rep_i < ${#_zg_rep_dirs[@]}; _zg_rep_i++)); do
        _zg_rep_name="$(zg_helpers_worktree_report_name "${_zg_rep_branches[_zg_rep_i]}" \
            "${_zg_rep_dirs[_zg_rep_i]}" "${_zg_rep_heads[_zg_rep_i]}")"
        if ((_zg_rep_i == 0)) && [[ -n "$_zg_rep_main" \
            && "$(cd "${_zg_rep_dirs[0]}" 2>/dev/null && pwd -P)" == "$_zg_rep_main" ]]; then
            _zg_names+=("$_zg_rep_name") _zg_rdirs+=("${_zg_rep_dirs[0]}") _zg_rheads+=("${_zg_rep_heads[0]}")
        else
            _zg_rep_sorted+="$_zg_rep_name"$'\t'"${_zg_rep_heads[_zg_rep_i]}"$'\t'"${_zg_rep_dirs[_zg_rep_i]}"$'\n'
        fi
    done
    if [[ -n "$_zg_rep_sorted" ]]; then
        # Case-insensitive byte order: alphabetical, and the same in every locale.
        _zg_rep_sorted="$(LC_ALL=C sort -f <<<"${_zg_rep_sorted%$'\n'}")"
        local _zg_rep_n _zg_rep_h _zg_rep_d
        while IFS= read -r _zg_rep_line; do
            # Same layout as a list_worktrees line, with the name for the branch.
            zg_helpers_split_worktree_line "$_zg_rep_line" _zg_rep_n _zg_rep_h _zg_rep_d
            _zg_names+=("$_zg_rep_n") _zg_rheads+=("$_zg_rep_h") _zg_rdirs+=("$_zg_rep_d")
        done <<<"$_zg_rep_sorted"
    fi

    # 3/3 The current worktree is the one whose top level the user is in.
    # Physical paths, so symlinked prefixes (macOS /var) can't hide a match; a
    # plain prefix test would also wrongly mark the main checkout from inside a
    # linked worktree nested under it (e.g. .worktrees/foo).
    _zg_rep_top=""
    if _zg_rep_top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
        _zg_rep_top="$(cd "$_zg_rep_top" 2>/dev/null && pwd -P)" || _zg_rep_top=""
    fi
    # Outside any work tree (top empty), nothing is marked.
    for ((_zg_rep_i = 0; _zg_rep_i < ${#_zg_rdirs[@]}; _zg_rep_i++)); do
        if [[ -n "$_zg_rep_top" && "$(cd "${_zg_rdirs[_zg_rep_i]}" 2>/dev/null && pwd -P)" == "$_zg_rep_top" ]]; then
            _zg_current=$_zg_rep_i
            break
        fi
    done
    return "$_zg_rep_rc"
}

# --- Pick a report row's marker and name colour ---
# Usage: zg_helpers_report_mark <mark-var> <colour-var> <is-current: 0|1>
# Call zg_helpers_colors first. The marker is two columns wide either way.
zg_helpers_report_mark() {
    local -n _zg_mark="$1" _zg_colour="$2"
    if [[ "$3" == 1 ]]; then
        _zg_mark="${ZG_C_CUR}*${ZG_C_RESET} " _zg_colour="$ZG_C_CUR"
    else
        _zg_mark="  " _zg_colour="$ZG_C_NAME"
    fi
}

# --- Set the report colours (ZG_C_* globals) ---
# Empty when NO_COLOR is set (https://no-color.org) or stdout is not a terminal,
# so piped output stays plain and scriptable.
# shellcheck disable=SC2034  # read by list and status in the other modules
zg_helpers_colors() {
    ZG_C_RESET="" ZG_C_NAME="" ZG_C_PATH="" ZG_C_HASH="" ZG_C_CUR=""
    if [[ -z "${NO_COLOR:-}" && -t 1 ]]; then
        ZG_C_RESET=$'\e[0m' ZG_C_NAME=$'\e[36m' ZG_C_PATH=$'\e[90m'
        ZG_C_HASH=$'\e[33m' ZG_C_CUR=$'\e[1;32m'
    fi
}

# --- Fail if a branch is already checked out in any worktree ---
# git refuses to check a branch out twice; this names the worktree holding it
# (wherever it lives) instead of surfacing git's raw error. Returns 1 if taken.
zg_helpers_ensure_branch_free() {
    local branch="$1" wt_path rc=0
    wt_path="$(zg_helpers_branch_worktree_path "$branch")" || rc=$?
    case $rc in
        0) echo "❌ Branch '$branch' is already checked out at $wt_path. Try: zg switch $branch" >&2 ;;
        1) return 0 ;;
        *) echo "❌ Error: Could not list worktrees." >&2 ;;
    esac
    return 1
}

# --- True if a worktree has uncommitted work or a git operation in progress ---
# Uncommitted work includes untracked files (ignored ones are not counted).
# Operations: merge, cherry-pick, revert or rebase. If git can't read the
# worktree at all, it also counts as busy: callers use this to decide what is
# safe to force-remove, so unknown state must err on the side of keeping it.
zg_helpers_worktree_busy() {
    local dir="$1" gitdir
    local status
    status="$(git -C "$dir" status --porcelain --ignore-submodules 2>/dev/null)" || return 0
    [[ -z "$status" ]] || return 0
    gitdir="$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null)" || return 0
    [[ -e "$gitdir/MERGE_HEAD" || -e "$gitdir/CHERRY_PICK_HEAD" || -e "$gitdir/REVERT_HEAD" \
        || -d "$gitdir/rebase-merge" || -d "$gitdir/rebase-apply" ]]
}

# --- Resolve a worktree identifier to its path (prints the path) ---
# The identifier is a branch name (canonical identity, see docs/adr/0001).
# Fast path: a directory of that name under ZWEIG_WORKTREE_DIR (no subprocess).
# It wins even if that directory holds a different branch (accepted trade-off,
# see the ADR). Fallback: the branch's worktree from `git worktree list`,
# which finds worktrees anywhere on disk, including ones other tools created.
# Returns 1 when nothing matches; prints nothing in that case.
zg_helpers_resolve_worktree() {
    local target="$1"
    [[ -n "$target" ]] || return 1
    # Never let an identifier walk out of the worktree dir (e.g. "..").
    [[ "/$target/" != */../* && "/$target/" != */./* ]] || return 1

    if [[ -d "$ZWEIG_WORKTREE_DIR/$target" ]]; then
        printf '%s\n' "$ZWEIG_WORKTREE_DIR/$target"
        return 0
    fi

    local worktree_path
    worktree_path="$(zg_helpers_branch_worktree_path "$target")" || return 1
    [[ -d "$worktree_path" ]] || return 1
    printf '%s\n' "$worktree_path"
}

# --- Report why a worktree identifier did not resolve (stderr only) ---
# Uses local refs only: no fetch, so a typo never waits on the network.
zg_helpers_report_worktree_not_found() {
    local target="$1" registered rc=0
    registered="$(zg_helpers_branch_worktree_path "$target")" || rc=$?
    if [[ $rc -eq 2 ]]; then
        echo "❌ Error: Could not list worktrees, so '$target' could not be looked up." >&2
        return 0
    fi
    echo "❌ Worktree or branch '$target' not found." >&2
    if [[ $rc -eq 0 ]]; then
        echo "ℹ️ Branch '$target' is registered to a missing directory ($registered). Try: zg prune metadata" >&2
    elif git show-ref --verify --quiet "refs/heads/$target" || \
         git show-ref --verify --quiet "refs/remotes/origin/$target"; then
        echo "ℹ️ Branch '$target' exists without a worktree. Try: zg create from $target" >&2
    fi
}

# --- Print the branch checked out in a worktree directory ---
# Prints an empty line for a detached HEAD. Returns 1, with an error on stderr,
# only if git can't read the directory at all.
zg_helpers_worktree_branch() {
    local branch
    if ! branch="$(git -C "$1" branch --show-current 2>/dev/null)"; then
        echo "❌ Cannot read the branch checked out in $1." >&2
        return 1
    fi
    printf '%s\n' "$branch"
}

# --- Path of the shell shim users should source ---
# An install keeps each release under <root>/versions/<label> and links the shim
# at <root>/shims/shims.sh; point at that stable link so a sourced line keeps
# working after an upgrade. A source checkout has no versions/ and is used as is.
zg_helpers_shim_path() {
    printf '%s\n' "${ZWEIG_ROOT%/versions/*}/shims/shims.sh"
}

# --- Move the caller's shell to a directory (through the shell shim) ---
# zg runs as a subprocess, so it can't change its caller's directory. The shim
# (shims/shims.sh) sets ZG_CD_FILE in zg's environment to a zg-cd.* temp file;
# write the target there as one line, and the shim cd's to it once zg exits
# successfully. A ZG_CD_FILE that isn't an existing zg-cd.* file (the name
# shims/shims.sh uses; keep in sync) is ignored rather than overwritten, and
# treated as no shim. Without the shim, print the path and how to enable it
# instead of claiming a switch that didn't happen.
# Usage: zg_helpers_request_cd <dir> <what>   e.g. "worktree: foo", "project root"
# (<what> is printed capitalised when the handoff isn't used: "Worktree: foo").
zg_helpers_request_cd() {
    local dir="$1" what="$2" handoff="${ZG_CD_FILE:-}"
    [[ "${handoff##*/}" == zg-cd.* && -f "$handoff" ]] || handoff=""
    if [[ -n "$handoff" ]] && printf '%s\n' "$dir" 2>/dev/null > "$handoff"; then
        echo "📂 Switching to $what"
        echo "   Path: $dir"
        return 0
    fi
    echo "📂 ${what^}"
    echo "   Path: $dir"
    if [[ -n "$handoff" ]]; then
        echo "❌ Could not hand the directory to the shell shim ($handoff)." >&2
        return 1
    fi
    echo "💡 To switch automatically, source the shell shim: . \"$(zg_helpers_shim_path)\"" >&2
}

# --- True if the current directory is the given directory or inside it ---
# Compares physical paths, so symlinked prefixes (macOS /var) can't hide a match.
# A directory that doesn't exist counts as "not inside".
zg_helpers_inside_dir() {
    local dir here
    dir="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
    here="$(pwd -P)"
    [[ "$here" == "$dir" || "$here" == "$dir"/* ]]
}

# --- True if a worktree identifier (branch or directory name) is protected ---
# The default branch is always protected, even without a worktree. Otherwise
# its worktree, wherever it lives, must be; an identifier that resolves to no
# worktree counts as not protected, since there is nothing on disk to protect.
zg_helpers_is_protected() {
    local wtree="$1" dir=""
    dir="$(zg_helpers_resolve_worktree "$wtree")" || dir=""
    zg_helpers_dir_is_protected "$wtree" "$dir"
}

# --- The protection rule: one place for every command ---
# Takes a branch name and the worktree directory (empty if there is none).
# Protected means the branch is the default branch, or the directory carries a
# .protected marker. Bulk sweeps call this directly with what they enumerated.
zg_helpers_dir_is_protected() {
    local branch="$1" dir="$2"
    [[ "$branch" == "$ZWEIG_DEFAULT_BRANCH" ]] && return 0
    [[ -n "$dir" && -f "$dir/.protected" ]]
}

# --- Guard for remove/finalize without --force ---
# Takes the name the user typed, the resolved worktree directory (empty if
# there is none) and the branch checked out there. Fails, with the reason on
# stderr, when the worktree is protected or holds the default branch. The
# branch is checked as well as the name, so the guard holds whichever name the
# worktree was addressed by.
zg_helpers_guard_protected() {
    local name="$1" dir="$2" branch="$3"
    if zg_helpers_dir_is_protected "$name" "$dir"; then
        echo "❌ '$name' is protected. Use --force to override." >&2
        return 1
    fi
    if [[ "$branch" == "$ZWEIG_DEFAULT_BRANCH" ]]; then
        echo "❌ '$name' holds the default branch '$branch'. Use --force to override." >&2
        return 1
    fi
}

# --- Seed a newly created worktree with local, usually-gitignored context files ---
# Copies each entry in ZWEIG_COPY_ON_CREATE (space-separated, relative to the repo
# root) from the control repo root into the new worktree, when present in the
# source and absent in the target. Never overwrites. Files and directories both work.
zg_helpers_seed_worktree() {
    local target_dir="$1"
    local root_dir="$2"
    local entry src dst

    for entry in $ZWEIG_COPY_ON_CREATE; do
        src="$root_dir/$entry"
        dst="$target_dir/$entry"

        [[ -e "$src" ]] || continue
        [[ -e "$dst" ]] && continue

        mkdir -p "$(dirname "$dst")"
        if cp -R "$src" "$dst"; then
            echo "📋 Copied $entry into worktree"
        else
            echo "⚠️  Failed to copy $entry into worktree" >&2
        fi
    done

    return 0
}

# --- Determine version from package.json ---
zg_helpers_version() {
    local version
    if command -v jq >/dev/null 2>&1; then
        version="$(jq -r '.version' "$ZWEIG_ROOT/package.json")"
    else
        version="$(grep -m1 '"version"' "$ZWEIG_ROOT/package.json" | cut -d '"' -f 4)"
    fi
    echo "Zweig CLI v${version:-unknown}"
}



# --- Print CLI Help ---
zg_helpers_help() {
    cat <<EOF
Zweig CLI (alias: zg)

Worktree Core Lifecycle:
  zg list [-d|--detail]             List all worktrees by name: main checkout first, the
                                     current one marked *. -d adds an aligned PATH/HEAD table.
  zg create <worktree name>         Create a new worktree (and local branch) from the default branch.
  zg create from <branch>           Create a worktree from an existing branch.
  zg create from-pr <pr-id>         Create worktree pr-<id>-<branch> from GitHub PR (requires gh);
                                     "/" in the branch becomes "-". Re-running switches to
                                     the PR's existing worktree.
  zg create ... -s                  Add -s to any create form to switch into it immediately
                                     (requires the shell shim; see shims/shims.sh).
  zg (remove|rm) <worktree>         Remove a worktree but keeps the branch.
  zg remove merged                  Remove worktrees whose branches are merged into the default branch,
                                     wherever they live on disk; detached ones, and ones with
                                     uncommitted work or a merge/rebase in progress, are skipped.
  zg (switch|cd) <worktree|branch>  Enter a worktree or switch to one by branch name.
                                     Finds worktrees anywhere on disk; detached ones
                                     only by their directory name under the worktree dir.
  zg finalize <branch>              Final cleanup after merge (removes worktree and branch).
                                     The default branch is never deleted, even with --force.
  zg rebuild <worktree>             Rebuild a worktree (removes and re-adds).
  zg protect <worktree>             Protect a worktree from accidental deletion.
  zg unprotect <worktree>           Remove protection marker from a worktree.

Maintenance:
  zg status                         Show sync status (ahead/behind) of every worktree of the
                                     repo, wherever it lives on disk, current one marked *.
  zg sync [all|current|<wtree>]     Sync worktrees with the default branch (or specified).
                                     'all' covers every worktree of the repo, wherever
                                     it lives on disk; detached ones are skipped.
  zg rebase                         Rebase the current worktree onto the default branch.
  zg prune metadata                 Prune broken worktree metadata.
  zg prune trees                    Prune worktrees for deleted remote branches, covering
                                     every worktree of the repo, wherever it lives on disk.
                                     Only branches tracking a now-deleted origin branch
                                     (pushed with -u) count; others are kept. Requires an
                                     origin remote.
  zg migrate                        Migrate existing branches to worktrees, skipping branches
                                     already checked out in any worktree.

Meta:
  zg main                           Jump to the main worktree (default branch).
  zg root                           Jump to the project root directory.
  zg help                           Show this help message.
  zg version                        Show Zweig CLI version.

Extensions:
  zg select                         Fuzzy switch to any worktree of the repo, with a git log
                                     preview (requires fzf).
  zg create from-pr <pr-id>         Create worktree pr-<id>-<branch> from GitHub PR (requires gh);
                                     see Worktree Core Lifecycle above.

Commands that move you (switch/cd, main, root, select, create -s, create from-pr)
change your shell's directory only with the shell shim sourced; without it they
print the target path instead:  . "$(zg_helpers_shim_path)"

EOF
}
