#!/usr/bin/env bash
# Zweig Maintenance Module
# Commands: status, prune (metadata|trees), sync, migrate, protect, unprotect
# Functions named zg_maintenance__<name> (double underscore) are internal
# helpers, not commands.
# Requires: bash 4.3+ (namerefs, via the zg_helpers_load_* loaders and
# zg_helpers_report_mark)

# --- Show sync status ---
# One aligned row per worktree (main checkout first): name, commits ahead of and
# behind origin/<default>, the current worktree marked *.
zg_maintenance_status() {
    zg_helpers_fetch_origin || return 1
    echo "📊 Worktree sync status (vs origin/$ZWEIG_DEFAULT_BRANCH):"
    # Filled as arrays (and an index) by the loader, through namerefs. Status
    # has no HEAD column, but the loader fills heads regardless.
    # shellcheck disable=SC2034
    local names dirs heads current i rc=0
    # A missing directory (rc 2) is only warned about: status is a read-only report.
    zg_helpers_load_report_worktrees names dirs heads current || rc=$?
    [[ $rc -ne 1 ]] || return 1
    zg_helpers_colors

    # "?" rather than 0 when git can't count (e.g. no origin/<default>): a
    # made-up 0 would read as "in sync". Those rows are named on stderr.
    local mark colour aheads=() behinds=() uncounted=() name_w=0 ahead_w=0
    # ${#dirs[@]}, not "${!dirs[@]}": the latter trips set -u on an empty array before bash 4.4.
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        aheads+=("$(git -C "${dirs[i]}" rev-list --count "origin/$ZWEIG_DEFAULT_BRANCH..HEAD" 2>/dev/null || echo "?")")
        behinds+=("$(git -C "${dirs[i]}" rev-list --count "HEAD..origin/$ZWEIG_DEFAULT_BRANCH" 2>/dev/null || echo "?")")
        if [[ "${aheads[i]}" == "?" || "${behinds[i]}" == "?" ]]; then uncounted+=("${names[i]}"); fi
        # Columns grow to fit the widest name and ahead count.
        if ((${#names[i]} > name_w)); then name_w=${#names[i]}; fi
        if ((${#aheads[i]} > ahead_w)); then ahead_w=${#aheads[i]}; fi
    done
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        zg_helpers_report_mark mark colour "$((i == current))"
        printf '%s%s%-*s%s  ↑%-*s ↓%s\n' "$mark" "$colour" "$name_w" "${names[i]}" "$ZG_C_RESET" \
            "$ahead_w" "${aheads[i]}" "${behinds[i]}"
    done
    if ((${#uncounted[@]} > 0)); then
        local joined
        joined="$(printf '%s, ' "${uncounted[@]}")"
        echo "⚠️ Could not count ahead/behind for: ${joined%, } (does origin/$ZWEIG_DEFAULT_BRANCH exist?)" >&2
    fi
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

# True when the branch's upstream is on origin and git reports it `[gone]`.
# Only meaningful after `git fetch --prune` (prune trees runs
# zg_helpers_fetch_origin first). A branch is not gone when:
#   - it has no upstream (never pushed, or pushed without -u);
#   - its upstream is a local branch or on another remote;
#   - its upstream is on origin, but origin's fetch refspec doesn't cover it, so
#     there's no remote-tracking ref for git to report gone.
zg_maintenance__upstream_gone() {
    local branch="$1"
    # The format prints "<remote> <track>", e.g. "origin [gone]".
    [[ "$(git for-each-ref --format='%(upstream:remotename) %(upstream:track)' "refs/heads/$branch")" == "origin [gone]" ]]
}

# --- Prune worktrees for deleted remote branches ---
zg_maintenance_prune_trees() {
    local force="false" arg

    for arg in "$@"; do
        if [[ "$arg" == "--force" && "$force" == "false" ]]; then
            force="true"
        else
            echo "❌ Error: Unknown argument: $arg (usage: zg prune trees [--force])" >&2
            return 1
        fi
    done

    # Without origin no upstream can be reported gone, so nothing could be told
    # apart from a branch that was never pushed.
    # Checked before the prompt, so we never ask to confirm a refusal.
    if ! zg_helpers_has_origin; then
        echo "❌ Error: No 'origin' remote configured; can't tell which remote branches are gone." >&2
        return 1
    fi

    if [[ "$force" == "false" ]]; then
        # Safe prompt under set -e
        if ! read -p "Are you sure you want to prune worktrees for deleted remote branches? (y/N): " -n 1 -r; then
            echo
            echo "Operation cancelled."
            return 1
        fi
        echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 1
        fi
    fi

    zg_helpers_fetch_origin || return 1
    echo "🔍 Checking for deleted remote branches..."

    local branches dirs i branch dir failed=0 pruned=0 rc=0
    # A worktree with a missing directory is only warned about here: it isn't a
    # prune failure, and `zg prune metadata` cleans it up.
    zg_helpers_load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        branch="${branches[i]}" dir="${dirs[i]}"
        # A detached worktree has no branch, so no upstream to check.
        [[ -n "$branch" ]] || continue

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️ Skipping protected: $branch"
            continue
        fi

        if zg_maintenance__upstream_gone "$branch"; then
            echo "🔥 Remote branch gone: $branch"
            if ! git worktree remove "$dir"; then
                echo "❌ Failed to remove worktree dir: $dir" >&2
                failed=1
                continue
            fi
            pruned=$((pruned + 1))
            echo "✅ Worktree removed."

            if ! git branch -d "$branch"; then
                if [[ "$force" == "true" ]]; then
                    echo "⚠️ Forcing delete of local branch '$branch' ..."
                    if ! git branch -D "$branch"; then
                        echo "❌ Could not force delete local branch '$branch'." >&2
                        failed=1
                    fi
                else
                    echo "⚠️ Could not delete local branch '$branch' (not fully merged?). Use --force to override." >&2
                    failed=1
                fi
            fi
        fi
    done

    if [[ $failed -ne 0 ]]; then
        echo "⚠️ Some worktrees could not be pruned. See messages above." >&2
        return 1
    fi
    if ((pruned == 0)); then
        echo "ℹ️ No worktrees pruned."
        return 0
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
    zg_helpers_load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    [[ $rc -ne 2 ]] || failed=1
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        branch="${branches[i]}" dir="${dirs[i]}"
        label="$(zg_helpers_worktree_short_label "$branch" "$dir")"

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
# Works on the current worktree's own path, wherever it lives on disk.
zg_maintenance_sync_current() {
    local sync_branch="${1:-$ZWEIG_DEFAULT_BRANCH}"
    local wdir branch label
    wdir="$(git rev-parse --show-toplevel)" || return 1
    branch="$(zg_helpers_worktree_branch "$wdir")" || return 1
    label="$(zg_helpers_worktree_short_label "$branch" "$wdir")"
    # Same rules as sync all: never move a detached HEAD, and leave protected
    # worktrees (including the default branch's) alone.
    if [[ -z "$branch" ]]; then
        echo "❌ Current worktree ($label) has a detached HEAD; nothing to sync." >&2
        return 1
    fi
    if zg_helpers_dir_is_protected "$branch" "$wdir"; then
        echo "🛡️ Current worktree ($label) is protected; not syncing." >&2
        return 1
    fi

    echo "🔄 Syncing current worktree ($label) with origin/$sync_branch..."
    local rc=0
    zg_maintenance__sync_dir "$wdir" "$label" "$sync_branch" || rc=$?
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

    # Every branch already checked out (main checkout included): git refuses to
    # check a branch out twice, wherever the other worktree is. Read once.
    local -A held=()
    # held_head is filled by the split but not needed here.
    # shellcheck disable=SC2034
    local listing line held_branch held_head held_path
    if ! listing="$(zg_helpers_list_worktrees --all)"; then
        echo "❌ Error: Could not list worktrees." >&2
        return 1
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        zg_helpers_split_worktree_line "$line" held_branch held_head held_path
        # An empty branch is a detached worktree: nothing held.
        if [[ -n "$held_branch" ]]; then held["$held_branch"]="$held_path"; fi
    done <<<"$listing"

    local branch dir_name dir
    for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -vxE "($ZWEIG_DEFAULT_BRANCH|HEAD)"); do
        dir_name="${branch//\//__}"
        dir="$ZWEIG_WORKTREE_DIR/$dir_name"
        if [[ -n "${held[$branch]+set}" ]]; then
            echo "⏭️ Already checked out: $branch (${held[$branch]})"
        elif [[ -d "$dir" ]]; then
            echo "⏭️ Directory already exists, not migrating $branch: $dir"
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
