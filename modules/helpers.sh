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

zg_helpers_worktree_exists() {
    [ -d "$ZWEIG_WORKTREE_DIR/$1" ]
}

# --- Resolve a worktree identifier to its path (prints the path) ---
# The identifier is a branch name (canonical identity, see docs/adr/0001).
# Fast path: a directory of that name under ZWEIG_WORKTREE_DIR (no subprocess).
# Fallback: match the branch in `git worktree list --porcelain`, which finds
# worktrees anywhere on disk, including ones other tools created.
# Returns 1 when nothing matches; prints nothing in that case.
zg_helpers_resolve_worktree() {
    local target="$1"
    [[ -n "$target" ]] || return 1

    if [[ -d "$ZWEIG_WORKTREE_DIR/$target" ]]; then
        printf '%s\n' "$ZWEIG_WORKTREE_DIR/$target"
        return 0
    fi

    local worktree_path
    worktree_path="$(git worktree list --porcelain | awk -v b="$target" '
        $1=="worktree" {wt=substr($0, 10)}
        $1=="branch"   {sub("^refs/heads/","",$2); if ($2==b) {print wt; exit}}
    ')"

    [[ -n "$worktree_path" && -d "$worktree_path" ]] || return 1
    printf '%s\n' "$worktree_path"
}

# --- Explain why a worktree identifier did not resolve (stderr) ---
zg_helpers_worktree_not_found() {
    local target="$1"
    echo "❌ Worktree or branch '$target' not found." >&2
    zg_helpers_fetch_origin >/dev/null 2>&1 || true
    if git show-ref --verify --quiet "refs/heads/$target" || \
       git show-ref --verify --quiet "refs/remotes/origin/$target"; then
        echo "ℹ️ Branch '$target' exists without a worktree. Try: zg create from $target" >&2
    fi
}


# Internal helper to check if branch is protected
zg_helpers_is_protected() {
    local wtree="$1"
    # Default branch is always protected
    if [[ "$wtree" == "$ZWEIG_DEFAULT_BRANCH" ]]; then
        return 0
    fi
    # Or explicitly marked with a .protected file
    [[ -f "$ZWEIG_WORKTREE_DIR/$wtree/.protected" ]]
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
  zg remove merged                  Remove worktrees whose branches are merged into the default branch.
  zg (switch|cd) <worktree|branch>  Enter a worktree or switch to one by branch name.
  zg finalize <branch>              Final cleanup after merge (removes worktree and branch).
  zg rebuild <worktree>             Rebuild a worktree (removes and re-adds).
  zg protect <worktree>             Protect a worktree from accidental deletion.
  zg unprotect <worktree>           Remove protection marker from a worktree.

Maintenance:
  zg status                         Show sync status of all worktrees.
  zg sync [all|current|<wtree>]     Sync worktrees with the default branch (or specified).
  zg rebase                         Rebase the current worktree onto the default branch.
  zg prune metadata                 Prune broken worktree metadata.
  zg prune trees                    Prune worktrees for deleted remote branches.
  zg migrate                        Migrate existing branches to worktrees.

Meta:
  zg main                           Jump to the main worktree (default branch).
  zg root                           Jump to the project root directory.
  zg help                           Show this help message.
  zg version                        Show Zweig CLI version.

Extensions:
  zg select                         Fuzzy switch to a worktree (requires fzf).
  zg create from-pr <pr-id>         Create worktree from GitHub PR (requires gh).

EOF
}
