# zweig

**Smart**, **safe**, **minimal** CLI for Git worktree lifecycle management.
Invoked via: `zg`

## 🌱 Why zweig?

`git worktree` is powerful but painful.
**zweig** (German for *twig*) is a hardened Bash CLI that wraps `git worktree` workflows into clean, safe, automation-ready commands.

## 🚀 Features

- 🔒 Automation-safe: no accidental deletions
- 🔁 Lifecycle aware: archive, finalize, rebuild
- ⚙️ Modular Bash: core + optional extensions (`gh`, `fzf`)
- 📦 One-line install
- 🪴 Built with trunk-based dev + semantic releases

## 📥 Install

```bash
curl -sSL https://raw.githubusercontent.com/<your-username>/zweig/main/install.sh | bash
```

## 💻 Usage

```bash
Zweig CLI (alias: zg)

zg create <branch>          # Create branch + worktree
zg from <branch>            # Create worktree from existing branch
zg remove <branch> (rm)     # Remove worktree, keep branch
zg switch <branch>          # Enter worktree
zg list                     # List worktrees


Lifecycle
zg finalize <branch>
zg rebuild <branch>
zg archive <branch>
zg protect <branch>
zg unprotect <branch>

Maintenance
zg prune-metadata
zg remove-merged
zg remove-deleted-remote
zg sync
zg status
zg migrate

Meta
zg main
zg help
```

## 🧪 Release Process

✨ Uses Conventional Commits
🔁 Fully automated via GitHub Actions + `semantic-release`
🆕 Changelog and GitHub release notes generated from commits

## Want to contribute?

See [contributing guidelines](./CONTRIBUTING.md).