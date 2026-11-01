# 1. Branch name is the canonical identity of a worktree

Date: 2026-10-31

## Status

Accepted

## Context

zg originally assumed it was the only tool creating worktrees and that every
**managed worktree** (see `GLOSSARY.md`) lived at `$ZWEIG_WORKTREE_DIR/<name>`,
with `<name>` equal to the branch name. Neither holds in practice:

- Other tools (Claude Code, Codex, plain `git worktree add`) create worktrees
  wherever they choose, under directory names zg doesn't control.
- zg itself breaks the equality: `zg migrate` flattens `feature/foo` into a
  `feature__foo` directory, and `zg create from-pr` names directories
  `pr-<N>-<branch>` with `/` flattened to `-` (older versions used the bare
  PR number).

Commands that build `$ZWEIG_WORKTREE_DIR/<name>` therefore can't see or act on
a large class of real worktrees.

## Decision

A worktree is identified by its **branch name**. Every command that takes a
worktree argument resolves it through one shared resolver
(`zg_helpers_resolve_worktree`). Bulk commands, which take no worktree
argument, enumerate every linked worktree from `git worktree list --porcelain`
(`zg_helpers_list_worktrees`) instead of globbing `$ZWEIG_WORKTREE_DIR`.
Commands that act on the worktree they run in use that worktree's own path.

1. **Fast path:** if `$ZWEIG_WORKTREE_DIR/<identifier>` is a directory, use it.
   This costs no subprocess and covers the common case of a worktree zg created.
2. **Fallback:** match `<identifier>` against the `branch` field of
   `git worktree list --porcelain`, which reports every worktree of the
   repository regardless of location.

The directory-name match is a shortcut, not the identity. It is kept because it
is cheap and lets `zg switch <dir-name>` keep working for directory names that
differ from the branch (e.g. migrated `feature__foo`).

## Consequences

- Commands find and sweep worktrees anywhere on disk.
- Git is the source of truth for which worktrees exist; zg keeps no registry.
- If a directory under `$ZWEIG_WORKTREE_DIR` shares its name with a
  *different* branch, the fast path wins and that branch is unreachable by
  name. Most zg-created directories are named after their branch, but not all:
  `zg migrate` flattens `a/b` to `a__b`, and `zg create from-pr` uses
  `pr-<N>-<branch>` (the bare PR number in older versions), so a branch
  literally named `a__b`, `pr-42-x` or `42` can be shadowed. This is
  accepted: such names are rare, and the directory stays reachable by its
  directory name.
- Detached-HEAD worktrees have no branch and are only reachable via the fast
  path (by directory name) for now. Bulk sweeps list them in `status` and
  `select` but skip them in `sync all`, `prune trees` and `remove merged`:
  they have no branch to rebase, look up on the remote or test for merging.
  `sync current` refuses one for the same reason.
- Identifiers containing `.` or `..` path components are rejected, so the fast
  path can't be used to traverse out of `$ZWEIG_WORKTREE_DIR`. (The fallback
  still resolves worktrees anywhere on disk, by branch.)

## Alternatives considered

- **Keep directory name == branch name.** Simple, but can't represent
  worktrees created by other tools or zg's own flattened names.
- **Always query `git worktree list`.** Correct, but adds a subprocess to every
  command for the case zg handles most often.
- **A zg-owned registry of worktrees.** Duplicates state git already has and
  drifts the moment another tool adds or removes a worktree.
