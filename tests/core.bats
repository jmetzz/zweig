#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Black-box tests: run the real `zg` entrypoint against a disposable repo and a
# fake HOME, asserting only on output and filesystem state.

setup() {
    ZG="$BATS_TEST_DIRNAME/../bin/zg"
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME"
    unset ZWEIG_WORKTREE_DIR ZWEIG_ROOT
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_AUTHOR_NAME="Test" GIT_AUTHOR_EMAIL="test@example.com"
    export GIT_COMMITTER_NAME="Test" GIT_COMMITTER_EMAIL="test@example.com"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

# Creates a fresh repo (one commit, no remote) and cd's into it.
make_repo() {
    REPO="$TEST_ROOT/repo"
    git init -q -b main "$REPO"
    cd "$REPO"
    git commit -q --allow-empty -m "chore: init"
}

@test "zg help works" {
    run "$ZG" help
    [ "$status" -eq 0 ]
}

@test "zg help outside a repo does not create ~/.worktrees" {
    cd "$TEST_ROOT"
    run "$ZG" help
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.worktrees" ]
}

@test "zg list in a fresh repo does not create .worktrees" {
    make_repo
    run "$ZG" list
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create in a fresh repo creates the worktree dir on demand" {
    make_repo
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/foo" ]
    [ "$(git -C "$REPO/.worktrees/foo" branch --show-current)" = "foo" ]
}

@test "zg version outside a repo does not create ~/.worktrees" {
    cd "$TEST_ROOT"
    run "$ZG" version
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.worktrees" ]
}

@test "zg status in a fresh repo does not create .worktrees" {
    make_repo
    run "$ZG" status
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg select in a fresh repo reports no worktrees" {
    make_repo
    # Stub fzf so the select extension is available; it must not be reached.
    mkdir -p "$TEST_ROOT/bin"
    printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/fzf"
    chmod +x "$TEST_ROOT/bin/fzf"
    PATH="$TEST_ROOT/bin:$PATH" run "$ZG" select
    [ "$status" -ne 0 ]
    [[ "$output" == *"No worktrees found"* ]]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create honours a ZWEIG_WORKTREE_DIR that does not exist yet" {
    make_repo
    export ZWEIG_WORKTREE_DIR="$TEST_ROOT/custom/nested"
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$ZWEIG_WORKTREE_DIR/foo" ]
    [ ! -e "$REPO/.worktrees" ]
}

# Physical path, so macOS /var -> /private/var symlinks don't cause mismatches.
realdir() { (cd "$1" && pwd -P); }

@test "zg path finds a worktree created outside the zg worktree dir by branch" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run "$ZG" path ext-branch
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$TEST_ROOT/elsewhere/ext")" ]
}

@test "zg path finds a zg-created worktree by its directory name" {
    make_repo
    "$ZG" create foo >/dev/null
    run "$ZG" path foo
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$REPO/.worktrees/foo")" ]
}

@test "zg path finds a slash-named branch whose directory name differs" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/feature__foo" -b feature/foo
    run "$ZG" path feature/foo
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$TEST_ROOT/elsewhere/feature__foo")" ]
}

@test "zg switch succeeds for a worktree created outside the zg worktree dir" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run "$ZG" switch ext-branch
    [ "$status" -eq 0 ]
    [[ "$output" == *"elsewhere/ext"* ]]
}

@test "zg path fails for an unknown worktree or branch" {
    make_repo
    run "$ZG" path does-not-exist
    [ "$status" -ne 0 ]
    [[ "$output" == *"Worktree or branch 'does-not-exist' not found."* ]]
    [[ "$output" != *"exists without a worktree"* ]]
}

@test "zg path resolves an outside worktree whose path contains a space" {
    make_repo
    git worktree add -q "$TEST_ROOT/with space/ext" -b spaced
    run "$ZG" path spaced
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$TEST_ROOT/with space/ext")" ]
}

@test "zg path matches a directory name that differs from its branch" {
    make_repo
    git worktree add -q "$REPO/.worktrees/custom-dir" -b other-branch
    run "$ZG" path custom-dir
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$REPO/.worktrees/custom-dir")" ]
}

@test "zg path prefers the directory-name match over a branch of the same name" {
    make_repo
    git worktree add -q "$REPO/.worktrees/collide" -b dir-owner
    git worktree add -q "$TEST_ROOT/elsewhere/collide" -b collide
    run "$ZG" path collide
    [ "$status" -eq 0 ]
    [ "$(realdir "$output")" = "$(realdir "$REPO/.worktrees/collide")" ]
}

@test "zg path rejects relative path components" {
    make_repo
    mkdir -p "$REPO/.worktrees"
    run "$ZG" path ..
    [ "$status" -ne 0 ]
}

@test "zg switch fails for an unknown name with the error on stderr only" {
    make_repo
    run --separate-stderr "$ZG" switch does-not-exist
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Worktree or branch 'does-not-exist' not found."* ]]
}

@test "zg path and switch hint at create when the branch has no worktree" {
    make_repo
    git branch lonely
    run "$ZG" path lonely
    [ "$status" -ne 0 ]
    [[ "$output" == *"Try: zg create from lonely"* ]]
    run "$ZG" switch lonely
    [ "$status" -ne 0 ]
    [[ "$output" == *"Try: zg create from lonely"* ]]
}

@test "zg path hints at prune when the worktree directory was deleted" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/gone" -b gone
    rm -rf "$TEST_ROOT/elsewhere/gone"
    run "$ZG" path gone
    [ "$status" -ne 0 ]
    [[ "$output" == *"zg prune metadata"* ]]
    [[ "$output" != *"zg create from"* ]]
}

@test "shim: zg cd changes the shell directory and fails cleanly when unknown" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c '
        PATH="'"$BATS_TEST_DIRNAME"'/../bin:$PATH"
        source "'"$BATS_TEST_DIRNAME"'/../shims/shims.sh"
        zg cd ext-branch || exit 10
        pwd -P
        zg cd does-not-exist 2>/dev/null
        [ $? -eq 1 ] || exit 11
        exit 0
    '
    [ "$status" -eq 0 ]
    [[ "${lines[${#lines[@]}-1]}" == "$(realdir "$TEST_ROOT/elsewhere/ext")" ]]
}

@test "zg remove removes a worktree created outside the zg worktree dir by branch" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run "$ZG" remove ext-branch --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/ext" ]
    git show-ref --verify --quiet refs/heads/ext-branch
}

@test "zg protect blocks removing an outside worktree until zg unprotect" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run "$ZG" protect ext-branch
    [ "$status" -eq 0 ]
    run bash -c 'echo y | "$1" remove ext-branch' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is protected"* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
    run "$ZG" unprotect ext-branch
    [ "$status" -eq 0 ]
    run bash -c 'echo y | "$1" remove ext-branch' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/ext" ]
}

@test "zg finalize removes an outside worktree and deletes its merged branch" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run "$ZG" finalize ext-branch --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/ext" ]
    ! git show-ref --verify --quiet refs/heads/ext-branch
}

@test "zg rebuild recreates an outside worktree at its original path" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    touch "$TEST_ROOT/elsewhere/ext/stale-file"
    run "$ZG" rebuild ext-branch --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/ext/stale-file" ]
    [ "$(git -C "$TEST_ROOT/elsewhere/ext" branch --show-current)" = "ext-branch" ]
    [ ! -e "$REPO/.worktrees/ext-branch" ]
}

@test "zg remove still removes a zg-created worktree and keeps its branch" {
    make_repo
    "$ZG" create foo >/dev/null
    run bash -c 'echo y | "$1" remove foo' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/foo" ]
    git show-ref --verify --quiet refs/heads/foo
}

@test "zg finalize by directory name deletes the branch checked out there" {
    make_repo
    git worktree add -q "$REPO/.worktrees/feature__foo" -b feature/foo
    run "$ZG" finalize feature__foo --force
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/feature__foo" ]
    ! git show-ref --verify --quiet refs/heads/feature/foo
}

@test "zg finalize refuses a protected outside worktree without --force" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    "$ZG" protect ext-branch >/dev/null
    run bash -c 'echo y | "$1" finalize ext-branch' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is protected"* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
}

@test "zg rebuild refuses a detached worktree and leaves it in place" {
    make_repo
    git worktree add -q --detach "$REPO/.worktrees/detached"
    run "$ZG" rebuild detached --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"detached HEAD"* ]]
    [ -d "$REPO/.worktrees/detached" ]
}

@test "zg remove and finalize refuse to run from inside the target worktree" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    cd "$TEST_ROOT/elsewhere/ext"
    run "$ZG" remove ext-branch --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"You are inside"* ]]
    run "$ZG" finalize ext-branch --force
    [ "$status" -ne 0 ]
    [[ "$output" == *"You are inside"* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
}

@test "zg remove works from a sibling worktree whose name shares the prefix" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/foo" -b foo
    git worktree add -q "$TEST_ROOT/elsewhere/foobar" -b foobar
    cd "$TEST_ROOT/elsewhere/foobar"
    run "$ZG" remove foo --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/foo" ]
}

@test "zg rebuild leaves the worktree untouched when the prompt is declined" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    touch "$TEST_ROOT/elsewhere/ext/stale-file"
    run bash -c 'echo n | "$1" rebuild ext-branch' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [[ "$output" != *"Rebuilt"* ]]
    [ -e "$TEST_ROOT/elsewhere/ext/stale-file" ]
    git worktree list --porcelain | grep -qx "worktree $(cd "$TEST_ROOT/elsewhere/ext" && pwd -P)"
    git show-ref --verify --quiet refs/heads/ext-branch
}

@test "zg rebuild recreates the worktree and exits 0 when the prompt is accepted" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c 'echo y | "$1" rebuild ext-branch' _ "$ZG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Rebuilt"* ]]
    [ "$(git -C "$TEST_ROOT/elsewhere/ext" branch --show-current)" = "ext-branch" ]
}

