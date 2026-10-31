# Zweig

A worktree-lifecycle CLI (`zg`) layered on top of `git worktree`.

## Language

**Control repo**:
The single main checkout that owns a repository's `.git` directory (as opposed to a linked worktree, whose `.git` is a pointer file). Resolved via `git rev-parse --git-common-dir`, so it's the same location no matter which worktree you run `zg` from.
_Avoid_: main repo, root repo, primary checkout

**Managed worktree**:
Any git worktree `git worktree list` reports for the control repo — regardless of which tool created it or where on disk it lives (zg's own worktree directory, or a location another tool like Claude Code or Codex chose for itself). Every read/mutate command (`list`, `switch`, `select`, `remove`, `remove merged`, `protect`, `prune`, `sync`, `status`, `finalize`) operates over all managed worktrees. Only `create` and `migrate` are opinionated about where a *new* one goes; both refuse a branch already checked out in any managed worktree.
_Avoid_: zg worktree, tracked worktree
