# Contributing to zweig

## 🚧 Process

- All changes via PRs to `main`
- Branch protection is enabled
- No direct pushes

## 📜 Commit Style

We use [Conventional Commits](https://www.conventionalcommits.org/):

Examples:

```paintext
feat: add protect/unprotect commands
fix: handle sync edge cases
chore: refactor help system
````

## 🧪 Lint

Use `shellcheck` for all shell files:

```bash
shellcheck $(find . -name '*.sh')
```

## 🚀 Releases

Every merge to main → triggers auto-version, changelog, GitHub Release

## 📄 License

MIT License applies to all contributions.
