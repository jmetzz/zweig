#!/usr/bin/env bash
# Zweig Maintenance Module
# Commands: prune-metadata, remove-merged, remove-deleted-remote, sync, status, migrate
# Requires: bash 4+


# --- Show sync status ---
zg_maintenance_status() {
    zg_helpers_fetch_origin || return 1
    echo "📊 Worktree sync status (vs origin/$ZWEIG_DEFAULT_BRANCH):"
    shopt -s nullglob
    for dir in "$ZWEIG_WORKTREE_DIR"/*; do
        wtree="$(basename "$dir")"
        ahead=$(git -C "$dir" rev-list --count origin/"$ZWEIG_DEFAULT_BRANCH"..HEAD 2>/dev/null || echo 0)
        behind=$(git -C "$dir" rev-list --count HEAD..origin/"$ZWEIG_DEFAULT_BRANCH" 2>/dev/null || echo 0)
        echo "- $wtree: ↑$ahead ↓$behind"
    done
    shopt -u nullglob
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

    shopt -s nullglob
    for dir in "$ZWEIG_WORKTREE_DIR"/*; do
        wtree="$(basename "$dir")"

        if zg_helpers_is_protected "$wtree"; then
            echo "🛡️ Skipping protected: $wtree"
            continue
        fi

        if ! git ls-remote --exit-code --heads origin "$wtree" &>/dev/null; then
            echo "🔥 Remote branch gone: $wtree"
            git worktree remove "$dir" || { echo "❌ Failed to remove worktree dir: $dir"; continue; }
            echo "✅ Worktree removed."

            if ! git branch -d "$wtree"; then
                if [[ "$force" == "true" ]]; then
                    echo "⚠️ Forcing delete of local branch '$wtree' ..."
                    git branch -D "$wtree" || echo "❌ Could not force delete local branch '$wtree'."
                else
                    echo "⚠️ Could not delete local branch '$wtree' (not fully merged?). Use --force to override."
                fi
            fi
        fi
    done
    shopt -u nullglob

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

    local failed=0
    shopt -s nullglob
    for dir in "$ZWEIG_WORKTREE_DIR"/*; do
        wtree="$(basename "$dir")"
        echo "🔁 Rebasing $sync_branch into $wtree..."

        if zg_helpers_is_protected "$wtree"; then
            echo "🛡️ Skipping protected: $wtree"
            continue
        fi

        zg_maintenance_sync_tree "$wtree" "$sync_branch" || failed=1
    done
    shopt -u nullglob

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
    if ! zg_helpers_worktree_exists "$wtree"; then
        echo "❌ Error: Worktree '$wtree' not found."
        return 1
    fi

    local wdir="$ZWEIG_WORKTREE_DIR/$wtree"
    # guard: dirty worktree
    if ! git -C "$wdir" diff --quiet --ignore-submodules --; then
        echo "⚠️ Worktree '$wtree' has uncommitted changes. Commit/stash before syncing." >&2
        return 2
    fi

    echo "🔁 Rebasing '$wtree' onto origin/$sync_branch ..."
    if git -C "$wdir" rebase "origin/$sync_branch"; then
        echo "✅ $wtree is up to date with origin/$sync_branch."
        return 0
    else
        echo "❌ Rebase failed for '$wtree'. Resolve in that worktree and run 'git rebase --continue' or '--abort'." >&2
        return 1
    fi
}


# --- Migrate all existing branches into worktrees ---
zg_maintenance_migrate() {
    echo "🚚 Migrating branches to worktrees..."

    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vE "^($ZWEIG_DEFAULT_BRANCH|HEAD)"); do
        dir="$ZWEIG_WORKTREE_DIR/$branch"
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
    if ! zg_helpers_worktree_exists "$wtree"; then
        echo "❌ Worktree '$wtree' not found."; return 1
    fi

    touch "$ZWEIG_WORKTREE_DIR/$wtree/.protected"
    echo "🔐 Protected worktree: $wtree"
}

# --- Remove protection ---
zg_maintenance_unprotect() {
    local wtree="$1"
    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"; return 1
    fi
    if ! zg_helpers_worktree_exists "$wtree"; then
        echo "❌ Worktree '$wtree' not found."; return 1
    fi
    rm -f "$ZWEIG_WORKTREE_DIR/$wtree/.protected"
    echo "🔓 Unprotected worktree: $wtree"
}