@test "zg rebuild refuses a protected outside worktree without --force" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    "$ZG" protect ext-branch >/dev/null
    run bash -c 'echo y | "$1" rebuild ext-branch' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is protected"* ]]
    [ -e "$TEST_ROOT/elsewhere/ext/.protected" ]
}

@test "zg finalize deletes a merged branch that has no worktree" {
    make_repo
    git branch lonely
    run "$ZG" finalize lonely --force
    [ "$status" -eq 0 ]
    ! git show-ref --verify --quiet refs/heads/lonely
}

@test "zg finalize of a detached worktree keeps a branch sharing its name" {
    make_repo
    git branch foo
    git worktree add -q --detach "$REPO/.worktrees/foo"
    run "$ZG" finalize foo --force
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/foo" ]
    git show-ref --verify --quiet refs/heads/foo
}

# The default branch checked out in a linked worktree whose directory name
# differs from the branch, so a guard on the typed name alone would miss it.
make_default_branch_worktree() {
    make_repo
    git checkout -q -b dev
    git worktree add -q "$REPO/.worktrees/other" main
}

@test "zg finalize refuses a directory holding the default branch without --force" {
    make_default_branch_worktree
    run bash -c 'echo y | "$1" finalize other' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"'other' holds the default branch 'main'"* ]]
    [ -d "$REPO/.worktrees/other" ]
}

@test "zg remove refuses a directory holding the default branch without --force" {
    make_default_branch_worktree
    run --separate-stderr bash -c 'echo y | "$1" remove other' _ "$ZG"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"'other' holds the default branch 'main'"* ]]
    [ -d "$REPO/.worktrees/other" ]
}

@test "zg remove refuses a protected worktree on stderr" {
    make_repo
    git worktree add -q "$REPO/.worktrees/keep" -b keep
    touch "$REPO/.worktrees/keep/.protected"
    run --separate-stderr bash -c 'echo y | "$1" remove keep' _ "$ZG"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"'keep' is protected"* ]]
    [ -d "$REPO/.worktrees/keep" ]
}

@test "zg remove refuses a worktree whose branch can't be read and leaves it" {
    make_repo
    git worktree add -q "$REPO/.worktrees/broken" -b broken
    echo "gitdir: $TEST_ROOT/nonexistent" > "$REPO/.worktrees/broken/.git"
    run bash -c 'echo y | "$1" remove broken' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Cannot read the branch"* ]]
    [ -d "$REPO/.worktrees/broken" ]
}

@test "zg remove removes a detached worktree without --force" {
    make_repo
    git worktree add -q --detach "$REPO/.worktrees/detached"
    run bash -c 'echo y | "$1" remove detached' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/detached" ]
}

@test "zg rebuild refuses a directory holding the default branch without --force" {
    make_default_branch_worktree
    run bash -c 'echo y | "$1" rebuild other' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"'other' holds the default branch 'main'"* ]]
    [ -d "$REPO/.worktrees/other" ]
}

@test "zg remove --force removes a directory holding the default branch but keeps the branch" {
    make_default_branch_worktree
    run "$ZG" remove other --force
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/other" ]
    git show-ref --verify --quiet refs/heads/main
}

@test "zg rebuild --force recreates a directory holding the default branch and keeps the branch" {
    make_default_branch_worktree
    touch "$REPO/.worktrees/other/stale-file"
    run "$ZG" rebuild other --force
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/other/stale-file" ]
    [ "$(git -C "$REPO/.worktrees/other" branch --show-current)" = "main" ]
    git show-ref --verify --quiet refs/heads/main
}

# dev is created from main, so main is fully merged and `git branch -d` would
# delete it.
@test "zg finalize --force removes a directory holding the default branch but never deletes the branch" {
    make_default_branch_worktree
    run "$ZG" finalize other --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed worktree 'other'; kept the default branch 'main'"* ]]
    [ ! -e "$REPO/.worktrees/other" ]
    git show-ref --verify --quiet refs/heads/main
}

@test "zg finalize --force never deletes the default branch named directly" {
    make_repo
    git checkout -q -b dev
    run "$ZG" finalize main --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to finalize: the default branch 'main' is never deleted"* ]]
    [[ "$output" != *"Finalized"* ]]
    git show-ref --verify --quiet refs/heads/main
}

@test "zg protect and unprotect report an unknown worktree on stderr" {
    make_repo
    run --separate-stderr "$ZG" protect does-not-exist
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Worktree or branch 'does-not-exist' not found."* ]]
    run --separate-stderr "$ZG" unprotect does-not-exist
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"Worktree or branch 'does-not-exist' not found."* ]]
}

@test "zg protect by branch guards a worktree whose directory name differs" {
    make_repo
    git worktree add -q "$REPO/.worktrees/feature__foo" -b feature/foo
    run "$ZG" protect feature/foo
    [ "$status" -eq 0 ]
    run bash -c 'echo y | "$1" remove feature__foo' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is protected"* ]]
    run "$ZG" unprotect feature/foo
    [ "$status" -eq 0 ]
    run bash -c 'echo y | "$1" remove feature/foo' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/feature__foo" ]
}

# make_repo plus a bare "origin" holding main, so fetch/rebase/ls-remote work.
make_repo_with_origin() {
    make_repo
    git init -q --bare "$TEST_ROOT/origin.git"
    git remote add origin "$TEST_ROOT/origin.git"
    git push -q -u origin main
}

@test "zg status reports the main checkout, outside and zg-created worktrees by branch" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *" ext "*"↑0 ↓0"* ]]
    [[ "$output" == *" foo "*"↑0 ↓0"* ]]
    [[ "${lines[1]}" == "* main "* ]]
}

# Regression guard: prune metadata is plain `git worktree prune`, already
# location-agnostic before #5.
@test "zg prune metadata drops an outside worktree whose directory was deleted" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/outside"
    rm -rf "$TEST_ROOT/outside"
    run "$ZG" prune metadata
    [ "$status" -eq 0 ]
    [[ "$(git worktree list --porcelain)" != *"branch refs/heads/ext"* ]]
}

@test "zg prune trees removes outside and zg-created worktrees whose remote branch is gone" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    "$ZG" create kept >/dev/null
    git push -q -u origin ext foo kept
    git push -q origin --delete ext foo
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/outside" ]
    [ ! -e "$REPO/.worktrees/foo" ]
    [ -d "$REPO/.worktrees/kept" ]
    ! git show-ref --verify --quiet refs/heads/ext
    ! git show-ref --verify --quiet refs/heads/foo
}

# Regression guard: prune trees already skips the default branch as protected.
# origin's HEAD moves to dev first so origin will let main be deleted, which
# leaves the local main tracking a gone upstream.
@test "zg prune trees --force never deletes the default branch even when its remote is gone" {
    make_repo_with_origin
    git checkout -q -b dev
    git worktree add -q "$REPO/.worktrees/other" main
    git push -q origin dev
    git --git-dir="$TEST_ROOT/origin.git" symbolic-ref HEAD refs/heads/dev
    git push -q origin --delete main
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/other" ]
    git show-ref --verify --quiet refs/heads/main
}

@test "zg prune trees skips a protected outside worktree" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    git push -q origin --delete ext
    touch "$TEST_ROOT/outside/.protected"
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping protected: ext"* ]]
    [[ "$output" == *"No worktrees pruned."* ]]
    [ -d "$TEST_ROOT/outside" ]
}

@test "zg sync all rebases outside and zg-created worktrees onto origin/main" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run "$ZG" sync all
    [ "$status" -eq 0 ]
    git -C "$TEST_ROOT/outside" merge-base --is-ancestor origin/main HEAD
    git -C "$REPO/.worktrees/foo" merge-base --is-ancestor origin/main HEAD
}

@test "zg sync all skips a protected outside worktree" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    touch "$TEST_ROOT/outside/.protected"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run "$ZG" sync all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping protected: ext"* ]]
    ! git -C "$TEST_ROOT/outside" merge-base --is-ancestor origin/main HEAD
}

@test "zg sync <branch> rebases a worktree created outside the zg worktree dir" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run "$ZG" sync ext
    [ "$status" -eq 0 ]
    git -C "$TEST_ROOT/outside" merge-base --is-ancestor origin/main HEAD
}

@test "zg status and prune trees handle a detached outside worktree whose path has a space" {
    make_repo_with_origin
    git worktree add -q --detach "$TEST_ROOT/out side"
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *" (detached: $(git rev-parse --short=7 HEAD)) "*"↑0 ↓0"* ]]
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/out side" ]
}

@test "zg status lists every worktree, including the main checkout, when run from a linked worktree" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    cd "$TEST_ROOT/outside"
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *" ext "*"↑0 ↓0"* ]]
    [[ "$output" == *" foo "*"↑0 ↓0"* ]]
    [[ "${lines[1]}" == "  main "* ]]
}

@test "zg status, prune trees and sync all succeed with no linked worktrees" {
    make_repo_with_origin
    run "$ZG" status
    [ "$status" -eq 0 ]
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    run "$ZG" sync all
    [ "$status" -eq 0 ]
}

@test "zg status and prune trees warn about a worktree whose directory is missing" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    rm -rf "$TEST_ROOT/outside"
    run --separate-stderr "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Skipping ext: directory missing"*"zg prune metadata"* ]]
    run --separate-stderr bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Skipping ext: directory missing"* ]]
}

@test "zg sync all fails when a worktree's directory is missing but syncs the rest" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    rm -rf "$TEST_ROOT/outside"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run --separate-stderr "$ZG" sync all
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Skipping ext: directory missing"* ]]
    git -C "$REPO/.worktrees/foo" merge-base --is-ancestor origin/main HEAD
}

