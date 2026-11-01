# zweig

**Smart**, **safe**, **minimal** CLI for Git worktree lifecycle management.

> Invoked via: `zg`

## 🌱 Why zweig?

Managing `git worktree` is powerful but painful.
**zweig** (German for *twig*) is a hardened Bash CLI that abstracts the low-level commands and wraps `git worktree` workflows into clean, safe, lifecycle-aware, and automation-ready workflows.

## 🚀 Features

- 🔁 Lifecycle aware: create, navigate, finalize, rebuild, protect, sync, and clean
- 🌍 Location-agnostic: manages every worktree of the repo, wherever it lives on disk (including ones created by plain `git worktree add` or other tools); only `create` decides where a new one goes
- 📦 One-line install
- 🔒 Automation-safe: no accidental deletions
- ⚙️ Modular Bash codebase: core + optional extensions (`gh`, `fzf`)
- 🪶 Lightweight: pure shell + Git only (no exotic dependencies for core functionalities)
- 👀 Readable reports: `zg list` (names, current one marked `*`; `-d`/`--detail` adds an aligned PATH/HEAD table) and `zg status` (aligned ahead/behind per worktree)
- 🪴 Built with trunk-based dev + semantic releases

## Dependencies

- ❗ Requires `Bash` 4.3+
- ❗ Requires `Git`

## ⚙️ Configuration

You can configure `zweig` behavior using the following environment variables.
To override the defaults, you must export these variables manually in your shell rc file (e.g., `.bashrc`, `.zshrc`):

- `ZWEIG_WORKTREE_DIR`: Specifies the base directory where worktrees are created. It doesn't limit which worktrees zg manages: bulk commands (`list`, `status`, `sync all`, `prune trees`, `remove merged`, `select`) act on every worktree of the repo, wherever it lives on disk, and `migrate` skips any branch already checked out in one of them.
    Default: `<repo-root>/.worktrees`, resolved per repository (same directory whether you're in the main checkout or an existing worktree). Falls back to `$HOME/.worktrees` when run outside a Git repository.
- `ZWEIG_DEFAULT_BRANCH`: Sets the default main branch name for operations (e.g., `create`, `sync`).
    Default: `main`
- `ZWEIG_DEFAULT_SYNC_SCOPE`: Defines the default scope for `zg sync` if no argument is provided.
    Default: `current`
- `NO_COLOR`: When set (to any value), `zg list` and `zg status` print without colours. Colours are also off whenever output is not a terminal (e.g. piped).
- `ZWEIG_COPY_ON_CREATE`: Space-separated list of local files/directories (relative to the repo root) copied into every newly created worktree, when present in the source and absent in the target. Never overwrites.
    Default: `.env .env.local .env.development .env.test .env.production AGENTS.md CLAUDE.md GEMINI.md .claude .cursor .codex .antigravity`

## 📥 Install

```bash
curl -fsSL https://raw.githubusercontent.com/jmetzz/zweig/main/install.sh | sh
```

*Note:* After installation, make sure that `~/.local/bin` is included in your `PATH` environment variable if it is not already.

## 🐳 Docker Usage

You can use the provided `Dockerfile` to create a containerized environment for testing the `zweig` CLI. This simulates an end-user installation.

1. **Build the Docker image:**
    Navigate to the project's root directory and run:

    ```bash
    docker build -t zweig-e2e .
    ```

2. **Run a container from the image:**
    This will give you an interactive Bash shell inside the container where `zweig` is installed.

    ```bash
    docker run -it zweig-e2e
    ```

3. **Test the `zg` command inside the container:**

    ```bash
    root@<container_id>:/app# zg help
    root@<container_id>:/app# zg list
    root@<container_id>:/app# zg create my-test-worktree
    ```

### Interactive Testing

To perform a more comprehensive interactive test of all `zg` commands, follow these steps:

1. **Run an interactive shell in the Docker container:**

    ```bash
    docker run -it -v ~/.gitconfig:/root/.gitconfig zweig-e2e
    ```

2. **Inside the container, test the `zg` commands:**
    You will be at a Bash prompt (`root@<container_id>:/app#`). You can then execute `zg` commands.

    - **Example: Basic commands**

        ```bash
        root@<container_id>:/app# zg help
        root@<container_id>:/app# zg list
        root@<container_id>:/app# zg version
        ```

    - **Example: Commands requiring a Git repository**
        For commands like `zg create`, `zg remove`, `zg sync`, etc., you'll need to initialize a Git repository first.

        ```bash
        root@<container_id>:/app# mkdir my_test_repo
        root@<container_id>:/app# cd my_test_repo
        root@<container_id>:/app/my_test_repo# git init
        root@<container_id>:/app/my_test_repo# git config user.email "test@example.com"
        root@<container_id>:/app/my_test_repo# git config user.name "Test User"
        root@<container_id>:/app/my_test_repo# touch README.md
        root@<container_id>:/app/my_test_repo# git add README.md
        root@<container_id>:/app/my_test_repo# git commit -m "Initial commit"
        ```

        Now you can try commands like:

        ```bash
        root@<container_id>:/app/my_test_repo# zg create feature/my-new-feature
        root@<container_id>:/app/my_test_repo# zg list
        root@<container_id>:/app/my_test_repo# zg switch feature/my-new-feature
        ```

    - **Exit the container:**
        Type `exit` or press `Ctrl+D`.

## 💻 Usage

For a full list of commands and their usage, run `zg help`.

Here are some examples of conversational API usage:

- Sync all worktrees:

  ```bash
  zg sync all
  ```

- Create a worktree from a pull request number. The worktree checks out the PR's branch and is named `pr-<N>-<branch>`, with `/` turned into `-` (PR 42 on `feat/login-sso` becomes `.worktrees/pr-42-feat-login-sso`). Running it again switches to the existing worktree:

  ```bash
  zg create from-pr 42
  ```

- Remove the worktrees (and local branches) whose remote branch was deleted, for example after a PR merge. Only branches that track a branch on `origin` (pushed with `git push -u`) and whose remote branch is now gone are pruned; branches that were never pushed are kept, and the command refuses to run without an `origin` remote:

  ```bash
  zg prune trees
  ```

- Enable the shell shim so commands that move you (`zg cd`/`switch`, `main`, `root`, `select`, `create -s`, `create from-pr`) change your shell's directory. A subprocess can't do that on its own; without the shim these commands print the target path instead. Add to your `.bashrc`/`.zshrc` (or run `install.sh --write-rc`):

  ```bash
  . "$HOME/.local/share/zweig/shims/shims.sh"
  ```

- Create a worktree and switch into it in one step (requires the shell shim):

  ```bash
  zg create -s my-feature
  ```

## 🧪 Release Process

✨ Uses Conventional Commits
🔁 Fully automated via GitHub Actions + `semantic-release`
🆕 Changelog and GitHub release notes generated from commits
*Note:* The `CHANGELOG.md` file is updated automatically during each release.

## Want to contribute?

See [contributing guidelines](./docs/CONTRIBUTING.md).
