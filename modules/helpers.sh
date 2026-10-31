#!/usr/bin/env bash
# Zweig Helpers Module - helpers.sh
# Provides reusable helper functions for the other modules.

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

# Fetch origin safely (used by status/sync/prune). Quiet by default.
zg_helpers_fetch_origin() {
    # Ensure we're inside a Git repository
    git rev-parse --git-dir >/dev/null 2>&1 || {
        echo "❌ Error: Not inside a Git repository." >&2
        return 1
    }

    # If 'origin' is configured, fetch from it; otherwise, skip gracefully
    if git remote get-url origin >/dev/null 2>&1; then
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
# Prints nothing (and returns 1) if the branch isn't checked out in any
# worktree. The path is printed even if that directory no longer exists.
zg_helpers_branch_worktree_path() {
    local branch="$1" wt_path
    # substr($0, 10), not $2: worktree paths may contain spaces, and
    # 10 = length("worktree ") + 1.
    wt_path="$(git worktree list --porcelain | awk -v b="$branch" '
        $1=="worktree" {wt=substr($0, 10)}
        $1=="branch"   {sub("^refs/heads/","",$2); if ($2==b) {print wt; exit}}
    ')"
    [[ -n "$wt_path" ]] || return 1
    printf '%s\n' "$wt_path"
}

# --- List every linked worktree of the repo, wherever it lives on disk ---
# Prints one "<branch>\t<path>" line per worktree, skipping the main worktree
# (always the first porcelain record, wherever it's run from) and bare entries.
# The branch is empty for a detached HEAD. Paths are printed even if the
# directory no longer exists. Returns 1 if git can't list worktrees.
#
# Refs can't contain a tab, so callers split on the first one:
# branch="${line%%$'\t'*}" path="${line#*$'\t'}". Not `IFS=$'\t' read`: tab is
# IFS whitespace, so read would drop an empty (detached) branch field.
zg_helpers_list_worktrees() {
    local porcelain
    porcelain="$(git worktree list --porcelain)" || return 1
    # substr($0, 10): see zg_helpers_branch_worktree_path.
    # n counts records; record 1 is the main worktree, so only n > 1 is printed.
    awk '
        function flush() { if (n > 1 && wt != "" && !bare) printf "%s\t%s\n", br, wt }
        $1=="worktree" {flush(); n++; wt=substr($0, 10); br=""; bare=0}
        $1=="branch"   {br=$2; sub("^refs/heads/","",br)}
        $1=="bare"     {bare=1}
        END            {flush()}
    ' <<<"$porcelain"
}

# --- Load the linked worktrees for a bulk sweep into two arrays ---
# Usage: zg_helpers_load_worktrees <branches-array> <dirs-array>
# Fills the named arrays in parallel, one element per worktree from
# zg_helpers_list_worktrees (branch empty for a detached HEAD). A worktree whose
# directory is missing is left out with a warning on stderr.
# Returns 0, 2 if any worktree was left out, or 1 if git can't list worktrees.
zg_helpers_load_worktrees() {
    local -n _zg_branches="$1" _zg_dirs="$2"
    local listing line branch dir rc=0
    _zg_branches=() _zg_dirs=()
    if ! listing="$(zg_helpers_list_worktrees)"; then
        echo "❌ Error: Could not list worktrees." >&2
        return 1
    fi
    [[ -n "$listing" ]] || return 0
    while IFS= read -r line; do
        # Split on the first tab; see zg_helpers_list_worktrees for why not `read`.
        branch="${line%%$'\t'*}" dir="${line#*$'\t'}"
        if [[ -d "$dir" ]]; then
            _zg_branches+=("$branch") _zg_dirs+=("$dir")
        else
            echo "⚠️ Skipping $(zg_helpers_worktree_label "$branch" "$dir"): directory missing ($dir). Try: zg prune metadata" >&2
            rc=2
        fi
    done <<<"$listing"
    return "$rc"
}

# --- Name a worktree in output: its branch, or its directory name if detached ---
zg_helpers_worktree_label() {
    local branch="$1" dir="$2"
    if [[ -n "$branch" ]]; then printf '%s\n' "$branch"; else basename "$dir"; fi
}

# --- Fail if a branch is already checked out in any worktree ---
# git refuses to check a branch out twice; this names the worktree holding it
# (wherever it lives) instead of surfacing git's raw error. Returns 1 if taken.
zg_helpers_ensure_branch_free() {
    local branch="$1" wt_path
    wt_path="$(zg_helpers_branch_worktree_path "$branch")" || return 0
    echo "❌ Branch '$branch' is already checked out at $wt_path. Try: zg switch $branch" >&2
    return 1
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
    local target="$1" registered
    echo "❌ Worktree or branch '$target' not found." >&2
    if registered="$(zg_helpers_branch_worktree_path "$target")"; then
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
  zg list                           List all worktrees.
  zg create <worktree name>         Create a new worktree (and local branch) from the default branch.
  zg create from <branch>           Create a worktree from an existing branch.
  zg create from-pr <pr-id>         Create worktree from GitHub PR (requires gh).
  zg create ... -s                  Add -s to any create form to switch into it immediately
                                     (requires the shell shim; see shims/shims.sh).
  zg (remove|rm) <worktree>         Remove a worktree but keeps the branch.
  zg remove merged                  Remove worktrees whose branches are merged into the default branch,
                                     wherever they live on disk; detached ones are skipped.
  zg (switch|cd) <worktree|branch>  Enter a worktree or switch to one by branch name.
                                     Finds worktrees anywhere on disk; detached ones
                                     only by their directory name under the worktree dir.
  zg finalize <branch>              Final cleanup after merge (removes worktree and branch).
  zg rebuild <worktree>             Rebuild a worktree (removes and re-adds).
  zg protect <worktree>             Protect a worktree from accidental deletion.
  zg unprotect <worktree>           Remove protection marker from a worktree.

Maintenance:
  zg status                         Show sync status of every worktree of the repo,
                                     wherever it lives on disk.
  zg sync [all|current|<wtree>]     Sync worktrees with the default branch (or specified).
                                     'all' covers every worktree of the repo, wherever
                                     it lives on disk; detached ones are skipped.
  zg rebase                         Rebase the current worktree onto the default branch.
  zg prune metadata                 Prune broken worktree metadata.
  zg prune trees                    Prune worktrees for deleted remote branches, covering
                                     every worktree of the repo, wherever it lives on disk.
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
  zg create from-pr <pr-id>         Create worktree from GitHub PR (requires gh).

EOF
}
