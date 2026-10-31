#!/usr/bin/env bats

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
    [[ "$output" == *"not found"* ]]
}
