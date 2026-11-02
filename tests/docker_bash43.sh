#!/usr/bin/env bash
# Runs the suite inside the bash:4.3 container; started by `make test-bash43`.
# Expects the checkout mounted read-only at /src.

set -euo pipefail

apk add git util-linux-misc

# /src is read-only and the tests write next to themselves: work on a copy.
# .git and .worktrees are skipped: the suite builds its own repos, and
# .worktrees can hold many full checkouts.
mkdir /work
for entry in /src/* /src/.[!.]*; do
    [[ "${entry##*/}" == .git || "${entry##*/}" == .worktrees ]] || cp -R "$entry" /work/
done
cd /work

export ZG_REQUIRE_PTY=1
./tests/run_tests.sh
