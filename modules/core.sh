#!/usr/bin/env bash
# Zweig Core Module - core.sh
# Provides essential commands for worktree lifecycle: create, from, remove, switch, list
# Requires: bash 4+


# --- Jump to the main worktree (default branch) ---
zg_core_main() {
    echo "Attempting to switch to main worktree: $ZWEIG_DEFAULT_BRANCH"
    zg_core_switch "$ZWEIG_DEFAULT_BRANCH"
}

# --- Navigate back to project root ---
# Resolves the control repo root, not just the current worktree's own top level,
# so this works correctly even when called from inside a linked worktree.
zg_core_root() {
    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"
    cd "$root_dir" || return
    echo "📂 Switched to project root: $root_dir"
}

# --- List all worktrees ---
zg_core_list() {
    git worktree list --porcelain | awk '
      $1=="worktree"{wt=$2}
      $1=="branch"{gsub("^refs/heads/","",$2); printf "- %s  (%s)\n", wt, $2}
    '
}

# --- Create new branch and worktree from default branch (robust base selection) ---
zg_core_create() {
  local wtree="$1"

  # Validate input
  [[ -n "$wtree" ]] || { echo "❌ Missing branch/worktree name."; return 1; }
  git check-ref-format --branch "$wtree" >/dev/null 2>&1 || { echo "❌ Invalid branch name: $wtree"; return 1; }

  zg_helpers_is_protected "$wtree" && { echo "❌ Name is protected: $wtree"; return 1; }
  zg_helpers_worktree_exists "$wtree" && { echo "❌ Worktree '$wtree' already exists."; return 1; }

  # Try to refresh remotes (no-op if no origin)
  zg_helpers_fetch_origin || return 1

  local root_dir
  root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"

  # Decide base: prefer origin/<default>, then local <default>, else current HEAD
  local base=""
  if git show-ref --verify --quiet "refs/remotes/origin/$ZWEIG_DEFAULT_BRANCH"; then
    base="origin/$ZWEIG_DEFAULT_BRANCH"
  elif git show-ref --verify --quiet "refs/heads/$ZWEIG_DEFAULT_BRANCH"; then
    base="$ZWEIG_DEFAULT_BRANCH"
  else
    base=""  # use current HEAD implicitly
  fi

  # Create worktree and new branch from decided base
  if [[ -n "$base" ]]; then
    if git worktree add "$ZWEIG_WORKTREE_DIR/$wtree" -b "$wtree" "$base"; then
      zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$wtree" "$root_dir"
      echo "🌱 Created new branch + worktree: $wtree (from $base)"
      return 0
    fi
  else
    if git worktree add "$ZWEIG_WORKTREE_DIR/$wtree" -b "$wtree"; then
      zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$wtree" "$root_dir"
      echo "🌱 Created new branch + worktree: $wtree (from HEAD)"
      return 0
    fi
  fi

  # Friendly guidance if Git rejected (e.g., branch already exists)
  if git show-ref --verify --quiet "refs/heads/$wtree"; then
    echo "⚠️ Local branch '$wtree' already exists. Use: zg create from $wtree"
  elif git show-ref --verify --quiet "refs/remotes/origin/$wtree"; then
    echo "⚠️ Remote branch 'origin/$wtree' already exists. Use: zg create from $wtree"
  else
    if [[ -n "$base" ]]; then
      echo "❌ Failed to create worktree '$wtree' from $base."
    else
      echo "❌ Failed to create worktree '$wtree' from HEAD."
    fi
  fi
  return 1
}

# --- Create worktree from existing branch ---
zg_core_create_from() {
    local branch="$1"

    if [[ -z "$branch" ]]; then
        echo "❌ Error: Missing branch name"
        return 1
    fi

    if zg_helpers_is_protected "$branch"; then
        echo "❌ Error: Branch '$branch' is protected."
        return 1
    fi

    if zg_helpers_worktree_exists "$branch"; then
        echo "❌ Error: Worktree directory for '$branch' already exists."
        return 1
    fi

    # Refresh remote refs consistently
    zg_helpers_fetch_origin || return 1

    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"

    if git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "🌿 Creating worktree from local branch: $branch"
        git worktree add "$ZWEIG_WORKTREE_DIR/$branch" "$branch" || {
            echo "❌ Error: Failed to add worktree for local branch '$branch'." >&2
            return 1
        }
        zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$branch" "$root_dir"
        echo "✅ Created worktree for branch: $branch"
        return 0
    fi

    if git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        echo "🌿 Creating local tracking branch from origin/$branch and adding worktree..."
        # Create a local branch tracking origin/<branch> (idempotent if it already exists)
        git branch --track "$branch" "origin/$branch" 2>/dev/null || git branch "$branch" "origin/$branch" || {
            echo "❌ Error: Could not create local branch '$branch' from origin/$branch." >&2
            return 1
        }
        git worktree add "$ZWEIG_WORKTREE_DIR/$branch" "$branch" || {
            echo "❌ Error: Failed to add worktree for '$branch'." >&2
            return 1
        }
        zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$branch" "$root_dir"
        echo "✅ Created worktree for branch: $branch"
        return 0
    fi

    echo "❌ Error: Branch '$branch' not found locally or on origin."
    return 1
}


