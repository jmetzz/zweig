#!/usr/bin/env bash
# Zweig Maintenance Module
# Commands: prune-metadata, remove-merged, remove-deleted-remote, sync, status, migrate
# status, prune trees and sync all sweep every linked worktree git knows about,
# wherever it lives on disk (zg_helpers_list_worktrees), not just ZWEIG_WORKTREE_DIR.
# Requires: bash 4+


# --- Show sync status ---
zg_maintenance_status() {
    zg_helpers_fetch_origin || return 1
    echo "📊 Worktree sync status (vs origin/$ZWEIG_DEFAULT_BRANCH):"
    local entries entry branch dir ahead behind
    mapfile -t entries < <(zg_helpers_list_worktrees)
    for entry in "${entries[@]+"${entries[@]}"}"; do
        branch="${entry%%$'\t'*}" dir="${entry#*$'\t'}"
        [[ -d "$dir" ]] || continue
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

    local entries entry branch dir
    mapfile -t entries < <(zg_helpers_list_worktrees)
    for entry in "${entries[@]+"${entries[@]}"}"; do
        branch="${entry%%$'\t'*}" dir="${entry#*$'\t'}"
        [[ -d "$dir" ]] || continue
        # A detached worktree has no branch to look up on the remote.
        [[ -n "$branch" ]] || continue

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️ Skipping protected: $branch"
            continue
        fi

        if ! git ls-remote --exit-code --heads origin "$branch" &>/dev/null; then
            echo "🔥 Remote branch gone: $branch"
            git worktree remove "$dir" || { echo "❌ Failed to remove worktree dir: $dir"; continue; }
            echo "✅ Worktree removed."

            if ! git branch -d "$branch"; then
                if [[ "$force" == "true" ]]; then
                    echo "⚠️ Forcing delete of local branch '$branch' ..."
                    git branch -D "$branch" || echo "❌ Could not force delete local branch '$branch'."
                else
                    echo "⚠️ Could not delete local branch '$branch' (not fully merged?). Use --force to override."
                fi
            fi
        fi
    done

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

    local failed=0 entries entry branch dir wtree
    mapfile -t entries < <(zg_helpers_list_worktrees)
    for entry in "${entries[@]+"${entries[@]}"}"; do
        branch="${entry%%$'\t'*}" dir="${entry#*$'\t'}"
        [[ -d "$dir" ]] || continue
        wtree="$(zg_maintenance__label "$branch" "$dir")"
        echo "🔁 Rebasing $sync_branch into $wtree..."

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️ Skipping protected: $wtree"
            continue
        fi

        zg_maintenance__sync_dir "$dir" "$wtree" "$sync_branch" || failed=1
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
    local wdir="$1" wtree="$2" sync_branch="$3"
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