@test "zg sync all skips a detached worktree and leaves its HEAD alone" {
    make_repo_with_origin
    git worktree add -q --detach "$TEST_ROOT/parked"
    before="$(git -C "$TEST_ROOT/parked" rev-parse HEAD)"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run "$ZG" sync all
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping detached worktree: parked"* ]]
    [ "$(git -C "$TEST_ROOT/parked" rev-parse HEAD)" = "$before" ]
}

@test "zg sync all fails on a dirty outside worktree but still syncs the others" {
    make_repo_with_origin
    echo one > file.txt
    git add file.txt
    git commit -q -m "chore: add file"
    git push -q origin main
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    echo dirty > "$TEST_ROOT/outside/file.txt"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    run --separate-stderr "$ZG" sync all
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"'ext' has uncommitted changes"* ]]
    [[ "$stderr" == *"Some worktrees failed to sync"* ]]
    git -C "$REPO/.worktrees/foo" merge-base --is-ancestor origin/main HEAD
    ! git -C "$TEST_ROOT/outside" merge-base --is-ancestor origin/main HEAD
}

@test "zg sync reports an unknown worktree on stderr and fails" {
    make_repo_with_origin
    run --separate-stderr "$ZG" sync nope
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Worktree or branch 'nope' not found"* ]]
}

@test "zg status and prune trees handle an outside worktree on a slash-named branch" {
    make_repo_with_origin
    git worktree add -q -b feature/x "$TEST_ROOT/outside"
    git push -q -u origin feature/x
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *" feature/x "*"↑0 ↓0"* ]]
    git push -q origin --delete feature/x
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/outside" ]
    ! git show-ref --verify --quiet refs/heads/feature/x
}

@test "zg prune trees --force deletes an unmerged branch whose remote is gone" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git -C "$TEST_ROOT/outside" commit -q --allow-empty -m "feat: unmerged work"
    git push -q -u origin ext
    git push -q origin --delete ext
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/outside" ]
    ! git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees fails on a locked worktree but still prunes the others" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git worktree lock "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    git push -q -u origin ext foo
    git push -q origin --delete ext foo
    run --separate-stderr bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Failed to remove worktree dir: $(realdir "$TEST_ROOT/outside")"* ]]
    [ -d "$TEST_ROOT/outside" ]
    [ ! -e "$REPO/.worktrees/foo" ]
}

@test "zg prune trees keeps worktrees whose branch was never pushed" {
    make_repo_with_origin
    # ext has no upstream; foo (from zg create) tracks origin/main, which still
    # exists; local-only tracks the local main. None has a gone origin upstream.
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    git branch -q --track local-only main
    git worktree add -q "$TEST_ROOT/tracks-local" local-only
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"No worktrees pruned."* ]]
    [ -d "$TEST_ROOT/outside" ]
    [ -d "$REPO/.worktrees/foo" ]
    [ -d "$TEST_ROOT/tracks-local" ]
    git show-ref --verify --quiet refs/heads/ext
    git show-ref --verify --quiet refs/heads/foo
    git show-ref --verify --quiet refs/heads/local-only
}

@test "zg prune trees keeps a worktree whose upstream is on another remote" {
    make_repo_with_origin
    git init -q --bare "$TEST_ROOT/fork.git"
    git remote add fork "$TEST_ROOT/fork.git"
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u fork ext
    git push -q fork --delete ext
    git fetch -q --prune fork
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees keeps a live branch that origin's fetch refspec doesn't map" {
    make_repo_with_origin
    # Fetch only main: ext's upstream has no remote-tracking ref, so git can't
    # report it [gone] even though the branch is live on origin.
    git config remote.origin.fetch '+refs/heads/main:refs/remotes/origin/main'
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees prunes a branch deleted on origin by someone else" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    # Deleted directly on origin: the local remote-tracking ref survives until
    # prune trees' own fetch --prune drops it.
    git --git-dir="$TEST_ROOT/origin.git" branch -q -D ext
    git show-ref --verify --quiet refs/remotes/origin/ext
    run "$ZG" prune trees --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/outside" ]
    ! git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees removes nothing when the fetch from origin fails" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    git push -q origin --delete ext
    git remote set-url origin "$TEST_ROOT/missing.git"
    run --separate-stderr "$ZG" prune trees --force
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Failed to fetch from origin"* ]]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees exits non-zero and removes nothing when the prompt is declined" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    git push -q origin --delete ext
    run bash -c 'echo n | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees rejects an unknown argument and removes nothing" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    git push -q origin --delete ext
    run --separate-stderr bash -c 'echo y | "$1" prune trees --forse' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Unknown argument: --forse"* ]]
    [[ "$output" != *"Are you sure"* ]]
    [ -d "$TEST_ROOT/outside" ]
    run --separate-stderr "$ZG" prune trees --force extra
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Unknown argument: extra"* ]]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg prune trees refuses without an origin remote and removes nothing" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    run --separate-stderr bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"No 'origin' remote"* ]]
    [[ "$output" != *"Are you sure"* ]]
    [ -d "$TEST_ROOT/outside" ]
    [ -d "$REPO/.worktrees/foo" ]
    run "$ZG" prune trees --force
    [ "$status" -eq 1 ]
    [ -d "$TEST_ROOT/outside" ]
    git show-ref --verify --quiet refs/heads/ext
}

@test "zg remove merged finalizes an outside worktree whose branch is merged" {
    make_repo_with_origin
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/elsewhere/done" ]
    run git show-ref --verify --quiet refs/heads/done
    [ "$status" -ne 0 ]
}

@test "zg remove merged checks the branch checked out, not the directory name" {
    make_repo_with_origin
    git worktree add -q -b feature/foo "$REPO/.worktrees/feature__foo"
    git worktree add -q -b wip "$TEST_ROOT/elsewhere/wip"
    git -C "$TEST_ROOT/elsewhere/wip" commit -q --allow-empty -m "feat: unmerged"
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    [ ! -e "$REPO/.worktrees/feature__foo" ]
    run git show-ref --verify --quiet refs/heads/feature/foo
    [ "$status" -ne 0 ]
    [ -d "$TEST_ROOT/elsewhere/wip" ]
}

@test "zg remove merged skips protected and detached outside worktrees" {
    make_repo_with_origin
    git worktree add -q -b keep "$TEST_ROOT/elsewhere/keep"
    touch "$TEST_ROOT/elsewhere/keep/.protected"
    git worktree add -q --detach "$TEST_ROOT/elsewhere/loose"
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping protected: keep"* ]]
    [[ "$output" == *"Skipping detached worktree: loose"* ]]
    [ -d "$TEST_ROOT/elsewhere/keep" ]
    [ -d "$TEST_ROOT/elsewhere/loose" ]
}

# Puts a stub fzf on PATH that records its arguments and input, then prints the
# first input line containing $FZF_PICK. With FZF_PICK unset it exits like a
# cancelled fzf (130), or with $FZF_EXIT when that is set.
stub_fzf() {
    mkdir -p "$TEST_ROOT/bin"
    cat > "$TEST_ROOT/bin/fzf" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_ROOT/fzf.args"
cat > "$TEST_ROOT/fzf.input"
[ -n "${FZF_EXIT:-}" ] && exit "$FZF_EXIT"
[ -n "${FZF_PICK:-}" ] || exit 130
grep -F -m1 -- "$FZF_PICK" "$TEST_ROOT/fzf.input"
STUB
    chmod +x "$TEST_ROOT/bin/fzf"
    export TEST_ROOT PATH="$TEST_ROOT/bin:$PATH"
}

@test "zg select lists outside and detached worktrees with a git log preview" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    git worktree add -q -b feature/foo "$REPO/.worktrees/feature__foo"
    git worktree add -q --detach "$TEST_ROOT/elsewhere/loose"
    local sha7; sha7="$(git rev-parse --short=7 HEAD)"
    stub_fzf
    run "$ZG" select
    [ "$status" -eq 0 ]
    run cut -f1 "$TEST_ROOT/fzf.input"
    [ "$(sort <<<"$output")" = "$(printf '%s\n' "(detached: $sha7)" feature/foo outside)" ]
    grep -q -- "git -C {2} log --oneline --decorate -n 10" "$TEST_ROOT/fzf.args"
}

@test "zg select switches to the picked outside worktree" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    stub_fzf
    FZF_PICK=outside run "$ZG" select
    [ "$status" -eq 0 ]
    [[ "$output" == *"Path: "*"/elsewhere/outside"* ]]
}

@test "zg select reports no worktrees when only the main checkout exists" {
    make_repo
    mkdir -p "$REPO/.worktrees"
    stub_fzf
    run "$ZG" select
    [ "$status" -ne 0 ]
    [[ "$output" == *"No worktrees found"* ]]
    [ ! -e "$TEST_ROOT/fzf.input" ]
}

@test "zg migrate skips a branch already checked out in an outside worktree" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    git branch loose
    run "$ZG" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Already checked out: outside"* ]]
    [[ "$output" != *"fatal"* ]]
    [ ! -e "$REPO/.worktrees/outside" ]
    [ "$(git -C "$REPO/.worktrees/loose" branch --show-current)" = "loose" ]
}

@test "zg sync current rebases the outside worktree it is run from" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/odd-name"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    cd "$TEST_ROOT/elsewhere/odd-name"
    run "$ZG" sync current
    [ "$status" -eq 0 ]
    git merge-base --is-ancestor origin/main HEAD
}

@test "zg sync current refuses a detached worktree and leaves its HEAD alone" {
    make_repo_with_origin
    git worktree add -q --detach "$TEST_ROOT/elsewhere/loose"
    local before; before="$(git -C "$TEST_ROOT/elsewhere/loose" rev-parse HEAD)"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    cd "$TEST_ROOT/elsewhere/loose"
    run "$ZG" sync current
    [ "$status" -ne 0 ]
    [[ "$output" == *"detached"* ]]
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "zg create and create from name the outside worktree already holding the branch" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/odd-name"
    for args in "ext" "from ext"; do
        # shellcheck disable=SC2086
        run "$ZG" create $args
        [ "$status" -ne 0 ]
        [[ "$output" == *"'ext' is already checked out at "*"/elsewhere/odd-name"* ]]
        [[ "$output" != *"fatal"* ]]
        [ ! -e "$REPO/.worktrees/ext" ]
    done
}

