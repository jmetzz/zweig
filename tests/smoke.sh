#!/usr/bin/env bash
set -euo pipefail


# Installer (dry-run)
sh install.sh --dry-run --tag v0.0.0 2>/dev/null || true   # expect clear Dry Run lines

# Loader basic
if ! output="$(zg version 2>&1)"; then
  echo "❌ zg version failed"
  exit 1
fi
echo "$output" | grep -q "Zweig CLI" || {
  echo "❌ version output invalid: $output"
  exit 1
}
echo "✅ version OK"

# Path resolver + shim (manual check, not automated here):
#   zg path main                                        # prints a worktree dir or error hint
#   . "$HOME/.local/share/zweig/shims/shims.sh"          # after sourcing shim
#   zg cd <worktree>                                     # should change directory in the current shell

# Create in a repo without origin (local-only, no network)
TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
(
  set -e
  cd "$TMPDIR"
  git init testrepo >/dev/null
  cd testrepo
  git config user.email test@example.com
  git config user.name "Smoke Test"
  echo "init" > README.md
  git add README.md
  git commit -m "chore: init" >/dev/null

  # Isolate worktrees dir for this test run
  export ZWEIG_WORKTREE_DIR="$TMPDIR/wtrees"
  mkdir -p "$ZWEIG_WORKTREE_DIR"

  # No 'origin' remote present; should create from HEAD
  zg create feature-x
  test -d "$ZWEIG_WORKTREE_DIR/feature-x" || { echo "❌ worktree not created"; exit 1; }

  # Verify it's listed
  zg list | grep -q "$ZWEIG_WORKTREE_DIR/feature-x" || { echo "❌ worktree not listed"; exit 1; }
  echo "✅ create/list without origin OK"
)