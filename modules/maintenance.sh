#!/usr/bin/env bash
# Zweig Maintenance Module
# Commands: status, prune (metadata|trees), sync, migrate, protect, unprotect
# Functions named zg_maintenance__<name> (double underscore) are internal
# helpers, not commands.
# Requires: bash 4.3+ (namerefs)


# --- Load the linked worktrees for a bulk sweep into two arrays ---
# Usage: zg_maintenance__load_worktrees <branches-array> <dirs-array>
# Fills the named arrays in parallel, one element per worktree from
# zg_helpers_list_worktrees (branch empty for a detached HEAD). A worktree whose
# directory is missing is left out with a warning on stderr.
# Returns 0, 2 if any worktree was left out, or 1 if git can't list worktrees.
zg_maintenance__load_worktrees() {
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
            echo "⚠️ Skipping $(zg_maintenance__label "$branch" "$dir"): directory missing ($dir). Try: zg prune metadata" >&2
            rc=2
        fi
    done <<<"$listing"
    return "$rc"
}

# --- Show sync status ---
zg_maintenance_status() {
    zg_helpers_fetch_origin || return 1
    echo "📊 Worktree sync status (vs origin/$ZWEIG_DEFAULT_BRANCH):"
    local branches dirs i branch dir ahead behind rc=0
    zg_maintenance__load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    for i in "${!dirs[@]}"; do
        branch="${branches[i]}" dir="${dirs[i]}"
        ahead=$(git -C "$dir" rev-list --count origin/"$ZWEIG_DEFAULT_BRANCH"..HEAD 2>/dev/null || echo 0)
        behind=$(git -C "$dir" rev-list --count HEAD..origin/"$ZWEIG_DEFAULT_BRANCH" 2>/dev/null || echo 0)
        echo "- $(zg_maintenance__label "$branch" "$dir"): ↑$ahead ↓$behind"
    done
}

# --- Name a worktree in output: its branch, or its directory name if detached ---
zg_maintenance__label() {
    local branch="$1" dir="$2"
    if [[ -n "$branch" ]]; then printf '%s\n' "$branch"; else basename "$dir"; fi
}

# --- Remove broken worktree metadata ---
zg_maintenance_prune_metadata() {
    if ! zg_helpers_inside_git_repo; then
        echo "❌ Error: Not inside a Git repository."
        return 1
    fi

    echo "🔍 Pruning broken worktree metadata..."
    git worktree prune
    echo "✅ Done."
}

# --- Prune worktrees for deleted remote branches ---
zg_maintenance_prune_trees() {
    local force="false"

    # Check for --force flag
    if [[ "${1:-}" == "--force" ]]; then
        force="true"
    fi

    if [[ "$force" == "false" ]]; then
        read -p "Are you sure you want to prune worktrees for deleted remote branches? (y/N): " -n 1 -r
        echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 0
        fi
    fi

    zg_helpers_fetch_origin || return 1
    echo "🔍 Checking for deleted remote branches..."

    local branches dirs i branch dir failed=0 rc=0
    # A worktree with a missing directory is only warned about here: it isn't a
    # prune failure, and `zg prune metadata` cleans it up.
    zg_maintenance__load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    for i in "${!dirs[@]}"; do
        branch="${branches[i]}" dir="${dirs[i]}"
        # A detached worktree has no branch to look up on the remote.
        [[ -n "$branch" ]] || continue

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️ Skipping protected: $branch"
            continue
        fi

        if ! git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
            echo "🔥 Remote branch gone: $branch"
            if ! git worktree remove "$dir"; then
                echo "❌ Failed to remove worktree dir: $dir" >&2
                failed=1
                continue
            fi
            echo "✅ Worktree removed."

            if ! git branch -d "$branch"; then
                if [[ "$force" == "true" ]]; then
                    echo "⚠️ Forcing delete of local branch '$branch' ..."
                    if ! git branch -D "$branch"; then
                        echo "❌ Could not force delete local branch '$branch'." >&2
                        failed=1
                    fi
                else
                    echo "⚠️ Could not delete local branch '$branch' (not fully merged?). Use --force to override."
                fi
            fi
        fi
    done

    if [[ $failed -ne 0 ]]; then
        echo "⚠️ Some worktrees could not be pruned. See messages above." >&2
        return 1
    fi
    echo "✅ Cleanup complete."
}

# --- Sync worktrees ---
zg_maintenance_sync() {
    # Positional-only selector:
    #   zg sync all
    #   zg sync current
    #   zg sync <worktree>
    #   zg sync               # defaults to $ZWEIG_DEFAULT_SYNC_SCOPE


    local sub_command
    if [[ $# -gt 0 ]]; then
        sub_command="$1"; shift || true
    else
        sub_command="${ZWEIG_DEFAULT_SYNC_SCOPE:-current}"
    fi

    zg_helpers_fetch_origin || return 1

    case "$sub_command" in
        all)
            zg_maintenance_sync_all "$@" ;;
        current)
            zg_maintenance_sync_current "$@" ;;
        *)
            # Assume it's a worktree name
            zg_maintenance_sync_tree "$sub_command" "$@" ;;
    esac
}