@test "zg remove merged leaves a worktree whose directory name shadows a merged branch" {
    make_repo_with_origin
    # .worktrees/done holds unmerged work on another branch; the merged branch
    # "done" lives outside. Finalizing "done" by name would hit the wrong one.
    git worktree add -q -b other "$REPO/.worktrees/done"
    git -C "$REPO/.worktrees/done" commit -q --allow-empty -m "feat: unmerged"
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    git worktree add -q -b also-done "$TEST_ROOT/elsewhere/also-done"
    run "$ZG" remove merged --force
    [ "$status" -ne 0 ]
    [ -d "$REPO/.worktrees/done" ]
    [ "$(git -C "$REPO/.worktrees/done" branch --show-current)" = "other" ]
    [[ "$output" == *"Not finalizing done: its name resolves to $(realdir "$REPO")/.worktrees/done"* ]]
    [ ! -e "$TEST_ROOT/elsewhere/also-done" ]
}

@test "zg select switches to a picked detached worktree whose path has a space" {
    make_repo
    git worktree add -q --detach "$TEST_ROOT/else where/loose"
    stub_fzf
    FZF_PICK="(detached:" run --separate-stderr "$ZG" select
    [ "$status" -eq 0 ]
    [[ "$output" == *"Worktree: (detached: "* ]]
    [[ "$output" == *"Path: "*"/else where/loose" ]]
}

@test "zg select stays put when cancelled or nothing matches, and fails when fzf errors" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    stub_fzf
    run "$ZG" select
    [ "$status" -eq 0 ]
    [[ "$output" != *"Switched"* ]]
    FZF_EXIT=1 run "$ZG" select
    [ "$status" -eq 0 ]
    [[ "$output" != *"Switched"* ]]
    FZF_EXIT=2 run "$ZG" select
    [ "$status" -ne 0 ]
    [[ "$output" == *"fzf failed (exit 2)"* ]]
}

@test "zg select warns about a worktree whose directory is missing and lists the rest" {
    make_repo
    git worktree add -q -b gone "$TEST_ROOT/elsewhere/gone"
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    rm -rf "$TEST_ROOT/elsewhere/gone"
    stub_fzf
    run "$ZG" select
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping gone: directory missing"* ]]
    [ "$(cut -f1 "$TEST_ROOT/fzf.input")" = "outside" ]
}

@test "zg remove merged warns about a missing directory but finalizes the rest" {
    make_repo_with_origin
    git worktree add -q -b gone "$TEST_ROOT/elsewhere/gone"
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    rm -rf "$TEST_ROOT/elsewhere/gone"
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping gone: directory missing"* ]]
    [[ "$output" == *"missing directory were not checked"* ]]
    [ ! -e "$TEST_ROOT/elsewhere/done" ]
}

@test "zg remove merged skips worktrees holding uncommitted work or a rebase" {
    make_repo_with_origin
    git worktree add -q -b fresh "$TEST_ROOT/elsewhere/fresh"
    touch "$TEST_ROOT/elsewhere/fresh/notes.txt"
    git worktree add -q -b rebasing "$TEST_ROOT/elsewhere/rebasing"
    mkdir "$(git -C "$TEST_ROOT/elsewhere/rebasing" rev-parse --absolute-git-dir)/rebase-merge"
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping fresh: uncommitted work"* ]]
    [[ "$output" == *"Skipping rebasing: uncommitted work or a merge/rebase in progress"* ]]
    [ -f "$TEST_ROOT/elsewhere/fresh/notes.txt" ]
    [ -d "$TEST_ROOT/elsewhere/rebasing" ]
    [ ! -e "$TEST_ROOT/elsewhere/done" ]
}

@test "zg create reports a branch checked out in the main checkout or on a slash branch" {
    make_repo
    git worktree add -q -b feature/foo "$TEST_ROOT/elsewhere/foo"
    run "$ZG" create from feature/foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"'feature/foo' is already checked out at "*"/elsewhere/foo"* ]]
    git checkout -q -b in-main
    run "$ZG" create in-main
    [ "$status" -ne 0 ]
    [[ "$output" == *"'in-main' is already checked out at "* ]]
    [ ! -e "$REPO/.worktrees/in-main" ]
}

@test "zg sync current rebases a slash branch whose directory name differs" {
    make_repo_with_origin
    git worktree add -q -b feature/foo "$REPO/.worktrees/feature__foo"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    cd "$REPO/.worktrees/feature__foo"
    run "$ZG" sync current
    [ "$status" -eq 0 ]
    git merge-base --is-ancestor origin/main HEAD
}

@test "zg sync current refuses a protected worktree and the default branch" {
    make_repo_with_origin
    git worktree add -q -b keep "$TEST_ROOT/elsewhere/keep"
    touch "$TEST_ROOT/elsewhere/keep/.protected"
    git commit -q --allow-empty -m "chore: advance main"
    git push -q origin main
    cd "$TEST_ROOT/elsewhere/keep"
    run "$ZG" sync current
    [ "$status" -ne 0 ]
    [[ "$output" == *"(keep) is protected"* ]]
    ! git merge-base --is-ancestor origin/main HEAD
    cd "$REPO"
    run "$ZG" sync current
    [ "$status" -ne 0 ]
    [[ "$output" == *"(main) is protected"* ]]
}

@test "zg migrate names a directory that already exists for another branch" {
    make_repo
    git branch loose
    mkdir -p "$REPO/.worktrees/loose"
    run "$ZG" migrate
    [ "$status" -eq 0 ]
    [[ "$output" == *"Directory already exists, not migrating loose: "*"/.worktrees/loose"* ]]
}

@test "zg refuses to run on bash older than 4.3" {
    [ -x /bin/bash ] || skip "no /bin/bash"
    if /bin/bash -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) ))'; then
        skip "/bin/bash is 4.3 or newer"
    fi
    make_repo
    run /bin/bash "$ZG" status
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs bash 4.3 or newer"* ]]
}

@test "zg remove merged skips worktrees with a merge, cherry-pick or revert in progress" {
    make_repo_with_origin
    local op gitdir
    for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        git worktree add -q -b "op-$op" "$TEST_ROOT/elsewhere/$op"
        gitdir="$(git -C "$TEST_ROOT/elsewhere/$op" rev-parse --absolute-git-dir)"
        git rev-parse HEAD > "$gitdir/$op"
    done
    run "$ZG" remove merged --force
    [ "$status" -eq 0 ]
    for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
        [[ "$output" == *"Skipping op-$op: uncommitted work or a merge/rebase in progress"* ]]
        [ -d "$TEST_ROOT/elsewhere/$op" ]
    done
}

@test "zg create and create from refuse the default branch by name" {
    make_repo
    run "$ZG" create main
    [ "$status" -ne 0 ]
    [[ "$output" == *"Name is protected: main"* ]]
    run "$ZG" create from main
    [ "$status" -ne 0 ]
    [[ "$output" == *"Branch 'main' is protected"* ]]
    [ ! -e "$REPO/.worktrees/main" ]
}

@test "zg migrate migrates a branch whose name starts with the default branch" {
    make_repo
    git branch main-fix
    run "$ZG" migrate
    [ "$status" -eq 0 ]
    [ "$(git -C "$REPO/.worktrees/main-fix" branch --show-current)" = "main-fix" ]
}

# Byte offset of the first occurrence of $2 in $1. Comparing offsets across rows
# is only sound while the text before $2 is ASCII on every row (as the test
# names and paths here are); a non-ASCII name would shift its row's bytes.
col_of() { local prefix="${1%%"$2"*}"; echo "${#prefix}"; }

@test "zg list shows names only, main first then sorted, and marks the current worktree" {
    make_repo
    git worktree add -q -b zeta "$TEST_ROOT/elsewhere/zeta"
    git worktree add -q -b alpha "$REPO/.worktrees/alpha"
    git worktree add -q --detach "$TEST_ROOT/elsewhere/loose"
    local sha7; sha7="$(git rev-parse --short=7 HEAD)"
    run "$ZG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' "* main" "  (detached: $sha7)" "  alpha" "  zeta")" ]
    cd "$TEST_ROOT/elsewhere/zeta"
    run "$ZG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' "  main" "  (detached: $sha7)" "  alpha" "* zeta")" ]
}

@test "zg list -d and --detail print an aligned NAME/PATH/HEAD table" {
    make_repo
    git worktree add -q -b feature/long-name "$TEST_ROOT/elsewhere/x"
    local sha7 flag row path_col head_col
    sha7="$(git rev-parse --short=7 HEAD)"
    for flag in -d --detail; do
        run "$ZG" list "$flag"
        [ "$status" -eq 0 ]
        [ "${#lines[@]}" -eq 3 ]
        [[ "${lines[0]}" =~ ^"  NAME "+"PATH "+"HEAD"$ ]]
        path_col="$(col_of "${lines[0]}" PATH)" head_col="$(col_of "${lines[0]}" HEAD)"
        for row in "${lines[@]:1}"; do
            [ "${row:$path_col:1}" = "/" ]
            [ "${row:$head_col}" = "$sha7" ]
        done
        [[ "${lines[1]}" == "* main "*"/repo "* ]]
        [[ "${lines[2]}" == "  feature/long-name "*"/elsewhere/x "* ]]
    done
}

@test "zg list rejects an unknown flag or extra arguments with usage on stderr" {
    make_repo
    local args
    for args in "--bogus" "-d extra"; do
        # shellcheck disable=SC2086
        run --separate-stderr "$ZG" list $args
        [ "$status" -ne 0 ]
        [[ "$stderr" == *"Usage: zg list [-d|--detail]"* ]]
    done
}

