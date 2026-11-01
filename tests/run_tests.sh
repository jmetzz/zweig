#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR="$(dirname "$0")"

# Resolve bats: PATH, then the vendored submodule, then basher.
if command -v bats >/dev/null 2>&1; then
    BATS_EXECUTABLE="$(command -v bats)"
elif [[ -x "$TESTS_DIR/bats-core/bin/bats" ]]; then
    BATS_EXECUTABLE="$TESTS_DIR/bats-core/bin/bats"
elif [[ -x "$HOME/.basher/cellar/bin/bats" ]]; then
    BATS_EXECUTABLE="$HOME/.basher/cellar/bin/bats"
else
    echo "Error: bats not found." >&2
    echo "  Use the vendored copy: git submodule update --init tests/bats-core" >&2
    echo "  Or install bats (e.g. brew install bats-core)." >&2
    exit 1
fi

# Find all .bats files in the current directory and run them
while IFS= read -r -d '' file; do
    echo "Running tests in $file"
    "$BATS_EXECUTABLE" "$file"
    echo ""
done < <(find "$TESTS_DIR" -maxdepth 1 -name "*.bats" -print0)

echo "All tests passed!"