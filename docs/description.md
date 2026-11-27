## Zweig: A Worktree-Centric Git CLI

### Why Zweig?

Git worktrees are a powerful but underutilized feature that allows multiple working directories from a single repository. While the native `git worktree` command provides the basics, it lacks lifecycle tooling, safety controls, ergonomics, and automation capabilities.

**Zweig** was created to solve this: a clean, modular, safe, and automation-ready CLI for managing Git worktrees at scale. It is not a replacement for Git — it is a specialization layer focused exclusively on worktree lifecycle management.

---

### Objectives

* **Make worktree workflows ergonomic** for daily development.
* **Avoid destructive mistakes** (accidental deletion, branch loss, etc.).
* **Enable automation-safe scripting** (clean exit codes, guarded deletes).
* **Encourage trunk-based workflows** with easy branch+worktree handling.
* **Support full lifecycle operations** (create, finalize, rebuild, sync).
* **Design with extensibility** in mind (modules, plugins, integrations).

---

### Design Philosophy

* **Minimal friction**: Every command must be safe to run and fast to type.
* **Separation of concerns**: Core Git logic is isolated from extensions.
* **Shell-native**: Bash-based for maximum portability and zero dependencies.
* **Lifecycle aware**: The CLI understands the state and intent of a worktree.
* **Automation-friendly**: Fail fast, exit clean, no surprises.
* **Declarative structure**: Subcommands are self-contained and predictable.

---

### The Build Process

The CLI was designed and built from scratch, starting with a fully modular architecture:

* A **dispatcher** (`zg`) routes all subcommands.
* **Modules** (`helpers`, `core`, `maintenance`, `extensions`) encapsulate logic.
* A **loader** detects optional extensions (`gh`, `fzf`, etc.) automatically.
* Safety layers were added to every destructive command (`finalize`, `remove`, etc.).
* A **GitHub installer** script enables one-line installation across environments.

No frameworks. No dependencies. Pure Bash — structured, testable, and DRY.

---

### Key Decisions

* **Command structure**: Unified CLI interface (`zg <subcommand>`) for predictability.
* **Worktree protection**: Guarded metadata prevents accidental deletion.
* **Versioning**: Semantic Versioning (SemVer) and conventional commits.
* **Releases**: Automated via GitHub Actions and `semantic-release`.
* **Branching**: Trunk-based development enforced via branch protection.
* **Contributions**: Allowed but not actively triaged (best-effort basis).

---

### Ideology

Zweig is unapologetically minimal.

It assumes:

* You're a developer or automation engineer who already knows Git basics.
* You want fast and safe tools that do one thing well.
* You value clarity and reproducibility over abstraction.

Zweig doesn’t try to be a Git wrapper. It’s a **worktree lifecycle manager**.

---

### Future Outlook

* Optional features like `self-update`, shell completions, and `ci doctor`.
* Extensibility system via dynamic plugin loading.
* Native support for metrics, CI checks, or multi-repo workflows.

Zweig is built for stability first. Features evolve when real needs surface.

---

### Final Thought

Zweig is the CLI that Git worktrees have been missing — deliberate, safe, minimal, and crafted for teams that care about their workflow integrity.

> Git gave you worktrees. Zweig makes them livable.