# --- Switch to worktree ---
zg_core_switch() {
    local target="$1"

    if [[ -z "$target" ]]; then
        echo "❌ Error: Missing worktree or branch name"
        return 1
    fi

    local dir="$ZWEIG_WORKTREE_DIR/$target"

    # Fast path: switch by worktree directory name
    if [[ -d "$dir" ]]; then
        cd "$dir" || return
        echo "📂 Switched to worktree: $target"
        return 0
    fi

    # Fallback: resolve by branch name using porcelain (worktree -> next branch)
    local worktree_path
    worktree_path="$(git worktree list --porcelain | awk -v b="$target" '
        $1=="worktree" {wt=$2}
        $1=="branch"   {gsub("^refs/heads/","",$2); if ($2==b) {print wt; exit}}
    ')"

    if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
        cd "$worktree_path" || return
        echo "📂 Switched to worktree for branch: $target"
        echo "   Path: $worktree_path"
        return 0
    fi

    # Not found: provide a helpful hint if the branch exists without a worktree
    echo "❌ Worktree or branch '$target' not found."
    zg_helpers_fetch_origin || true
    if git show-ref --verify --quiet "refs/heads/$target" || \
        git show-ref --verify --quiet "refs/remotes/origin/$target"; then
        echo "ℹ️ Branch '$target' exists without a worktree. Try: zg create from $target"
    fi
    return 1
}

# Resolve worktree directory from name or branch (prints path)
zg_core_path() {
  local target="$1"
  [[ -n "$target" ]] || { echo "❌ Missing worktree or branch name" >&2; return 2; }

  local dir="$ZWEIG_WORKTREE_DIR/$target"
  if [[ -d "$dir" ]]; then
    printf '%s\n' "$dir"; return 0
  fi

  local worktree_path
  worktree_path="$(git worktree list --porcelain | awk -v b="$target" '
    $1=="worktree" {wt=$2}
    $1=="branch"   {gsub("^refs/heads/","",$2); if ($2==b) {print wt; exit}}
  ')"

  if [[ -n "$worktree_path" && -d "$worktree_path" ]]; then
    printf '%s\n' "$worktree_path"; return 0
  fi

  # Optional hint (freshen remotes quietly)
  zg_helpers_fetch_origin || true
  if git show-ref --verify --quiet "refs/heads/$target" || \
     git show-ref --verify --quiet "refs/remotes/origin/$target"; then
    echo "ℹ️ Branch '$target' exists without a worktree. Try: zg create from $target" >&2
  else
    echo "❌ Worktree or branch '$target' not found." >&2
  fi
  return 1
}

