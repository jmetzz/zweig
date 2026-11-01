#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

# Black-box tests for tests/run_tests.sh. The runner is copied into a temp
# "tests" dir next to a dummy .bats file so it never runs the real suite, and
# bats is stubbed, with a fake HOME and a controlled PATH.

setup() {
    TEST_ROOT="$(mktemp -d)"
    export HOME="$TEST_ROOT/home"
    mkdir -p "$HOME" "$TEST_ROOT/tests" "$TEST_ROOT/stub"
    cp "$BATS_TEST_DIRNAME/run_tests.sh" "$TEST_ROOT/tests/run_tests.sh"
    : >"$TEST_ROOT/tests/dummy.bats"
    RUNNER="$TEST_ROOT/tests/run_tests.sh"
    CALLS="$TEST_ROOT/calls.log"
}

teardown() {
    rm -rf "$TEST_ROOT"
}

# Writes an executable stub bats at $1 that records its arguments in $CALLS.
make_stub() {
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\necho "$@" >>"%s"\n' "$CALLS" >"$1"
    chmod +x "$1"
}

@test "runner invokes bats found on PATH for each .bats file" {
    make_stub "$TEST_ROOT/stub/bats"
    PATH="$TEST_ROOT/stub:$PATH" run "$RUNNER"
    [ "$status" -eq 0 ]
    [ "$(cat "$CALLS")" = "$TEST_ROOT/tests/dummy.bats" ]
}

@test "runner fails with an install hint when no bats is available" {
    # PATH holds only the tools the runner needs, so no bats is reachable.
    mkdir -p "$TEST_ROOT/tools"
    for tool in env bash find dirname; do
        ln -s "$(command -v "$tool")" "$TEST_ROOT/tools/$tool"
    done
    run -1 --separate-stderr "$TEST_ROOT/tools/env" PATH="$TEST_ROOT/tools" "$RUNNER"
    [[ "$stderr" == *"bats not found"* ]]
    [[ "$stderr" == *"git submodule update --init tests/bats-core"* ]]
    [ ! -e "$CALLS" ]
}
