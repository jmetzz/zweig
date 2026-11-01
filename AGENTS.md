# zweig - Gemini Development Context

This document provides development context for the `zweig` project, a command-line interface for managing `git worktree`.

## Zweig: A Worktree-Centric Git CLI

Git worktrees are a powerful but underutilized feature that allows multiple working directories from a single repository. While the native `git worktree` command provides the basics, it lacks lifecycle tooling, safety controls, ergonomics, and automation capabilities.

**Zweig** was created to solve this: a clean, modular, safe, and automation-ready CLI for managing Git worktrees at scale. It is not a replacement for Git — it is a specialization layer focused exclusively on worktree lifecycle management.

### Objectives

* **Make worktree workflows ergonomic** for daily development.
* **Avoid destructive mistakes** (accidental deletion, branch loss, etc.).
* **Enable automation-safe scripting** (clean exit codes, guarded deletes).
* **Encourage trunk-based workflows** with easy branch+worktree handling.
* **Support full lifecycle operations** (create, finalize, rebuild, sync, rebase).
* **Design with extensibility** in mind (modules, plugins, integrations).

## Project Overview

`zweig` is a CLI tool written in Bash for managing the lifecycle of `git worktree`. It provides a higher-level abstraction over the raw `git worktree` commands, making them safer and easier to use. The tool is designed to be modular, with a core set of commands and optional extensions.

The primary command is `zg`, which is an alias for the main `zweig` script.

**Key Technologies:**

* **Core Logic:** Bash
* **Release Management:** Node.js, semantic-release
* **Installation:** Shell script

## Design Philosophy

* **Minimal friction**: Every command must be safe to run and fast to type.
* **Separation of concerns**: Core Git logic is isolated from extensions.
* **Shell-native**: Bash-based for maximum portability and zero dependencies.
* **Lifecycle aware**: The CLI understands the state and intent of a worktree.
* **Automation-friendly**: Fail fast, exit clean, no surprises.
* **Declarative structure**: Subcommands are self-contained and predictable.

## Building and Running

### Installation

The `zweig` CLI is installed via a remote shell script:

```bash
curl -sSL https://raw.githubusercontent.com/jmetzz/zweig/main/install.sh | bash
```

The installer script performs the following actions:

1. Determines the latest version of `zweig` from the GitHub releases.
2. Downloads the release artifact to `$HOME/.local/share/zweig`.
3. Creates a symbolic link to the `zg` executable in `$HOME/.local/bin`.
4. Adds the `ZWEIG_WORKTREE_DIR` environment variable to the user's shell profile (e.g., `.bashrc`, `.zshrc`).

### Usage

The main command is `zg`. Here are some of the most common commands:

* `zg create <worktree name>`: Creates a new worktree (and local branch) from the default branch.
* `zg create from <branch>`: Creates a worktree from an existing branch.
* `zg create from-pr <pr-id>`: Creates worktree from GitHub PR (requires gh).
* `zg remove <worktree name>`: Removes a worktree but keeps the branch.
* `zg remove merged`: Removes worktrees whose branches are merged into the default branch.
* `zg prune metadata`: Prunes broken worktree metadata.
* `zg prune trees`: Prunes worktrees for deleted remote branches.
* `zg switch <worktree|branch>` (cd): Switches to a worktree.
* `zg list`: List all worktrees.
* `zg finalize <branch>`: Performs final cleanup after merge (removes worktree and branch).
* `zg rebuild <worktree>`: Rebuilds a worktree (removes and re-adds).
* `zg protect <worktree>`: Protects a worktree from accidental deletion.
* `zg unprotect <worktree>`: Removes protection marker from a worktree.
* `zg sync [all|current|<wtree>]`: Syncs worktrees with the default branch (or specified).
* `zg status`: Shows sync status of all worktrees.
* `zg migrate`: Migrates existing branches to worktrees.
* `zg rebase`: Rebases the current worktree onto the default branch.
* `zg help`: Shows help message.
* `zg main`: Jumps to the main worktree.
* `zg version`: Shows Zweig CLI version.
* `zg select`: Fuzzy switches to a worktree (requires fzf).

For a full list of commands, run `zg help`.

## Development Conventions

### Key Decisions

* **Command structure**: Unified CLI interface (`zg <subcommand>`) for predictability.
* **Worktree protection**: Guarded metadata prevents accidental deletion.
* **Versioning**: Semantic Versioning (SemVer) and conventional commits.
* **Releases**: Automated via GitHub Actions and `semantic-release`.
* **Branching**: Trunk-based development enforced via branch protection.
* **Contributions**: Allowed but not actively triaged (best-effort basis).

### Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/). This is enforced through a GitHub Action that runs on all pull requests.

### Linting

`shellcheck` is used for linting all shell scripts. To run the linter locally:

```bash
shellcheck $(find . -name '*.sh')
```

### Testing

Automated tests live in `tests/*.bats` and run against the real `bin/zg` in a disposable repo with a fake `HOME`.

* `make test` runs the `bats` suite via `tests/run_tests.sh`, which uses `bats` from `PATH`, else the vendored `tests/bats-core/bin/bats`, else basher's. It does not require `basher`.
* To get bats without installing it: `git submodule update --init tests/bats-core` (or install `bats-core`). `make install_deps` still installs it via `basher`.
* `make smoke` runs `tests/smoke.sh`, a secondary manual check that expects `zg` on `PATH`.

Add a bats test for every behavior change; anything not covered still needs manual testing.

### Release Process

Releases are fully automated using `semantic-release`. When a pull request is merged to the `main` branch, a GitHub Action is triggered that performs the following steps:

1. Analyzes the commit messages to determine the next version number.
2. Generates a changelog.
3. Creates a new GitHub release with the new version number and changelog.
4. Tags the new release in Git.

## Project Structure

```
.
├── bin
│   └── zg              # Main entrypoint for the CLI
├── docs
│   ├── CONTRIBUTING.md # Contribution guidelines
│   └── description.md  # Detailed project description
├── modules
│   ├── core.sh         # Core commands (create, from, remove, switch, list)
│   ├── extensions.sh   # Optional extensions (e.g., fzf, gh)
│   ├── lifecycle.sh    # Lifecycle commands (finalize, archive, rebuild, protect, unprotect)
│   ├── loader.sh       # Loads all modules and dispatches commands
│   ├── maintenance.sh  # Maintenance commands (prune, sync, etc.)
│   └── meta.sh         # Meta commands (help, version)
├── .github
│   └── workflows
│       ├── lint.yml        # GitHub Action for linting
│       └── release.yaml    # GitHub Action for releases
├── install.sh          # Installation script
├── package.json        # Defines dev dependencies for semantic-release
└── README.md           # Project README
```

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues on `jmetzz/zweig`, managed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default canonical labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout: `GLOSSARY.md` + `docs/adr/` at the repo root (`docs/adr/` is created lazily). See `docs/agents/domain.md`.

## Future Outlook

* Optional features like `self-update`, shell completions, and `ci doctor`.
* Extensibility system via dynamic plugin loading.
* Native support for metrics, CI checks, or multi-repo workflows.

Zweig is built for stability first. Features evolve when real needs surface.