@test "zg list and status print no ANSI codes when not on a terminal" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    run "$ZG" list
    [[ "$output" != *$'\e'* ]]
    run "$ZG" list -d
    [[ "$output" != *$'\e'* ]]
    run "$ZG" status
    [[ "$output" != *$'\e'* ]]
}

@test "zg status aligns its columns, lists main first and marks the current worktree" {
    make_repo_with_origin
    git worktree add -q -b a-much-longer-name "$TEST_ROOT/outside"
    git -C "$TEST_ROOT/outside" commit -q --allow-empty -m "feat: ahead"
    git worktree add -q --detach "$TEST_ROOT/loose"
    local sha7 row up_col down_col
    sha7="$(git rev-parse --short=7 HEAD)"
    run "$ZG" status
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 4 ]
    [[ "${lines[1]}" == "* main "*"↑0 ↓0" ]]
    [[ "${lines[2]}" == "  (detached: $sha7) "*"↑0 ↓0" ]]
    [[ "${lines[3]}" == "  a-much-longer-name "*"↑1 ↓0" ]]
    up_col="$(col_of "${lines[1]}" "↑")" down_col="$(col_of "${lines[1]}" "↓")"
    for row in "${lines[@]:1}"; do
        [ "$(col_of "$row" "↑")" -eq "$up_col" ]
        [ "$(col_of "$row" "↓")" -eq "$down_col" ]
    done
    cd "$TEST_ROOT/outside"
    run "$ZG" status
    [[ "${lines[1]}" == "  main "* ]]
    [[ "${lines[3]}" == "* a-much-longer-name "* ]]
}

@test "zg list sorts names case-insensitively and shows detached rows in the detail table" {
    make_repo
    git worktree add -q -b Zed "$TEST_ROOT/elsewhere/zed"
    git worktree add -q -b alpha "$TEST_ROOT/elsewhere/alpha"
    git worktree add -q --detach "$TEST_ROOT/elsewhere/loose"
    local sha7; sha7="$(git rev-parse --short=7 HEAD)"
    run "$ZG" list
    [ "$output" = "$(printf '%s\n' "* main" "  (detached: $sha7)" "  alpha" "  Zed")" ]
    run "$ZG" list -d
    [ "$status" -eq 0 ]
    [[ "${lines[2]}" == "  (detached: $sha7) "*"/elsewhere/loose "*"$sha7" ]]
}

@test "zg status shows ? when there is no origin to compare against" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/outside"
    run --separate-stderr "$ZG" status
    [ "$status" -eq 0 ]
    [[ "${lines[-1]}" == "  ext "*"↑? ↓?" ]]
}

@test "zg list and status mark only the nested worktree when run inside .worktrees or a subfolder" {
    make_repo_with_origin
    "$ZG" create foo >/dev/null 2>&1
    mkdir -p "$REPO/.worktrees/foo/sub/dir" "$REPO/docs"
    local where
    for where in "$REPO/.worktrees/foo" "$REPO/.worktrees/foo/sub/dir"; do
        cd "$where"
        run "$ZG" list
        [ "$output" = "$(printf '%s\n' "  main" "* foo")" ]
        run "$ZG" status
        [[ "${lines[1]}" == "  main "* ]]
        [[ "${lines[2]}" == "* foo "* ]]
    done
    cd "$REPO/docs"
    run "$ZG" list
    [ "$output" = "$(printf '%s\n' "* main" "  foo")" ]
}

@test "zg list sorts every row when the main entry is a bare repository" {
    git init -q --bare "$TEST_ROOT/bare.git"
    # git lists linked worktrees in directory order, so a-dir (zeta) comes
    # before b-dir (alpha): only a real sort puts alpha first.
    git -C "$TEST_ROOT/bare.git" worktree add -q --orphan -b zeta "$TEST_ROOT/a-dir" 2>/dev/null \
        || skip "git too old for worktree add --orphan"
    git -C "$TEST_ROOT/a-dir" commit -q --allow-empty -m "chore: init"
    git -C "$TEST_ROOT/bare.git" worktree add -q -b alpha "$TEST_ROOT/b-dir" zeta
    cd "$TEST_ROOT/a-dir"
    run "$ZG" list
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf '%s\n' "  alpha" "* zeta")" ]
}

@test "zg list and list -d warn about a missing directory and keep the other rows" {
    make_repo
    git worktree add -q -b gone "$TEST_ROOT/elsewhere/gone"
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/ext"
    rm -rf "$TEST_ROOT/elsewhere/gone"
    run --separate-stderr "$ZG" list
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Skipping gone: directory missing"* ]]
    [ "$output" = "$(printf '%s\n' "* main" "  ext")" ]
    run --separate-stderr "$ZG" list -d
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 3 ]
    [ "$(col_of "${lines[0]}" PATH)" -eq "$(col_of "${lines[2]}" /)" ]
}

@test "zg list -d keeps columns aligned for spaced paths and two detached worktrees at one commit" {
    make_repo
    git worktree add -q --detach "$TEST_ROOT/else where/b"
    git worktree add -q --detach "$TEST_ROOT/else where/a"
    local sha7 row path_col head_col
    sha7="$(git rev-parse --short=7 HEAD)"
    run "$ZG" list -d
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 4 ]
    path_col="$(col_of "${lines[0]}" PATH)" head_col="$(col_of "${lines[0]}" HEAD)"
    for row in "${lines[@]:1}"; do
        [ "${row:$path_col:1}" = "/" ]
        [ "${row:$head_col}" = "$sha7" ]
    done
    # Equal names fall back to path order.
    [[ "${lines[2]}" == *"/else where/a "* ]]
    [[ "${lines[3]}" == *"/else where/b "* ]]
}

@test "zg status widens the ahead column and says why it shows ?" {
    make_repo_with_origin
    git worktree add -q -b busy "$TEST_ROOT/busy"
    local n
    for n in 1 2 3 4 5 6 7 8 9 10; do git -C "$TEST_ROOT/busy" commit -q --allow-empty -m "feat: $n"; done
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "${lines[2]}" == "  busy "*"↑10 ↓0" ]]
    [ "$(col_of "${lines[1]}" "↓")" -eq "$(col_of "${lines[2]}" "↓")" ]
    git remote remove origin
    run --separate-stderr "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"Could not count ahead/behind for: main, busy"* ]]
}

@test "zg create from a subfolder of the main checkout uses the repo's worktree dir" {
    make_repo
    mkdir -p "$REPO/docs/deep"
    cd "$REPO/docs/deep"
    run --separate-stderr "$ZG" create bar
    [ "$status" -eq 0 ]
    [[ "$stderr" != *"No such file or directory"* ]]
    [ -d "$REPO/.worktrees/bar" ]
    [ ! -e "$HOME/.worktrees" ]
}

# Runs a script in a fresh <shell> with bin/ on PATH and the shim sourced.
# Inside the script, $1 is taken (the tests directory); don't use it.
with_shim() {
    local shell="$1" script="$2"
    "$shell" -c 'PATH="$1/../bin:$PATH"; source "$1/../shims/shims.sh"; '"$script" _ "$BATS_TEST_DIRNAME"
}

@test "shim: zg root moves the shell from a linked worktree to the project root" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/ext"
    cd "$TEST_ROOT/elsewhere/ext"
    run with_shim bash 'zg root >/dev/null || exit 10; pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$REPO")" ]
}

@test "shim: zg main moves the shell to the worktree holding the default branch" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/ext"
    cd "$TEST_ROOT/elsewhere/ext"
    run with_shim bash 'zg main >/dev/null || exit 10; pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$REPO")" ]
}

@test "shim: zg select moves the shell to the picked worktree" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/else where/outside"
    stub_fzf
    run with_shim bash 'FZF_PICK=outside zg select >/dev/null || exit 10; pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$TEST_ROOT/else where/outside")" ]
}

# Stubs gh so `gh pr view <N> --json headRefName -q .headRefName` prints $GH_HEAD.
# Without GH_HEAD it fails, printing $GH_ERR (if set) on stderr.
stub_gh() {
    mkdir -p "$TEST_ROOT/bin"
    printf '#!/bin/sh\nif [ -z "${GH_HEAD:-}" ]; then [ -n "${GH_ERR:-}" ] && echo "$GH_ERR" >&2; exit 1; fi\nprintf "%%s\\n" "$GH_HEAD"\n' > "$TEST_ROOT/bin/gh"
    chmod +x "$TEST_ROOT/bin/gh"
    export PATH="$TEST_ROOT/bin:$PATH"
}

@test "shim: zg create from-pr moves the shell into the new worktree, and again when it exists" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    stub_gh
    export GH_HEAD=pr-branch
    run with_shim bash 'zg create from-pr 42 >/dev/null 2>&1 || exit 10; pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$REPO/.worktrees/pr-42-pr-branch")" ]
    [ "$(git -C "$REPO/.worktrees/pr-42-pr-branch" branch --show-current)" = "pr-branch" ]
    run with_shim bash 'zg create from_pr 42 >/dev/null || exit 10; pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$REPO/.worktrees/pr-42-pr-branch")" ]
}

@test "shim under zsh: zg root, select, main and create from-pr move the shell" {
    command -v zsh >/dev/null || skip "zsh not installed"
    make_repo_with_origin
    git push -q origin main:pr-branch
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    stub_fzf
    stub_gh
    export GH_HEAD=pr-branch
    cd "$TEST_ROOT/elsewhere/outside"
    run with_shim zsh '
        zg root >/dev/null || exit 10; pwd -P
        FZF_PICK=outside zg select >/dev/null || exit 11; pwd -P
        zg main >/dev/null || exit 12; pwd -P
        zg create from-pr 42 >/dev/null 2>&1 || exit 13; pwd -P'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(realdir "$REPO")" ]
    [ "${lines[1]}" = "$(realdir "$TEST_ROOT/elsewhere/outside")" ]
    [ "${lines[2]}" = "$(realdir "$REPO")" ]
    [ "${lines[3]}" = "$(realdir "$REPO/.worktrees/pr-42-pr-branch")" ]
}

