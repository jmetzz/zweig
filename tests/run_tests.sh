#!/usr/bin/env bash

set -euo pipefail

BATS_EXECUTABLE="$HOME/.basher/cellar/bin/bats"

# Find all .bats files in the current directory and run them
while IFS= read -r -d '' file; do
    echo "Running tests in $file"
    "$BATS_EXECUTABLE" "$file"
    echo ""
done < <(find "$(dirname "$0")" -maxdepth 1 -name "*.bats" -print0)

echo "All tests passed!"