# --- Remove worktree (keep branch) ---
zg_core_remove() {
    local wtree="$1"
    local force="false"

    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"
        return 1
    fi

    # Accept --force in either position (optional; remove this loop if you prefer strict)
    if [[ "${2:-}" == "--force" || "${1:-}" == "--force" ]]; then
        force="true"
        # normalize wtree if user wrote: zg remove --force <wtree>
        if [[ "$1" == "--force" ]]; then
            wtree="${2:-$wtree}"
        fi
    fi

    if [[ "$wtree" == "--force" || -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"
        return 1
    fi

    local dir="$ZWEIG_WORKTREE_DIR/$wtree"
    if [[ ! -d "$dir" ]]; then
        echo "⚠️ Worktree does not exist: $dir"
        return 1
    fi

    # Avoid operating inside the target worktree
    local here; here="$(pwd -P)"
    if [[ "$here" == "$dir"* ]]; then
        echo "❌ You are inside the '$wtree' worktree. Switch away before removing." >&2
        return 1
    fi

    if zg_helpers_is_protected "$wtree" && [[ "$force" == "false" ]]; then
        echo "❌ Error: Worktree '$wtree' is protected. Use --force to override."
        return 1
    fi

    # Warn if dirty when not forced
    if [[ "$force" == "false" ]]; then
        if ! git -C "$dir" diff --quiet --ignore-submodules --; then
            echo "⚠️ Worktree '$wtree' has uncommitted changes. Use --force to override."
        fi
        local gitpath
        gitpath="$(git -C "$dir" rev-parse --git-path .)"
        if [[ -e "$gitpath/MERGE_HEAD" || -e "$gitpath/CHERRY_PICK_HEAD" || -e "$gitpath/REBASE_HEAD" ]]; then
            echo "⚠️ A merge/rebase/cherry-pick is in progress. Use --force to override."
        fi

        # Safe prompt under set -e
        if ! read -p "Remove worktree '$wtree'? (y/N): " -n 1 -r; then
            echo
            echo "Operation cancelled."
            return 1
        fi
        echo
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            return 0
        fi
    fi

    # Remove (pass --force to git if requested)
    if [[ "$force" == "true" ]]; then
        if git worktree remove --force "$dir"; then
            echo "🗑️ Removed worktree (forced): $wtree"
            return 0
        else
            echo "❌ Failed to remove worktree (forced): $wtree" >&2
            return 1
        fi
    else
        if git worktree remove "$dir"; then
            echo "🗑️ Removed worktree: $wtree"
            return 0
        else
            echo "❌ Failed to remove worktree: $wtree" >&2
            return 1
        fi
    fi
}



# --- Remove worktrees whose branches are merged into the default branch ---
zg_core_remove_merged() {
    local force="false"
    [[ "${1:-}" == "--force" ]] && force="true"

    # One confirmation at the start when not forced
    if [[ "$force" == "false" ]]; then
        if ! read -p "Remove ALL merged worktrees? (y/N): " -n 1 -r; then
            echo; echo "Operation cancelled."; return 1
        fi
        echo
        [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Operation cancelled."; return 0; }
    fi

    # Fresh remote info
    zg_helpers_fetch_origin || return 1
    local base="origin/$ZWEIG_DEFAULT_BRANCH"

    local removed=0 skipped=0 failed=0

    echo "🧹 Checking for worktrees merged into $base ..."
    shopt -s nullglob
    for dir in "$ZWEIG_WORKTREE_DIR"/*; do
        local wtree; wtree="$(basename "$dir")"

        if zg_helpers_is_protected "$wtree"; then
            echo "🛡️  Skipping protected: $wtree"; skipped=$((skipped + 1)); continue
        fi

        # Consider only branches that are fully merged into the default branch
        if git merge-base --is-ancestor "refs/heads/$wtree" "$base"; then
            echo "🔥 $wtree is merged into $base. Finalizing..."
            if zg_core_finalize "$wtree" --force; then
                removed=$((removed + 1))
            else
                echo "❌ Failed to finalize $wtree" >&2
                failed=$((failed + 1))
            fi
        else
            skipped=$((skipped + 1))
        fi
    done
    shopt -u nullglob

    echo "✅ remove-merged complete — removed: $removed, skipped: $skipped, failed: $failed"
    [[ $failed -eq 0 ]] || return 1
}


# --- Rebuild worktree (remove then re-add from same branch) ---
# Assumes: worktree directory name == branch name
zg_core_rebuild() {
    local wtree="$1"
    local force="false"

    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"
        return 1
    fi
    [[ ${2:-} == "--force" ]] && force="true"

    local dir="$ZWEIG_WORKTREE_DIR/$wtree"
    if [[ -d "$dir" ]]; then
        # Don’t operate while inside the target worktree
        local here; here="$(pwd -P)"
        if [[ "$here" == "$dir"* ]]; then
            echo "❌ You are inside the '$wtree' worktree. Switch away before rebuilding." >&2
            return 1
        fi
    fi

    # Delegate validations and heavy lifting to existing commands
    if [[ "$force" == "true" ]]; then
        zg_core_remove "$wtree" --force || return $?
    else
        zg_core_remove "$wtree" || return $?
    fi

    zg_core_create_from "$wtree" || return $?

    echo "🔧 Rebuilt worktree: $wtree"
}


# --- Finalize branch after merge ---
zg_core_finalize() {
  local branch="$1"
  local force="false"

  if [[ -z "$branch" ]]; then
    echo "❌ Error: Missing branch name"
    return 1
  fi
  [[ ${2:-} == "--force" ]] && force="true"

  # Protected branches require --force
  if zg_helpers_is_protected "$branch" && [[ "$force" == "false" ]]; then
    echo "❌ '$branch' is protected. Use --force to override." >&2
    return 1
  fi

  # Safe confirmation
  if [[ "$force" == "false" ]]; then
    if ! read -p "Finalize '$branch' (remove worktree & delete local branch)? (y/N): " -n 1 -r; then
      echo; echo "Operation cancelled."; return 1
    fi
    echo
    [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Operation cancelled."; return 0; }
  fi

  local dir="$ZWEIG_WORKTREE_DIR/$branch"

  # Avoid operating inside the target worktree
  if [[ -d "$dir" ]]; then
    local here; here="$(pwd -P)"
    if [[ "$here" == "$dir"* ]]; then
      echo "❌ You are inside the '$branch' worktree. Switch away before finalizing." >&2
      return 1
    fi
  fi

  # Fresh remote info (optional but helpful)
  zg_helpers_fetch_origin || return 1

  # Remove worktree (respect --force)
  if [[ -d "$dir" ]]; then
    if [[ "$force" == "true" ]]; then
      git worktree remove --force "$dir" || { echo "❌ Failed to force-remove worktree: $branch" >&2; return 1; }
    else
      git worktree remove "$dir" || { echo "❌ Failed to remove worktree: $branch" >&2; return 1; }
    fi
  fi

  # Delete local branch if present (will fail if not merged—fine)
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -d "$branch" || {
      echo "⚠️ Branch $branch not deleted (not fully merged?)."
      [[ "$force" == "true" ]] && echo "Hint: use 'git branch -D $branch' to force."
    }
  fi

  echo "✅ Finalized and cleaned up: $branch"
}