# Contributing to zweig

## Project structure

The `zweig` CLI is organized into modular Bash scripts.

* `bin/zg`: The main entrypoint for the CLI.
* `modules/loader.sh`: Dispatches commands to the appropriate module functions.
* `modules/core.sh`: Contains core worktree management commands.
* `modules/lifecycle.sh`: Manages the lifecycle of worktrees (finalization, protection, rebuilding).
* `modules/maintenance.sh`: Provides maintenance commands (pruning, syncing, migration).
* `modules/meta.sh`: Includes meta commands like help and version.
* `modules/extensions.sh`: Houses optional commands that require external tools.

For a detailed list of commands and their usage, run `zg help`.

## Development Setup

This project uses a `Makefile` to consolidate all the development commands.

To get started, you need to have `basher` installed. If you don't have it, you can install it with Homebrew:

```bash
curl -s https://raw.githubusercontent.com/basherpm/basher/master/install.sh | bash
```

Once you have `basher` installed, you can install the development dependencies:

```bash
make install_deps
```

This will install the testing framework `bats-core`.

## 🚧 Process

* All changes via PRs to `main`
* Branch protection is enabled
* No direct pushes

## 📜 Commit Style

We use [Conventional Commits](https://www.conventionalcommits.org/):

Examples:

```paintext
feat: add protect/unprotect commands
fix: handle sync edge cases
chore: refactor help system
```

## 📝 Lint

To lint all the shell scripts in the project, run:

```bash
make lint
```

## 🧪 Testing

To run the test suite, run:

```bash
make test
```

## 🚀 CI & Releases

Every merge to `main` → triggers auto-version, changelog, GitHub Release

* Fully automated releases via `semantic-release`
* Version bump, changelog, GH releases are all automatic

---

Thank you for contributing!

---

## 📄 License

By contributing, you agree that your code is [MIT licensed](./LICENSE), and this applies to all contributions.
