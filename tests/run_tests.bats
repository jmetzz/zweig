#!/usr/bin/env bats

# 1.5.0 for `run -<status>` and `run --separate-stderr`.
bats_require_minimum_version 1.5.0

# Black-box tests for tests/run_tests.sh. The runner is copied into a temp
# "tests" dir next to two dummy .bats files, so it never runs the real suite.
# The copy has no vendored tests/bats-core and HOME is fake (no basher), so each
# test places exactly the bats stubs it needs.

setup() {
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME" "$TEST_ROOT/tests" "$TEST_ROOT/stub"
    cp "$BATS_TEST_DIRNAME/run_tests.sh" "$TEST_ROOT/tests/run_tests.sh"
    : >"$TEST_ROOT/tests/a.bats"
    : >"$TEST_ROOT/tests/b.bats"
    RUNNER="$TEST_ROOT/tests/run_tests.sh"
    CALLS="$TEST_ROOT/calls.log"
    VENDORED="$TEST_ROOT/tests/bats-core/bin/bats"
    BASHER="$HOME/.basher/cellar/bin/bats"

    # A PATH holding only the external commands the runner uses (find, dirname),
    # so no system bats is reachable. The runner is started with "$BASH" (the
    # bash running bats: /bin/bash is missing or 3.2 on some systems), so its
    # #!/usr/bin/env shebang doesn't need env or bash on the restricted PATH.
    TOOLS="$TEST_ROOT/tools"
    mkdir -p "$TOOLS"
    for tool in find dirname; do
        ln -s "$(command -v "$tool")" "$TOOLS/$tool"
    done
}

teardown() {
    rm -rf "$TEST_ROOT"
}

# Writes an executable stub bats at $1 that records "<its path> <args>" in
# $CALLS and exits with $2 (default 0).
make_stub() {
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\necho "$0 $*" >>"%s"\nexit %s\n' "$CALLS" "${2:-0}" >"$1"
    chmod +x "$1"
}

# Runs the runner with PATH limited to $TOOLS plus any extra dirs given.
run_runner() {
    local path="$TOOLS"
    local dir
    for dir in "$@"; do path="$dir:$path"; done
    run --separate-stderr env PATH="$path" "$BASH" "$RUNNER"
}

@test "the restricted PATH has no bats on it" {
    run env PATH="$TOOLS" "$BASH" -c 'command -v bats'
    [ "$status" -ne 0 ]
}

@test "runner runs every .bats file with the bats found on PATH" {
    make_stub "$TEST_ROOT/stub/bats"
    make_stub "$VENDORED"
    run_runner "$TEST_ROOT/stub"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using bats: $TEST_ROOT/stub/bats"* ]]
    [[ "$output" == *"All tests passed!"* ]]
    [ "$(sort "$CALLS")" = "$TEST_ROOT/stub/bats $TEST_ROOT/tests/a.bats
$TEST_ROOT/stub/bats $TEST_ROOT/tests/b.bats" ]
}

@test "runner uses the vendored bats when none is on PATH" {
    make_stub "$VENDORED"
    run_runner
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using bats: $VENDORED"* ]]
    [ "$(wc -l <"$CALLS" | tr -d ' ')" = "2" ]
    ! grep -qv "^$VENDORED " "$CALLS"
}

@test "runner prefers the vendored bats over basher's" {
    make_stub "$VENDORED"
    make_stub "$BASHER"
    run_runner
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using bats: $VENDORED"* ]]
    ! grep -q "^$BASHER " "$CALLS"
}

@test "runner falls back to basher's bats" {
    make_stub "$BASHER"
    run_runner
    [ "$status" -eq 0 ]
    [[ "$output" == *"Using bats: $BASHER"* ]]
    [ "$(wc -l <"$CALLS" | tr -d ' ')" = "2" ]
}

@test "runner fails with an install hint when no bats is available" {
    run_runner
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"bats not found"* ]]
    [[ "$stderr" == *"git submodule update --init tests/bats-core"* ]]
    [[ "$stderr" == *"basher"* ]]
}

@test "runner says when a bats it found is not executable" {
    make_stub "$VENDORED"
    chmod -x "$VENDORED"
    run_runner
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"$VENDORED exists but is not executable"* ]]
    [ ! -e "$CALLS" ]
}

@test "runner fails when a test file fails" {
    make_stub "$TEST_ROOT/stub/bats" 1
    run_runner "$TEST_ROOT/stub"
    [ "$status" -ne 0 ]
    [[ "$output" != *"All tests passed!"* ]]
}

@test "runner fails when there are no .bats files to run" {
    rm "$TEST_ROOT/tests/a.bats" "$TEST_ROOT/tests/b.bats"
    make_stub "$TEST_ROOT/stub/bats"
    run_runner "$TEST_ROOT/stub"
    [ "$status" -eq 1 ]
    [[ "$stderr" == *"no .bats files"* ]]
    [[ "$output" != *"All tests passed!"* ]]
}