# --- Sync all worktrees ---
zg_maintenance_sync_all() {
    local sync_branch="${1:-$ZWEIG_DEFAULT_BRANCH}"

    echo "🔄 Syncing all worktrees with origin/$sync_branch..."

    local branches dirs i branch dir label failed=0 rc=0
    # A worktree with a missing directory wasn't synced, so it counts as a failure.
    zg_maintenance__load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    [[ $rc -ne 2 ]] || failed=1
    for i in "${!dirs[@]}"; do
        branch="${branches[i]}" dir="${dirs[i]}"
        label="$(zg_maintenance__label "$branch" "$dir")"

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️ Skipping protected: $label"
            continue
        fi
        # Rebasing a detached HEAD would silently move a checkout some other
        # tool parked there; leave it alone.
        if [[ -z "$branch" ]]; then
            echo "⏭️ Skipping detached worktree: $label ($dir)"
            continue
        fi

        zg_maintenance__sync_dir "$dir" "$label" "$sync_branch" || failed=1
    done

    if [[ $failed -eq 0 ]]; then
        echo "✅ All syncs succeeded."
        return 0
    else
        echo "⚠️ Some worktrees failed to sync. See messages above." >&2
        return 1
    fi
}

# --- Sync the current worktree ---
zg_maintenance_sync_current() {
    local sync_branch="${1:-$ZWEIG_DEFAULT_BRANCH}"
    local current_wtree
    current_wtree=$(basename "$(git rev-parse --show-toplevel)")

    echo "🔄 Syncing current worktree ($current_wtree) with origin/$sync_branch..."
    local rc
    zg_maintenance_sync_tree "$current_wtree" "$sync_branch"
    rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "✅ Current worktree sync complete."
    else
        echo "⚠️ Current worktree sync did not complete cleanly. See messages above." >&2
        return $rc
    fi
}

# --- Sync a specific worktree ---
zg_maintenance_sync_tree() {
    local wtree="$1"
    local sync_branch="${2:-$ZWEIG_DEFAULT_BRANCH}"

    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name for sync."
        return 1
    fi
    local wdir
    if ! wdir="$(zg_helpers_resolve_worktree "$wtree")"; then
        zg_helpers_report_worktree_not_found "$wtree"; return 1
    fi

    zg_maintenance__sync_dir "$wdir" "$wtree" "$sync_branch"
}

# --- Rebase the worktree at a directory onto origin/<sync branch> ---
# The label only names the worktree in messages.
zg_maintenance__sync_dir() {
    local wdir="$1" label="$2" sync_branch="$3"
    # guard: dirty worktree
    if ! git -C "$wdir" diff --quiet --ignore-submodules --; then
        echo "⚠️ Worktree '$label' has uncommitted changes. Commit/stash before syncing." >&2
        return 2
    fi

    echo "🔁 Rebasing '$label' onto origin/$sync_branch ..."
    if git -C "$wdir" rebase "origin/$sync_branch"; then
        echo "✅ $label is up to date with origin/$sync_branch."
        return 0
    else
        echo "❌ Rebase failed for '$label'. Resolve in that worktree and run 'git rebase --continue' or '--abort'." >&2
        return 1
    fi
}


# --- Migrate all existing branches into worktrees ---
# Branch names are flattened (/ -> __) for the worktree directory name, so a
# branch like "feature/foo" lands at "$ZWEIG_WORKTREE_DIR/feature__foo" rather
# than creating a nested "feature/foo" directory.
zg_maintenance_migrate() {
    echo "🚚 Migrating branches to worktrees..."

    local branch dir_name dir
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vE "^($ZWEIG_DEFAULT_BRANCH|HEAD)"); do
        dir_name="${branch//\//__}"
        dir="$ZWEIG_WORKTREE_DIR/$dir_name"
        if [[ -d "$dir" ]]; then
            echo "⏭️ Already exists: $branch"
        else
            echo "➡️ Adding $branch to worktree..."
            git worktree add "$dir" "$branch"
        fi
    done

    echo "✅ Migration complete."
}


# --- Protect a worktree (prevent accidental delete) ---
zg_maintenance_protect() {
    local wtree="$1"
    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"
        return 1
    fi
    local dir
    if ! dir="$(zg_helpers_resolve_worktree "$wtree")"; then
        zg_helpers_report_worktree_not_found "$wtree"; return 1
    fi

    touch "$dir/.protected"
    echo "🔐 Protected worktree: $wtree"
}

# --- Remove protection ---
zg_maintenance_unprotect() {
    local wtree="$1"
    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"; return 1
    fi
    local dir
    if ! dir="$(zg_helpers_resolve_worktree "$wtree")"; then
        zg_helpers_report_worktree_not_found "$wtree"; return 1
    fi
    rm -f "$dir/.protected"
    echo "🔓 Unprotected worktree: $wtree"
}
