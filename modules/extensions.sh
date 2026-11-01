#!/usr/bin/env bash
# Zweig Extensions Module - extensions.sh
# Optional helpers and interactive commands
# Requires: bash 4.3+ (namerefs, via zg_helpers_load_worktrees), fzf (if used)


# --- Interactive selector (fzf required) ---
zg_extensions_select() {
    if ! command -v fzf >/dev/null 2>&1; then
        echo "❌ Error: fzf is not installed"
        return 1
    fi

    local branches dirs heads i label menu="" rc=0
    # Worktrees whose directory is missing are left out with a warning.
    zg_helpers_load_worktrees branches dirs heads || rc=$?
    [[ $rc -ne 1 ]] || return 1
    for ((i = 0; i < ${#dirs[@]}; i++)); do
        label="$(zg_helpers_worktree_report_name "${branches[i]}" "${dirs[i]}" "${heads[i]}")"
        # Refs can't contain a tab, so "<label>\t<path>" splits unambiguously.
        menu+="$label"$'\t'"${dirs[i]}"$'\n'
    done
    if [[ -z "$menu" ]]; then
        echo "❌ No worktrees found" >&2
        return 1
    fi

    # fzf shows only the label; {2} (the path, quoted by fzf) feeds the preview.
    local selected fzf_rc=0
    selected="$(printf '%s' "$menu" | fzf --delimiter=$'\t' --with-nth=1 \
        --preview='git -C {2} log --oneline --decorate -n 10' \
        --prompt='Select worktree > ')" || fzf_rc=$?
    case $fzf_rc in
        0) ;;
        # No match (1) or cancelled with Esc/Ctrl-C (130): leave the user where they are.
        1|130) return 0 ;;
        *) echo "❌ Error: fzf failed (exit $fzf_rc)." >&2; return 1 ;;
    esac
    [[ -n "$selected" ]] || return 0

    # Use the picked path rather than zg_core_switch: switch resolves by name,
    # which can't reach a detached worktree outside the worktree dir.
    local dir="${selected#*$'\t'}" name="${selected%%$'\t'*}"
    zg_helpers_request_cd "$dir" "worktree: $name"
}

# --- From GitHub PR (requires gh CLI; loader enforces preconditions) ---
zg_extensions_from_pr() {
    local pr_id="${1:-}"
    if [[ -z "$pr_id" ]]; then
        echo "❌ Error: Missing PR ID"
        return 1
    fi

    # PR numbers become part of a directory name, so nothing else may get in.
    if [[ ! "$pr_id" =~ ^[1-9][0-9]*$ ]]; then
        echo "❌ Error: PR ID must be a number, got '$pr_id'." >&2
        return 1
    fi

    # Worktrees are named pr-<N>-<branch>; the prefix keeps PR 4 from matching pr-42-*.
    local prefix="pr-$pr_id-"

    # Offline fast path: a single pr-<N>-* worktree means this PR was set up
    # before, so switch to it without asking GitHub. With several (e.g. the PR's
    # head branch was renamed) let gh decide which one is current.
    local candidate found="" count=0
    for candidate in "$ZWEIG_WORKTREE_DIR/$prefix"*; do
        [[ -d "$candidate" ]] || continue
        found="$candidate"
        count=$((count + 1))
    done
    if [[ $count -eq 1 ]]; then
        echo "ℹ️ Worktree for PR #$pr_id already exists."
        zg_core_switch "${found##*/}"
        return
    fi

    # Resolve the PR head branch
    local branch
    branch="$(gh pr view "$pr_id" --json headRefName -q .headRefName 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
        echo "❌ Error: Could not resolve head branch for PR #$pr_id (not found or no access)." >&2
        return 1
    fi

    # The branch may already be checked out anywhere (an older "<N>" worktree,
    # a worktree made by another tool): switch there rather than fail on add.
    # Switch by the path git reports, not by name: a worktree-dir directory
    # named like the branch could otherwise shadow it (see docs/adr/0001).
    local existing rc=0
    existing="$(zg_helpers_branch_worktree_path "$branch")" || rc=$?
    case $rc in
        0)
            echo "ℹ️ Branch '$branch' of PR #$pr_id is already checked out in a worktree."
            if [[ ! -d "$existing" ]]; then
                zg_helpers_report_worktree_not_found "$branch"
                return 1
            fi
            zg_helpers_request_cd "$existing" "worktree: $branch"
            return ;;
        2)
            echo "❌ Error: Could not list worktrees to look up branch '$branch'." >&2
            return 1 ;;
    esac

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

    # Name the worktree pr-<N>-<branch>, with "/" flattened so it stays one level deep.
    local wt_name="$prefix${branch//\//-}"
    if ! git worktree add "$ZWEIG_WORKTREE_DIR/$wt_name" "$branch"; then
        echo "❌ Error: Failed to add worktree for PR #$pr_id (branch: $branch)." >&2
        return 1
    fi

    local root_dir
    root_dir="$(zg__control_root)" || root_dir="$(git rev-parse --show-toplevel)"
    zg_helpers_seed_worktree "$ZWEIG_WORKTREE_DIR/$wt_name" "$root_dir"

    echo "✅ Worktree created from PR #$pr_id ($branch)"
    zg_core_switch "$wt_name"
}
