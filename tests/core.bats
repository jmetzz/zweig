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
