#!/usr/bin/env bash
# Zweig Core Module - core.sh
# Provides essential commands for worktree lifecycle: create, from, remove, switch, list
# Requires: bash 4.3+ (namerefs, via the zg_helpers_load_* loaders and
# zg_helpers_report_mark)


# --- Jump to the main worktree (default branch) ---
zg_core_main() {
    zg_core_switch "$ZWEIG_DEFAULT_BRANCH"
}

# --- Navigate back to project root ---
# Resolves the control repo root, not just the current worktree's own top level,
# so this works correctly even when called from inside a linked worktree.
zg_core_root() {
    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"
    zg_helpers_request_cd "$root_dir" "project root"
}

# --- List all worktrees ---
# Names only by default; -d/--detail adds an aligned PATH and HEAD table.
zg_core_list() {
    local detail=0
    if (($# == 1)) && [[ "$1" == -d || "$1" == --detail ]]; then
        detail=1
    elif (($# > 0)); then
        echo "❌ Usage: zg list [-d|--detail]" >&2
        return 1
    fi

    # Filled as arrays (and an index) by the loader, through namerefs.
    local names dirs heads current rc=0
    zg_helpers_load_report_worktrees names dirs heads current || rc=$?
    [[ $rc -ne 1 ]] || return 1
    zg_helpers_colors

    local i mark colour
    if ((detail == 0)); then
        for ((i = 0; i < ${#dirs[@]}; i++)); do
            zg_helpers_report_mark mark colour "$((i == current))"
            printf '%s%s%s%s\n' "$mark" "$colour" "${names[i]}" "$ZG_C_RESET"
        done
        return 0
    fi

    # Columns start as wide as their headers ("NAME", "PATH") and grow to fit.
    local name_w=4 path_w=4
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        if ((${#names[i]} > name_w)); then name_w=${#names[i]}; fi
        if ((${#dirs[i]} > path_w)); then path_w=${#dirs[i]}; fi
    done
    printf '  %-*s  %-*s  %s\n' "$name_w" NAME "$path_w" PATH HEAD
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        zg_helpers_report_mark mark colour "$((i == current))"
        printf '%s%s%-*s%s  %s%-*s%s  %s%s%s\n' \
            "$mark" "$colour" "$name_w" "${names[i]}" "$ZG_C_RESET" \
            "$ZG_C_PATH" "$path_w" "${dirs[i]}" "$ZG_C_RESET" \
            "$ZG_C_HASH" "${heads[i]}" "$ZG_C_RESET"
    done
}

# --- Create new branch and worktree from default branch (robust base selection) ---
zg_core_create() {
  local wtree="$1"

  # Validate input
  [[ -n "$wtree" ]] || { echo "❌ Missing branch/worktree name."; return 1; }
  git check-ref-format --branch "$wtree" >/dev/null 2>&1 || { echo "❌ Invalid branch name: $wtree"; return 1; }

  zg_helpers_is_protected "$wtree" && { echo "❌ Name is protected: $wtree" >&2; return 1; }
  zg_helpers_worktree_exists "$wtree" && { echo "❌ Worktree '$wtree' already exists." >&2; return 1; }
  zg_helpers_ensure_branch_free "$wtree" || return 1

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
        echo "❌ Error: Branch '$branch' is protected." >&2
        return 1
    fi

    if zg_helpers_worktree_exists "$branch"; then
        echo "❌ Error: Worktree directory for '$branch' already exists." >&2
        return 1
    fi
    zg_helpers_ensure_branch_free "$branch" || return 1

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

    local dir
    if ! dir="$(zg_helpers_resolve_worktree "$target")"; then
        zg_helpers_report_worktree_not_found "$target"
        return 1
    fi

    zg_helpers_request_cd "$dir" "worktree: $target"
}

# Resolve worktree directory from name or branch (prints path)
zg_core_path() {
    local target="$1"
    [[ -n "$target" ]] || { echo "❌ Missing worktree or branch name" >&2; return 2; }

    if ! zg_helpers_resolve_worktree "$target"; then
        zg_helpers_report_worktree_not_found "$target"
        return 1
    fi
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

    local dir
    if ! dir="$(zg_helpers_resolve_worktree "$wtree")"; then
        zg_helpers_report_worktree_not_found "$wtree"
        return 1
    fi

    # Avoid operating inside the target worktree
    if zg_helpers_inside_dir "$dir"; then
        echo "❌ You are inside the '$wtree' worktree. Switch away before removing." >&2
        return 1
    fi

    if [[ "$force" == "false" ]]; then
        local branch
        branch="$(zg_helpers_worktree_branch "$dir")" || return 1
        zg_helpers_guard_protected "$wtree" "$dir" "$branch" || return 1
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
    local branches dirs i branch dir target target_real dir_real rc=0
    # A worktree with a missing directory is only warned about (rc 2): there is
    # nothing on disk to remove, and `zg prune metadata` cleans it up.
    zg_helpers_load_worktrees branches dirs || rc=$?
    [[ $rc -ne 1 ]] || return 1
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        branch="${branches[i]}" dir="${dirs[i]}"

        # A detached worktree has no branch to test for being merged.
        if [[ -z "$branch" ]]; then
            echo "⏭️  Skipping detached worktree: $(basename "$dir") ($dir)"
            skipped=$((skipped + 1)); continue
        fi

        if zg_helpers_dir_is_protected "$branch" "$dir"; then
            echo "🛡️  Skipping protected: $branch"; skipped=$((skipped + 1)); continue
        fi

        # Consider only branches that are fully merged into the default branch
        if git merge-base --is-ancestor "refs/heads/$branch" "$base"; then
            # finalize --force skips the dirty and in-progress guards, and this
            # sweep reaches worktrees other tools made (a fresh branch with no
            # commits counts as merged), so never hand it one holding work.
            if zg_helpers_worktree_busy "$dir"; then
                echo "⏭️  Skipping $branch: uncommitted work or a merge/rebase in progress, or git can't read it ($dir). Finalize it by hand: zg finalize $branch"
                skipped=$((skipped + 1)); continue
            fi
            # finalize resolves by name, and a directory named after the branch
            # wins (ADR 0001). If that is a different worktree, finalizing would
            # force-remove the wrong one, so leave this branch for the user.
            # Physical paths, so symlinked prefixes (macOS /var) still match.
            target="$(zg_helpers_resolve_worktree "$branch")" || target=""
            target_real="" dir_real="$(cd "$dir" && pwd -P)"
            # A cd failure (the directory vanished meanwhile) just means no match.
            if [[ -n "$target" ]]; then target_real="$(cd "$target" 2>/dev/null && pwd -P)" || target_real=""; fi
            if [[ "$target_real" != "$dir_real" ]]; then
                echo "❌ Not finalizing $branch: its name resolves to ${target:-nothing}, not $dir." >&2
                failed=$((failed + 1)); continue
            fi
            echo "🔥 $branch is merged into $base. Finalizing..."
            if zg_core_finalize "$branch" --force; then
                removed=$((removed + 1))
            else
                echo "❌ Failed to finalize $branch" >&2
                failed=$((failed + 1))
            fi
        else
            skipped=$((skipped + 1))
        fi
    done

    echo "✅ remove-merged complete — removed: $removed, skipped: $skipped, failed: $failed"
    [[ $rc -ne 2 ]] || echo "⚠️ Worktrees with a missing directory were not checked (see warnings above)." >&2
    [[ $failed -eq 0 ]] || return 1
}


# --- Rebuild worktree (remove then re-add the same branch at the same path) ---
zg_core_rebuild() {
    local wtree="$1"
    local force="false"

    if [[ -z "$wtree" ]]; then
        echo "❌ Error: Missing worktree name"
        return 1
    fi
    [[ ${2:-} == "--force" ]] && force="true"

    local dir branch
    if ! dir="$(zg_helpers_resolve_worktree "$wtree")"; then
        zg_helpers_report_worktree_not_found "$wtree"
        return 1
    fi
    branch="$(zg_helpers_worktree_branch "$dir")" || return 1
    if [[ -z "$branch" ]]; then
        echo "❌ Worktree '$wtree' has a detached HEAD; nothing to rebuild from." >&2
        return 1
    fi

    # Delegate validations (inside check, protection, prompt) to remove
    if [[ "$force" == "true" ]]; then
        zg_core_remove "$wtree" --force || return $?
    else
        zg_core_remove "$wtree" || return $?
    fi
    # remove also returns 0 when its prompt is declined, so a worktree that is
    # still there is the only sign that nothing was removed.
    [[ -d "$dir" ]] && return 0

    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"
    git worktree add "$dir" "$branch" || {
        echo "❌ Error: Failed to re-add worktree for '$branch' at $dir." >&2
        echo "   The old worktree was already removed; the branch is kept. Recover with:" >&2
        echo "   git worktree add \"$dir\" \"$branch\"" >&2
        return 1
    }
    zg_helpers_seed_worktree "$dir" "$root_dir"

    echo "🔧 Rebuilt worktree: $wtree"
}


# --- Finalize branch after merge ---
zg_core_finalize() {
  local target="$1"
  local force="false"

  if [[ -z "$target" ]]; then
    echo "❌ Error: Missing branch name"
    return 1
  fi
  [[ ${2:-} == "--force" ]] && force="true"

  # Find the worktree first: the guards below need its real branch. It may be
  # gone already; finalize then only deletes the branch named <target>.
  local dir="" branch="$target"
  if dir="$(zg_helpers_resolve_worktree "$target")"; then
    # Avoid operating inside the target worktree
    if zg_helpers_inside_dir "$dir"; then
      echo "❌ You are inside the '$target' worktree. Switch away before finalizing." >&2
      return 1
    fi
    # A directory-name match may hold a differently named branch (e.g. migrated
    # feature__foo): act on the branch actually checked out there. A detached
    # worktree has none, so no branch is deleted.
    branch="$(zg_helpers_worktree_branch "$dir")" || return 1
  fi

  # Protected worktrees, and the default branch wherever it is checked out,
  # require --force
  if [[ "$force" == "false" ]]; then
    zg_helpers_guard_protected "$target" "$dir" "$branch" || return 1
  fi

  # Safe confirmation
  if [[ "$force" == "false" ]]; then
    if ! read -p "Finalize '$target' (remove worktree & delete local branch)? (y/N): " -n 1 -r; then
      echo; echo "Operation cancelled."; return 1
    fi
    echo
    [[ "$REPLY" =~ ^[Yy]$ ]] || { echo "Operation cancelled."; return 0; }
  fi

  # Fresh remote info (optional but helpful)
  zg_helpers_fetch_origin || return 1

  # Remove worktree (respect --force)
  if [[ -n "$dir" ]]; then
    if [[ "$force" == "true" ]]; then
      git worktree remove --force "$dir" || { echo "❌ Failed to force-remove worktree: $target" >&2; return 1; }
    else
      git worktree remove "$dir" || { echo "❌ Failed to remove worktree: $target" >&2; return 1; }
    fi
  fi

  # Delete local branch if present (will fail if not merged—fine). The default
  # branch is never deleted, not even with --force.
  if [[ "$branch" == "$ZWEIG_DEFAULT_BRANCH" ]]; then
    echo "ℹ️ Kept the default branch '$branch'."
  elif [[ -n "$branch" ]] && git show-ref --verify --quiet "refs/heads/$branch"; then
    git branch -d "$branch" || {
      echo "⚠️ Branch $branch not deleted (not fully merged?)."
      [[ "$force" == "true" ]] && echo "Hint: use 'git branch -D $branch' to force."
    }
  fi

  echo "✅ Finalized and cleaned up: $target"
}
