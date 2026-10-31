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
  `feature__foo` directory, and `zg create from-pr` names directories after the
  PR rather than the branch.

Commands that build `$ZWEIG_WORKTREE_DIR/<name>` therefore can't see or act on
a large class of real worktrees.

## Decision

A worktree is identified by its **branch name**. Every command that takes a
worktree argument will resolve it through one shared resolver
(`zg_helpers_resolve_worktree`). `switch` and `path` use it as of #3; the
remaining commands move onto it in #4, #5 and #15.

1. **Fast path:** if `$ZWEIG_WORKTREE_DIR/<identifier>` is a directory, use it.
   This costs no subprocess and covers the common case of a worktree zg created.
2. **Fallback:** match `<identifier>` against the `branch` field of
   `git worktree list --porcelain`, which reports every worktree of the
   repository regardless of location.

The directory-name match is a shortcut, not the identity. It is kept because it
is cheap and lets `zg switch <dir-name>` keep working for directory names that
differ from the branch (e.g. migrated `feature__foo`).

## Consequences

- `switch` and `path` find worktrees anywhere on disk. #4, #5 and #15 move the
  remaining commands onto the same resolver.
- Git is the source of truth for which worktrees exist; zg keeps no registry.
- If a directory under `$ZWEIG_WORKTREE_DIR` shares its name with a
  *different* branch, the fast path wins and that branch is unreachable by
  name. Most zg-created directories are named after their branch, but not all:
  `zg migrate` flattens `a/b` to `a__b`, and `zg create from-pr` uses the PR
  number, so a branch literally named `a__b` or `42` can be shadowed. This is
  accepted: such names are rare, and the directory stays reachable by its
  directory name.
- Detached-HEAD worktrees have no branch and are only reachable via the fast
  path (by directory name) for now.
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
