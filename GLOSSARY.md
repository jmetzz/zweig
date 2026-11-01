# Zweig

A worktree-lifecycle CLI (`zg`) layered on top of `git worktree`.

## Language

**Control repo**:
The single main checkout that owns a repository's `.git` directory (as opposed to a linked worktree, whose `.git` is a pointer file). Resolved from `git rev-parse --git-common-dir`: the nearest directory, from the current top level upwards, whose `.git` (directory, symlink or gitfile) leads to that git dir, else the git dir's parent (a bare main repo's parent, or a normal repo's parent). It's the same location no matter which worktree or subfolder you run `zg` from. When it can't be told (e.g. `GIT_DIR` without `GIT_WORK_TREE`, or a linked worktree outside a repo whose `.git` is a symlink), `zg` refuses instead of guessing, unless `ZWEIG_WORKTREE_DIR` is set.
_Avoid_: main repo, root repo, primary checkout

**Managed worktree**:
Any git worktree `git worktree list` reports for the control repo — regardless of which tool created it or where on disk it lives (zg's own worktree directory, or a location another tool like Claude Code or Codex chose for itself). Every read/mutate command (`list`, `switch`, `select`, `remove`, `remove merged`, `protect`, `prune`, `sync`, `status`, `finalize`) operates over all managed worktrees. Only `create` and `migrate` are opinionated about where a *new* one goes; both refuse a branch already checked out in any managed worktree.
_Avoid_: zg worktree, tracked worktree