@test "without the shim, moving commands print the path and a shim hint, never 'Switched'" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    stub_fzf
    stub_gh
    export GH_HEAD=pr-branch FZF_PICK=outside
    cd "$TEST_ROOT/elsewhere/outside"
    # "<command args>|<label it prints>"; args are word-split on purpose.
    for case in "root|Project root" "main|Worktree: main" "switch outside|Worktree: outside" \
        "select|Worktree: outside" "create from-pr 7|Worktree: pr-7-pr-branch"; do
        # shellcheck disable=SC2086
        run --separate-stderr "$ZG" ${case%%|*}
        [ "$status" -eq 0 ]
        [[ "$output" != *[Ss]witch* ]]
        [[ "$output" == *"📂 ${case#*|}"$'\n'"   Path: /"* ]]
        [[ "$stderr" == *"source the shell shim: . \"$(realdir "$BATS_TEST_DIRNAME/..")/shims/shims.sh\""* ]]
        [ "$(pwd -P)" = "$(realdir "$TEST_ROOT/elsewhere/outside")" ]
    done
}

@test "the shim hint points at the stable install path, not the versioned release" {
    make_repo
    mkdir -p "$TEST_ROOT/share/zweig/versions/v9"
    cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../modules" "$TEST_ROOT/share/zweig/versions/v9/"
    local stable; stable="$(realdir "$TEST_ROOT")/share/zweig/shims/shims.sh"
    run --separate-stderr "$TEST_ROOT/share/zweig/versions/v9/bin/zg" root
    [ "$status" -eq 0 ]
    [[ "$stderr" == *". \"$stable\""* ]]
    run "$TEST_ROOT/share/zweig/versions/v9/bin/zg" help
    [[ "$output" == *". \"$stable\""* ]]
}

@test "without the shim, a stray ZG_CD_FILE is left alone; an unwritable handoff file fails" {
    make_repo
    printf 'keep me\n' > "$TEST_ROOT/notes.txt"
    ZG_CD_FILE="$TEST_ROOT/notes.txt" run --separate-stderr "$ZG" root
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_ROOT/notes.txt")" = "keep me" ]
    [[ "$stderr" == *"source the shell shim"* ]]
    # Shaped like the shim's but missing: also ignored.
    ZG_CD_FILE="$TEST_ROOT/zg-cd.gone" run --separate-stderr "$ZG" root
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/zg-cd.gone" ]
    [[ "$stderr" == *"source the shell shim"* ]]
    [ "$(id -u)" -ne 0 ] || skip "root can write a read-only file"
    : > "$TEST_ROOT/zg-cd.ro"
    chmod 444 "$TEST_ROOT/zg-cd.ro"
    ZG_CD_FILE="$TEST_ROOT/zg-cd.ro" run --separate-stderr "$ZG" root
    [ "$status" -eq 1 ]
    [[ "$output" == *"Path: $(realdir "$REPO")"* ]]
    [[ "$stderr" == *"Could not hand the directory to the shell shim"* ]]
}

@test "shim: a failed or cancelled move leaves the shell where it was" {
    make_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    stub_fzf
    cd "$TEST_ROOT/elsewhere/outside"
    # Cancelled select (fzf exits 130) succeeds without moving; a missing default
    # branch fails without moving.
    run with_shim bash 'zg select >/dev/null || exit 10; pwd -P; ZWEIG_DEFAULT_BRANCH=nope zg main >/dev/null 2>&1; echo "rc=$?"; pwd -P'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(realdir "$TEST_ROOT/elsewhere/outside")" ]
    [ "${lines[1]}" = "rc=1" ]
    [ "${lines[2]}" = "$(realdir "$TEST_ROOT/elsewhere/outside")" ]
}

# Puts a fake zg first on PATH for with_shim: it writes $STUB_DIR (if set) to
# the handoff file and exits $STUB_RC, so the shim can be tested on its own.
stub_zg() {
    mkdir -p "$TEST_ROOT/stubzg"
    cat > "$TEST_ROOT/stubzg/zg" <<'STUB'
#!/usr/bin/env bash
[ -n "${STUB_DIR:-}" ] && printf '%s\n' "$STUB_DIR" > "$ZG_CD_FILE"
exit "${STUB_RC:-0}"
STUB
    chmod +x "$TEST_ROOT/stubzg/zg"
}

@test "shim: stays put when zg fails after a handoff, when cd fails, and when nothing is handed off" {
    stub_zg
    mkdir -p "$TEST_ROOT/here" "$TEST_ROOT/there"
    cd "$TEST_ROOT/here"
    export TEST_ROOT
    run with_shim bash '
        PATH="$TEST_ROOT/stubzg:$PATH"
        STUB_DIR="$TEST_ROOT/there" STUB_RC=3 zg anything; echo "rc=$?"; pwd -P
        STUB_DIR="$TEST_ROOT/missing" zg anything 2>/dev/null; echo "rc=$?"; pwd -P
        zg anything; echo "rc=$?"; pwd -P'
    [ "$status" -eq 0 ]
    local here; here="$(realdir "$TEST_ROOT/here")"
    [[ "$output" == *"zg: not changing directory (zg exited 3)"* ]]
    [ "${lines[1]}" = "rc=3" ]
    [ "${lines[2]}" = "$here" ]
    [ "${lines[3]}" = "rc=1" ]
    [ "${lines[4]}" = "$here" ]
    [ "${lines[5]}" = "rc=0" ]
    [ "${lines[6]}" = "$here" ]
}

@test "shim: reuses one emptied handoff file per shell, and runs zg without one if mktemp fails" {
    make_repo
    git worktree add -q -b ext "$TEST_ROOT/elsewhere/ext"
    cd "$TEST_ROOT/elsewhere/ext"
    export TMPDIR="$TEST_ROOT/tmp"; mkdir -p "$TMPDIR"
    # A tmp cleaner removing the file between runs gets it recreated.
    run with_shim bash '
        zg root >/dev/null || exit 10
        zg switch ext >/dev/null || exit 11
        rm -f "$__ZG_CD_FILE"
        zg main >/dev/null || exit 12
        zg list >/dev/null || exit 13
        pwd -P'
    [ "$status" -eq 0 ]
    [ "$output" = "$(realdir "$REPO")" ]
    run find "$TMPDIR" -type f
    [ "${#lines[@]}" -eq 1 ]
    [[ "${lines[0]}" == */zg-cd.* ]]
    [ ! -s "${lines[0]}" ]
    # The temp dir is gone: zg still runs and prints the path instead of moving.
    TMPDIR="$TEST_ROOT/nope" run --separate-stderr with_shim bash 'zg list && zg root; echo "rc=$?"; pwd -P'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Path: $(realdir "$REPO")"* ]]
    [ "${lines[${#lines[@]}-2]}" = "rc=0" ]
    [ "${lines[${#lines[@]}-1]}" = "$(realdir "$TEST_ROOT/elsewhere/ext")" ]
}

@test "shim: zg create -s moves into the new worktree, also combined with from-pr" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    stub_gh
    export GH_HEAD=pr-branch
    run with_shim bash 'zg create -s foo >/dev/null 2>&1 || exit 10; pwd -P; zg create from-pr 43 -s >/dev/null 2>&1 || exit 11; pwd -P'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "$(realdir "$REPO/.worktrees/foo")" ]
    [ "${lines[1]}" = "$(realdir "$REPO/.worktrees/pr-43-pr-branch")" ]
}

@test "zg create from-pr names the worktree pr-<N>-<branch>, flattening slashes, on the real branch" {
    make_repo_with_origin
    git push -q origin main:feat/login-sso
    echo "SECRET=1" > .env
    stub_gh
    export GH_HEAD=feat/login-sso
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/pr-42-feat-login-sso" ]
    [ ! -e "$REPO/.worktrees/42" ]
    [ ! -e "$REPO/.worktrees/pr-42-feat" ]
    [ "$(git -C "$REPO/.worktrees/pr-42-feat-login-sso" branch --show-current)" = "feat/login-sso" ]
    [ "$(cat "$REPO/.worktrees/pr-42-feat-login-sso/.env")" = "SECRET=1" ]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-feat-login-sso"* ]]
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-feat-login-sso"* ]]
    [ "$(ls "$REPO/.worktrees")" = "pr-42-feat-login-sso" ]
}

@test "zg create from-pr switches to the PR branch's worktree wherever it is, creating nothing" {
    make_repo_with_origin
    git push -q origin main:feat/login-sso
    git worktree add -q "$TEST_ROOT/elsewhere/sso" -b feat/login-sso
    # A worktree-dir directory named like the branch, holding another branch,
    # must not shadow the branch's real worktree.
    git worktree add -q "$REPO/.worktrees/feat/login-sso" -b decoy
    stub_gh
    export GH_HEAD=feat/login-sso
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"already checked out"* ]]
    [[ "$output" == *"Path: $(realdir "$TEST_ROOT/elsewhere/sso")"* ]]
    [ "$(ls "$REPO/.worktrees")" = "feat" ]
}

@test "zg create from-pr reuses a worktree from the old <N> naming" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    git worktree add -q "$REPO/.worktrees/42" -b pr-branch
    stub_gh
    unset GH_HEAD # found offline, without asking gh
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/42"* ]]
    [ "$(ls "$REPO/.worktrees")" = "42" ]
}

@test "zg create from-pr finds an existing pr-<N>-* worktree without asking gh" {
    make_repo
    git worktree add -q "$REPO/.worktrees/pr-42-renamed" -b renamed
    git worktree add -q "$REPO/.worktrees/pr-420-other" -b other
    stub_gh
    unset GH_HEAD # the stub now fails like an offline gh
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"already exists"* ]]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-renamed"* ]]
    # pr-4 must not match pr-42-* or pr-420-*: it falls through to gh, which fails.
    run "$ZG" create from-pr 4
    [ "$status" -eq 1 ]
    [[ "$output" == *"Could not resolve head branch for PR #4"* ]]
}

