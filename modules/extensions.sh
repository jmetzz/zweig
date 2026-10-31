#!/usr/bin/env bash
# Zweig Extensions Module - extensions.sh
# Optional helpers and interactive commands
# Requires: bash 4+, fzf (if used)


# --- Interactive selector (fzf required) ---
zg_extensions_select() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "❌ Error: fzf is not installed"
        return 1
    fi

    if [[ ! -d "$ZWEIG_WORKTREE_DIR" ]]; then
        echo "❌ No worktrees found in $ZWEIG_WORKTREE_DIR" >&2
        return 1
    fi

    local selected
    selected=$(find "$ZWEIG_WORKTREE_DIR" -maxdepth 1 -mindepth 1 -type d | sed "s|$ZWEIG_WORKTREE_DIR/||" | fzf)
    if [[ -n "$selected" ]]; then
        zg_core_switch "$selected"
    fi
}

# --- From GitHub PR (requires gh CLI; loader enforces preconditions) ---
zg_extensions_from_pr() {
    local pr_id="${1:-}"
    if [[ -z "$pr_id" ]]; then
        echo "❌ Error: Missing PR ID"
        return 1
    fi

    # If a worktree named after the PR ID already exists, just switch to it
    if zg_helpers_worktree_exists "$pr_id"; then
        echo "ℹ️ Worktree for PR #$pr_id already exists. Switching to it…"
        zg_core_switch "$pr_id"
        return 0
    fi

    # Resolve the PR head branch
    local branch
    branch="$(gh pr view "$pr_id" --json headRefName -q .headRefName 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
        echo "❌ Error: Could not resolve head branch for PR #$pr_id (not found or no access)." >&2
        return 1
    fi

    # Refresh remote refs (shared helper)
    zg_helpers_fetch_origin || return 1

    # Require that the head branch exists on origin (fork PRs are out-of-scope)
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        echo "❌ Error: Remote branch 'origin/$branch' not found (fork PRs not supported)." >&2
        return 1
    fi

    # Ensure a local branch exists (track origin/<branch> if missing)
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        # Create a tracking branch; fall back to plain branch if tracking creation fails
        git branch --track "$branch" "origin/$branch" 2>/dev/null || git branch "$branch" "origin/$branch" || {
            echo "❌ Error: Could not create local branch '$branch' from origin." >&2
            return 1
        }
    fi

    # Create the worktree named after the PR ID and switch to it
    if ! git worktree add "$ZWEIG_WORKTREE_DIR/$pr_id" "$branch"; then
        echo "❌ Error: Failed to add worktree for PR #$pr_id (branch: $branch)." >&2
        return 1
    fi

    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"
    zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$pr_id" "$root_dir"

    echo "✅ Worktree created from PR #$pr_id ($branch)"
    zg_core_switch "$pr_id"
}
