# Contributing to zweig

Zweig is a personal project maintained on a best-effort basis. Issues and pull
requests are welcome, but they may not be triaged quickly. To report a security
problem, see [SECURITY.md](../SECURITY.md).

## Project structure

The `zweig` CLI is organized into modular Bash scripts.

* `bin/zg`: The main entrypoint for the CLI.
* `modules/loader.sh`: Dispatches commands to the appropriate module functions.
* `modules/core.sh`: Contains the worktree management and lifecycle commands (create, remove, switch, list, finalize, rebuild).
* `modules/maintenance.sh`: Provides maintenance commands (pruning, syncing, status, migration, protect).
* `modules/helpers.sh`: Shared helpers, plus the `help` and `version` commands.
* `modules/extensions.sh`: Houses optional commands that require external tools.

For a detailed list of commands and their usage, run `zg help`.

## Development Setup

This project uses a `Makefile` to consolidate all the development commands.

To run the tests you need `bats`. If you don't have it, fetch the vendored copy:

```bash
git submodule update --init tests/bats-core
```

Optionally, if you use [`basher`](https://github.com/basherpm/basher), `make install_deps` installs `bats-core` with it instead. `tests/run_tests.sh` lists where it looks for `bats`.

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