@test "zg create from-pr asks gh which worktree is current when several pr-<N>-* exist" {
    make_repo
    git worktree add -q "$REPO/.worktrees/pr-42-old-name" -b old-name
    git worktree add -q "$TEST_ROOT/elsewhere/new" -b new-name
    # Named like the current branch but holding another one: only gh's answer,
    # looked up by branch, may decide.
    git worktree add -q "$REPO/.worktrees/pr-42-new-name" -b decoy
    stub_gh
    export GH_HEAD=new-name
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Several worktrees match PR #42"* ]]
    [[ "$output" == *"Path: $(realdir "$TEST_ROOT/elsewhere/new")"* ]]
}

@test "zg switch reaches a from-pr worktree by directory name and by branch" {
    make_repo_with_origin
    git push -q origin main:feat/login-sso
    stub_gh
    export GH_HEAD=feat/login-sso
    "$ZG" create from-pr 42 >/dev/null 2>&1
    for target in pr-42-feat-login-sso feat/login-sso; do
        run "$ZG" switch "$target"
        [ "$status" -eq 0 ]
        [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-feat-login-sso"* ]]
    done
}

@test "zg create from-pr rejects a PR ID that isn't a number" {
    make_repo
    stub_gh
    export GH_HEAD=pr-branch
    for bad in ../x 4/2 abc 0 042 '4*' +4; do
        run --separate-stderr "$ZG" create from-pr "$bad"
        [ "$status" -eq 1 ]
        [[ "$stderr" == *"PR ID must be a number"* ]]
    done
    run --separate-stderr "$ZG" create from-pr
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Missing PR ID"* ]]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create from-pr creates a new worktree when several pr-<N>-* exist and none holds the PR branch" {
    make_repo_with_origin
    git push -q origin main:renamed
    git worktree add -q "$REPO/.worktrees/pr-42-first" -b first
    git worktree add -q "$REPO/.worktrees/pr-42-second" -b second
    stub_gh
    export GH_HEAD=renamed
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Several worktrees match PR #42"* ]]
    [ "$(git -C "$REPO/.worktrees/pr-42-renamed" branch --show-current)" = "renamed" ]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-renamed"* ]]
}

@test "zg create from-pr ignores a leftover pr-<N>-* directory that isn't a worktree" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    mkdir -p "$REPO/.worktrees/pr-42-leftover"
    stub_gh
    export GH_HEAD=pr-branch
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" != *"already exists"* ]]
    [ "$(git -C "$REPO/.worktrees/pr-42-pr-branch" branch --show-current)" = "pr-branch" ]
}

@test "zg create from-pr reports a PR branch whose worktree directory was deleted, creating nothing" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    git worktree add -q "$TEST_ROOT/elsewhere/gone" -b pr-branch
    rm -rf "$TEST_ROOT/elsewhere/gone"
    stub_gh
    export GH_HEAD=pr-branch
    run "$ZG" create from-pr 42
    [ "$status" -eq 1 ]
    [[ "$output" != *"already checked out"* ]]
    [[ "$output" == *"zg prune metadata"* ]]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create from-pr shows gh's reason when it can't resolve the PR" {
    make_repo
    stub_gh
    unset GH_HEAD
    export GH_ERR="To get started with GitHub CLI, please run:  gh auth login"
    run --separate-stderr "$ZG" create from-pr 42
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"PR #42: To get started with GitHub CLI"* ]]
    export GH_ERR=$'error connecting to api.github.com\ncheck your internet connection'
    run --separate-stderr "$ZG" create from-pr 42
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"PR #42: error connecting to api.github.com check your internet connection"* ]]
    unset GH_ERR
    run --separate-stderr "$ZG" create from-pr 42
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"PR #42: not found or no access"* ]]
}

@test "zg create from-pr fails cleanly when git can't list worktrees" {
    make_repo
    stub_gh
    export GH_HEAD=pr-branch
    local real_git
    real_git="$(command -v git)"
    mkdir -p "$TEST_ROOT/fakegit"
    printf '#!/bin/sh\n[ "$1 $2" = "worktree list" ] && exit 128\nexec "%s" "$@"\n' "$real_git" > "$TEST_ROOT/fakegit/git"
    chmod +x "$TEST_ROOT/fakegit/git"
    PATH="$TEST_ROOT/fakegit:$PATH" run --separate-stderr "$ZG" create from-pr 42
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Could not list worktrees to look up branch 'pr-branch'"* ]]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create from-pr asks gh when both an old <N> and a pr-<N>-* worktree exist" {
    make_repo
    git worktree add -q "$REPO/.worktrees/42" -b legacy
    git worktree add -q "$REPO/.worktrees/pr-42-current" -b current
    stub_gh
    export GH_HEAD=current
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" == *"Several worktrees match PR #42"* ]]
    [[ "$output" == *"Path: $(realdir "$REPO")/.worktrees/pr-42-current"* ]]
}

@test "zg create from-pr skips stale pr-<N>-* directories and a worktree on a branch named <N>" {
    make_repo_with_origin
    git push -q origin main:pr-branch
    mkdir -p "$REPO/.worktrees/pr-42-stale"
    echo "gitdir: $TEST_ROOT/removed/gitdir" > "$REPO/.worktrees/pr-42-stale/.git"
    touch "$REPO/.worktrees/pr-42-file"
    "$ZG" create 42 >/dev/null 2>&1
    stub_gh
    export GH_HEAD=pr-branch
    run "$ZG" create from-pr 42
    [ "$status" -eq 0 ]
    [[ "$output" != *"already exists"* ]]
    [[ "$output" != *"Several worktrees"* ]]
    [ "$(git -C "$REPO/.worktrees/pr-42-pr-branch" branch --show-current)" = "pr-branch" ]
}

@test "zg remove exits non-zero and keeps the worktree when the prompt is declined" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c 'echo n | "$1" remove ext-branch' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
    git show-ref --verify --quiet refs/heads/ext-branch
}

@test "zg remove merged exits non-zero and keeps everything when the prompt is declined" {
    make_repo_with_origin
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    run bash -c 'echo n | "$1" remove merged' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/elsewhere/done" ]
    git show-ref --verify --quiet refs/heads/done
}

@test "zg finalize exits non-zero and keeps worktree and branch when the prompt is declined" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c 'echo n | "$1" finalize ext-branch' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
    git show-ref --verify --quiet refs/heads/ext-branch
}

# With no input to answer the prompt (cron, CI), each command cancels like a decline.
@test "zg remove cancels with exit 1 when there is no input for the prompt" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c '"$1" remove ext-branch </dev/null' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/elsewhere/ext" ]
}

@test "zg remove merged cancels with exit 1 when there is no input for the prompt" {
    make_repo_with_origin
    git worktree add -q -b done "$TEST_ROOT/elsewhere/done"
    run bash -c '"$1" remove merged </dev/null' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/elsewhere/done" ]
}

@test "zg finalize cancels with exit 1 when there is no input for the prompt" {
    make_repo
    git worktree add -q "$TEST_ROOT/elsewhere/ext" -b ext-branch
    run bash -c '"$1" finalize ext-branch </dev/null' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    git show-ref --verify --quiet refs/heads/ext-branch
}

@test "zg prune trees cancels with exit 1 when there is no input for the prompt" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    git push -q -u origin ext
    git push -q origin --delete ext
    run bash -c '"$1" prune trees </dev/null' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operation cancelled."* ]]
    [ -d "$TEST_ROOT/outside" ]
}

# Moves the repo's git dir out of the work tree and symlinks it back as .git.
make_symlinked_git_repo() {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    ln -s "$TEST_ROOT/gitstore" "$REPO/.git"
}

@test "zg create places the worktree under the repo when .git is a symlink" {
    make_symlinked_git_repo
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/foo" ]
    [ ! -e "$TEST_ROOT/.worktrees" ]
}

@test "zg create from inside a linked worktree uses the repo's .worktrees when .git is a symlink" {
    make_symlinked_git_repo
    "$ZG" create foo
    cd "$REPO/.worktrees/foo"
    run "$ZG" create bar
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/bar" ]
    [ ! -e "$TEST_ROOT/.worktrees" ]
}

@test "zg refuses with a clear error when GIT_DIR hides the repo root" {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    export GIT_DIR="$TEST_ROOT/gitstore"
    run --separate-stderr "$ZG" create foo
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Cannot determine the repository root"* ]]
    [ ! -e "$TEST_ROOT/.worktrees" ]
    [ ! -e "$HOME/.worktrees" ]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg help still works when GIT_DIR hides the repo root" {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    export GIT_DIR="$TEST_ROOT/gitstore"
    run "$ZG" help
    [ "$status" -eq 0 ]
}

