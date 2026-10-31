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
    [ "$status" -eq 0 ]
    [[ "$output" != *"Rebuilt"* ]]
    [ -e "$TEST_ROOT/elsewhere/ext/stale-file" ]
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

@test "zg finalize refuses a directory holding the default branch without --force" {
    make_repo
    git checkout -q -b dev
    git worktree add -q "$REPO/.worktrees/trunk" main
    run bash -c 'echo y | "$1" finalize trunk' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$output" == *"'trunk' holds the default branch 'main'"* ]]
    [ -d "$REPO/.worktrees/trunk" ]
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

@test "zg status reports outside and zg-created worktrees by branch, not the main checkout" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"- ext: ↑0 ↓0"* ]]
    [[ "$output" == *"- foo: ↑0 ↓0"* ]]
    [[ "$output" != *"- main:"* ]]
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
    git push -q origin ext foo kept
    git push -q origin --delete ext foo
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_ROOT/outside" ]
    [ ! -e "$REPO/.worktrees/foo" ]
    [ -d "$REPO/.worktrees/kept" ]
    ! git show-ref --verify --quiet refs/heads/ext
    ! git show-ref --verify --quiet refs/heads/foo
}

@test "zg prune trees skips a protected outside worktree" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    touch "$TEST_ROOT/outside/.protected"
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping protected: ext"* ]]
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
    [[ "$output" == *"- out side: ↑0 ↓0"* ]]
    run bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -eq 0 ]
    [ -d "$TEST_ROOT/out side" ]
}

@test "zg status lists the other worktrees, not the main checkout, when run from a linked worktree" {
    make_repo_with_origin
    git worktree add -q -b ext "$TEST_ROOT/outside"
    "$ZG" create foo >/dev/null
    cd "$TEST_ROOT/outside"
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"- ext: ↑0 ↓0"* ]]
    [[ "$output" == *"- foo: ↑0 ↓0"* ]]
    [[ "$output" != *"- main:"* ]]
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
    git push -q origin feature/x
    run "$ZG" status
    [ "$status" -eq 0 ]
    [[ "$output" == *"- feature/x: ↑0 ↓0"* ]]
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
    git push -q origin ext
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
    run --separate-stderr bash -c 'echo y | "$1" prune trees' _ "$ZG"
    [ "$status" -ne 0 ]
    [[ "$stderr" == *"Failed to remove worktree dir: $(realdir "$TEST_ROOT/outside")"* ]]
    [ -d "$TEST_ROOT/outside" ]
    [ ! -e "$REPO/.worktrees/foo" ]
}
