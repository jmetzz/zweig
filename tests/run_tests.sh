#!/usr/bin/env bash
# Runs every .bats file in this directory with the first bats found, in order:
#   1. bats on PATH
#   2. the vendored submodule, tests/bats-core/bin/bats
#   3. basher's install, $HOME/.basher/cellar/bin/bats
# This is the one place the lookup order is documented; the docs point here.

set -euo pipefail

TESTS_DIR="$(dirname "$0")"
VENDORED="$TESTS_DIR/bats-core/bin/bats"
BASHER="$HOME/.basher/cellar/bin/bats"

if command -v bats >/dev/null 2>&1; then
    BATS_EXECUTABLE="$(command -v bats)"
elif [[ -x "$VENDORED" ]]; then
    BATS_EXECUTABLE="$VENDORED"
elif [[ -x "$BASHER" ]]; then
    BATS_EXECUTABLE="$BASHER"
else
    echo "Error: bats not found on PATH, at $VENDORED or at $BASHER." >&2
    for candidate in "$VENDORED" "$BASHER"; do
        if [[ -e "$candidate" ]]; then
            echo "  $candidate exists but is not executable." >&2
        fi
    done
    echo "  Get the vendored copy: git submodule update --init tests/bats-core" >&2
    echo "  Or install bats-core (e.g. brew install bats-core, or make install_deps with basher)." >&2
    exit 1
fi
# Named up front: a stale bats on PATH wins over the vendored copy.
echo "Using bats: $BATS_EXECUTABLE"

# set -e stops at the first failing file.
count=0
while IFS= read -r -d '' file; do
    echo "Running tests in $file"
    "$BATS_EXECUTABLE" "$file"
    echo ""
    count=$((count + 1))
done < <(find "$TESTS_DIR" -maxdepth 1 -name "*.bats" -print0)

# Also catches a find failure, which the process substitution would hide.
if ((count == 0)); then
    echo "Error: no .bats files found in $TESTS_DIR." >&2
    exit 1
fi
echo "All tests passed!"