@test "zg create works from inside a submodule and uses its own .worktrees" {
    git init -q -b main "$TEST_ROOT/subsrc"
    git -C "$TEST_ROOT/subsrc" commit -q --allow-empty -m "chore: init"
    make_repo
    git -c protocol.file.allow=always submodule add -q "$TEST_ROOT/subsrc" sub
    cd "$REPO/sub"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$REPO/sub/.worktrees/foo" ]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create resolves the work tree of a --separate-git-dir repo" {
    git init -q -b main --separate-git-dir "$TEST_ROOT/sepgit" "$TEST_ROOT/sep"
    cd "$TEST_ROOT/sep"
    git commit -q --allow-empty -m "chore: init"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/sep/.worktrees/foo" ]
    [ ! -e "$TEST_ROOT/.worktrees" ]
}

# Git accepts a gitfile with CRLF line endings or without a final newline.
@test "zg create reads a .git gitfile with CRLF line endings" {
    git init -q -b main --separate-git-dir "$TEST_ROOT/sepgit" "$TEST_ROOT/sep"
    cd "$TEST_ROOT/sep"
    git commit -q --allow-empty -m "chore: init"
    printf 'gitdir: %s\r\n' "$TEST_ROOT/sepgit" >"$TEST_ROOT/sep/.git"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/sep/.worktrees/foo" ]
}

@test "zg create reads a .git gitfile without a final newline" {
    git init -q -b main --separate-git-dir "$TEST_ROOT/sepgit" "$TEST_ROOT/sep"
    cd "$TEST_ROOT/sep"
    git commit -q --allow-empty -m "chore: init"
    printf 'gitdir: %s' "$TEST_ROOT/sepgit" >"$TEST_ROOT/sep/.git"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/sep/.worktrees/foo" ]
}

# Moves the git dir into a directory that is itself called .git-like
# (store/proj/.git) and symlinks it back as the work tree's .git.
make_nested_dotgit_repo() {
    make_repo
    mkdir -p "$TEST_ROOT/store/proj"
    mv "$REPO/.git" "$TEST_ROOT/store/proj/.git"
    ln -s "$TEST_ROOT/store/proj/.git" "$REPO/.git"
}

@test "zg create uses the work tree when .git is a symlink to a dir named .git elsewhere" {
    make_nested_dotgit_repo
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/foo" ]
    [ ! -e "$TEST_ROOT/store/proj/.worktrees" ]
}

@test "zg create from a linked worktree uses the work tree when .git is a symlink to a dir named .git elsewhere" {
    make_nested_dotgit_repo
    "$ZG" create foo
    cd "$REPO/.worktrees/foo"
    run "$ZG" create bar
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/bar" ]
    [ ! -e "$TEST_ROOT/store/proj/.worktrees" ]
}

@test "zg refuses from a linked worktree outside a symlinked-.git repo, naming the fix" {
    make_symlinked_git_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    cd "$TEST_ROOT/elsewhere/outside"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Cannot determine the repository root"* ]]
    [[ "$stderr" == *"ZWEIG_WORKTREE_DIR"* ]]
    [[ "$stderr" == *"$TEST_ROOT/gitstore"* ]]
    [ ! -e "$TEST_ROOT/.worktrees" ]
    [ ! -e "$HOME/.worktrees" ]
    [ ! -e "$REPO/.worktrees" ]
    [ ! -e "$TEST_ROOT/elsewhere/outside/.worktrees" ]
}

@test "an explicit ZWEIG_WORKTREE_DIR lets zg work from a linked worktree outside a symlinked-.git repo" {
    make_symlinked_git_repo
    git worktree add -q -b outside "$TEST_ROOT/elsewhere/outside"
    cd "$TEST_ROOT/elsewhere/outside"
    export ZWEIG_WORKTREE_DIR="$TEST_ROOT/wt"
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/wt/foo" ]
}

@test "zg refusal under GIT_DIR names GIT_DIR and GIT_WORK_TREE and exits 1" {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    export GIT_DIR="$TEST_ROOT/gitstore"
    run --separate-stderr "$ZG" create foo
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"GIT_WORK_TREE"* ]]
    [[ "$stderr" == *"$TEST_ROOT/gitstore"* ]]
}

@test "zg list refuses and zg version works when the root can't be determined" {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    export GIT_DIR="$TEST_ROOT/gitstore"
    run --separate-stderr "$ZG" list
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"Cannot determine the repository root"* ]]
    run "$ZG" version
    [ "$status" -eq 0 ]
}

@test "zg create uses GIT_WORK_TREE as the root when GIT_DIR is set" {
    make_repo
    mv "$REPO/.git" "$TEST_ROOT/gitstore"
    export GIT_DIR="$TEST_ROOT/gitstore" GIT_WORK_TREE="$REPO"
    mkdir "$REPO/sub"
    cd "$REPO/sub"
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$REPO/.worktrees/foo" ]
    [ ! -e "$REPO/sub/.worktrees" ]
}

@test "zg create from a linked worktree of a submodule uses the submodule's .worktrees" {
    git init -q -b main "$TEST_ROOT/subsrc"
    git -C "$TEST_ROOT/subsrc" commit -q --allow-empty -m "chore: init"
    make_repo
    git -c protocol.file.allow=always submodule add -q "$TEST_ROOT/subsrc" sub
    cd "$REPO/sub"
    "$ZG" create foo
    cd "$REPO/sub/.worktrees/foo"
    run "$ZG" create bar
    [ "$status" -eq 0 ]
    [ -d "$REPO/sub/.worktrees/bar" ]
    [ ! -e "$REPO/.worktrees" ]
}

@test "zg create from a linked worktree of a --separate-git-dir repo uses the work tree's .worktrees" {
    git init -q -b main --separate-git-dir "$TEST_ROOT/sepgit" "$TEST_ROOT/sep"
    cd "$TEST_ROOT/sep"
    git commit -q --allow-empty -m "chore: init"
    "$ZG" create foo
    cd "$TEST_ROOT/sep/.worktrees/foo"
    run "$ZG" create bar
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/sep/.worktrees/bar" ]
    [ ! -e "$TEST_ROOT/.worktrees" ]
}

@test "zg create from a linked worktree of a bare repo places worktrees beside the bare repo" {
    git init -q --bare "$TEST_ROOT/bare.git"
    git -C "$TEST_ROOT/bare.git" worktree add -q --orphan -b zeta "$TEST_ROOT/a-dir" 2>/dev/null \
        || skip "git too old for worktree add --orphan"
    git -C "$TEST_ROOT/a-dir" commit -q --allow-empty -m "chore: init"
    cd "$TEST_ROOT/a-dir"
    run "$ZG" create foo
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/.worktrees/foo" ]
}

# Worktrees with an initialized submodule (#38, deferred): zg keeps git's
# behaviour. git refuses to remove them without --force, and so do remove,
# finalize and rebuild. These tests record that behaviour, not endorse it:
# --force deletes the submodule's git dir, so its unpushed commits and stashes
# are lost. prune trees can't remove them even with --force (its --force only
# skips the prompt and force-deletes branches).

# Adds a one-commit "sub" repo as a submodule of the current repo, creates
# worktree $1 (branch $1) outside the repo, and initializes the submodule there.
make_worktree_with_submodule() {
    local name="$1"
    git init -q -b main "$TEST_ROOT/sub"
    git -C "$TEST_ROOT/sub" commit -q --allow-empty -m "chore: sub init"
    git -c protocol.file.allow=always submodule add -q "$TEST_ROOT/sub" sub
    git commit -q -m "chore: add submodule"
    git worktree add -q -b "$name" "$TEST_ROOT/wt-$name"
    git -C "$TEST_ROOT/wt-$name" -c protocol.file.allow=always submodule update --init -q
}

@test "zg remove refuses a worktree with an initialized submodule, as git does" {
    make_repo
    make_worktree_with_submodule sm
    run bash -c 'echo y | "$1" remove sm' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be moved or removed"* ]]
    [ -d "$TEST_ROOT/wt-sm/sub" ]
    git show-ref --verify --quiet refs/heads/sm
}

@test "zg remove --force removes a worktree with an initialized submodule and keeps its branch" {
    make_repo
    make_worktree_with_submodule sm
    run "$ZG" remove sm --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/wt-sm" ]
    git show-ref --verify --quiet refs/heads/sm
}

@test "zg finalize refuses a worktree with an initialized submodule and keeps its branch" {
    make_repo
    make_worktree_with_submodule sm
    run bash -c 'echo y | "$1" finalize sm' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be moved or removed"* ]]
    [ -d "$TEST_ROOT/wt-sm/sub" ]
    git show-ref --verify --quiet refs/heads/sm
}

@test "zg finalize --force removes a worktree with an initialized submodule and its merged branch" {
    make_repo
    make_worktree_with_submodule sm
    run "$ZG" finalize sm --force
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/wt-sm" ]
    ! git show-ref --verify --quiet refs/heads/sm
}

@test "zg rebuild refuses a worktree with an initialized submodule and leaves it in place" {
    make_repo
    make_worktree_with_submodule sm
    run bash -c 'echo y | "$1" rebuild sm' _ "$ZG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be moved or removed"* ]]
    [ -d "$TEST_ROOT/wt-sm/sub" ]
    [[ "$output" != *"Rebuilt"* ]]
    git show-ref --verify --quiet refs/heads/sm
}

@test "zg prune trees keeps a gone worktree with an initialized submodule and exits non-zero" {
    make_repo_with_origin
    make_worktree_with_submodule sm
    git push -q -u origin sm
    git push -q origin --delete sm
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot be moved or removed"* ]]
    [ -d "$TEST_ROOT/wt-sm/sub" ]
    git show-ref --verify --quiet refs/heads/sm
}

# remove merged finalizes with --force, which would bypass git's refusal and
# delete the submodule's git dir, so it must leave these worktrees alone.
@test "zg remove merged skips a worktree with an initialized submodule and keeps its unpushed commits" {
    make_repo_with_origin
    make_worktree_with_submodule sm
    git push -q origin main   # so sm counts as merged into origin/main
    git -C "$TEST_ROOT/wt-sm/sub" commit -q --allow-empty -m "chore: unpushed work"
    local unpushed
    unpushed="$(git -C "$TEST_ROOT/wt-sm/sub" rev-parse HEAD)"
    run bash -c 'echo y | "$1" remove merged' _ "$ZG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping sm: it has an initialized submodule"* ]]
    [[ "$output" == *"zg remove sm --force"* ]]
    [[ "$output" == *"removed: 0"* ]]
    [ -d "$TEST_ROOT/wt-sm/sub" ]
    git show-ref --verify --quiet refs/heads/sm
    [ "$(git -C "$TEST_ROOT/wt-sm/sub" rev-parse HEAD)" = "$unpushed" ]
}
