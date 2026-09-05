#!/usr/bin/env sh

set -e

# ------------------------
# Zweig Installer Script
# ------------------------

# Simple, pipeable installer for Zweig
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jmetzz/zweig/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/jmetzz/zweig/main/install.sh | sh -s -- --tag v1.2.3
#   ./install.sh --local .                     # install from a local clone, no network


REPO="jmetzz/zweig"
BRANCH="main"                 # default when no tag is provided
TAG=""                        # optional; when set, overrides BRANCH
LOCAL=""                      # optional; when set, install from this local clone instead of downloading
ROOT="${ZWEIG_ROOT:-$HOME/.local/share/zweig}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
DRY_RUN=0
FORCE=0
UNINSTALL=0
WRITE_RC=0

log()  { printf '%s\n' "[zweig-install] $*"; }
err()  { printf '%s\n' "[zweig-install] ERROR: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }; }

usage() {
  cat <<EOF
Usage: install.sh [--tag <vX.Y.Z>] [--local <path>] [--root <dir>] [--bin-dir <dir>] [--force] [--dry-run] [--uninstall] [--write-rc]

Options:
  --tag <vX.Y.Z>   Install a specific release tag (default: latest from 'main' branch)
  --local <path>   Install from a local git clone at <path> instead of downloading from GitHub.
                    Packages HEAD's tracked files (git archive), so uncommitted changes are not included.
  --root <dir>     Install root (default: \$HOME/.local/share/zweig)
  --bin-dir <dir>  Symlink directory for 'zg' (default: \$HOME/.local/bin)
  --force          Overwrite existing installation for the chosen label
  --dry-run        Print what would happen; make no changes
  --uninstall      Remove symlink and install tree for the chosen label
  --write-rc       Append a source line to your shell rc to enable 'zg' cd shim (bash/zsh preferred)

Environment:
  ZWEIG_ROOT       Overrides --root
  BIN_DIR          Overrides --bin-dir
EOF
}

# --- Parse args (POSIX) ---
while [ $# -gt 0 ]; do
  case "$1" in
    --tag)      [ $# -ge 2 ] || { err "--tag needs a value"; usage; exit 1; }; TAG="$2"; shift 2 ;;
    --local)    [ $# -ge 2 ] || { err "--local needs a value"; usage; exit 1; }; LOCAL="$2"; shift 2 ;;
    --root)     [ $# -ge 2 ] || { err "--root needs a value"; usage; exit 1; }; ROOT="$2"; shift 2 ;;
    --bin-dir)  [ $# -ge 2 ] || { err "--bin-dir needs a value"; usage; exit 1; }; BIN_DIR="$2"; shift 2 ;;
    --force)    FORCE=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --uninstall)UNINSTALL=1; shift ;;
    --write-rc) WRITE_RC=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          err "unknown option: $1"; usage; exit 1 ;;
  esac
done

if [ -n "$TAG" ] && [ -n "$LOCAL" ]; then
  err "--tag and --local are mutually exclusive"
  exit 1
fi

if [ -n "$LOCAL" ]; then
  need git
  [ -d "$LOCAL/.git" ] || { err "--local path '$LOCAL' is not a git clone"; exit 1; }
else
  need curl
  need tar
fi
mkdir -p "$BIN_DIR" "$ROOT/versions"

# Compute label + source
if [ -n "$LOCAL" ]; then
  LOCAL_SHA="$(git -C "$LOCAL" rev-parse --short HEAD 2>/dev/null)" || { err "failed to resolve HEAD in '$LOCAL'"; exit 1; }
  LABEL="local-$LOCAL_SHA"
  if ! git -C "$LOCAL" diff --quiet 2>/dev/null || ! git -C "$LOCAL" diff --cached --quiet 2>/dev/null; then
    log "Warning: '$LOCAL' has uncommitted changes; only the last commit ($LOCAL_SHA) will be installed."
  fi
elif [ -n "$TAG" ]; then
  LABEL="$TAG"
  URL="https://github.com/$REPO/archive/refs/tags/$TAG.tar.gz"
else
  LABEL="$BRANCH"
  URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
fi

DEST="$ROOT/versions/$LABEL"
LINK="$BIN_DIR/zg"

# Uninstall path
if [ "$UNINSTALL" -eq 1 ]; then
  log "Uninstalling Zweig label '$LABEL'"
  [ -L "$LINK" ] && rm -f "$LINK"
  [ -d "$DEST" ] && rm -rf "$DEST"
  log "Done. (Other labels under $ROOT/versions are untouched.)"
  exit 0
fi

# Dry-run summary
if [ "$DRY_RUN" -eq 1 ]; then
  if [ -n "$LOCAL" ]; then
    log "[Dry Run] Would package HEAD ($LOCAL_SHA) from: $LOCAL"
  else
    log "[Dry Run] Would download: $URL"
  fi
  log "[Dry Run] Would extract to: $DEST"
  log "[Dry Run] Would symlink: $LINK -> $DEST/bin/zg"
  log "[Dry Run] Would link shim to: $ROOT/shims/shims.sh (if present in archive)"
  # PATH guidance
  case ":$PATH:" in
    *:"$BIN_DIR":*) ;; # ok
    *) log "PATH does not include $BIN_DIR. Add this to your shell rc:  export PATH=\"$BIN_DIR:\$PATH\"";;
  esac
  if [ "$WRITE_RC" -eq 1 ]; then
    log "[Dry Run] Would append shim source line to your shell rc (bash/zsh preferred, else .profile)"
  fi
  exit 0
fi

# Install
if [ -d "$DEST" ]; then
  if [ "$FORCE" -eq 1 ]; then
    log "Forcing reinstall: removing $DEST"
    rm -rf "$DEST"
  else
    log "Reusing existing label directory: $DEST"
  fi
fi

tmpdir="$(mktemp -d 2>/dev/null || mktemp -d -t zweig)"
trap 'rm -rf "$tmpdir"' EXIT INT TERM

if [ -n "$LOCAL" ]; then
  log "Packaging HEAD ($LOCAL_SHA) from $LOCAL"
  src_dir="$tmpdir/src"
  mkdir -p "$src_dir"
  git -C "$LOCAL" archive HEAD | tar -x -C "$src_dir"
else
  log "Downloading $URL"
  curl -fsSL "$URL" | tar -xz -C "$tmpdir"

  # Move exploded dir to DEST (GitHub tarball creates a single top-level dir)
  src_dir="$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)"
  [ -n "$src_dir" ] || { err "download/extract failed"; exit 1; }
fi

if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi
mkdir -p "$ROOT/versions"
mv "$src_dir" "$DEST"

# Create symlink for 'zg'
ln -sfn "$DEST/bin/zg" "$LINK"
log "Linked $LINK -> $DEST/bin/zg"

# Create stable shim path that tracks current label
mkdir -p "$ROOT/shims"
if [ -f "$DEST/shims/shims.sh" ]; then
  ln -sfn "$DEST/shims/shims.sh" "$ROOT/shims/shims.sh"
  log "Linked $ROOT/shims/shims.sh -> $DEST/shims/shims.sh"
else
  log "Note: shim file not found at $DEST/shims/shims.sh (skipping)."
fi

# Guidance (no RC edits)
case ":$PATH:" in
  *:"$BIN_DIR":*) ;;
  *) log "PATH does not include $BIN_DIR."
     log "Add this to your shell rc and re-source:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

if [ "$WRITE_RC" -eq 1 ]; then
  # shellcheck disable=SC2016 # single-quoted on purpose: expands later, when the rc file is sourced
  add_line='[ -f "$HOME/.local/share/zweig/shims/shims.sh" ] && . "$HOME/.local/share/zweig/shims/shims.sh"'
  appended=0
  # Prefer shell-specific rc files if present
  if [ -n "${BASH_VERSION-}" ] && [ -f "$HOME/.bashrc" ]; then
    if ! grep -Fq "$add_line" "$HOME/.bashrc" 2>/dev/null; then
      printf '\n%s\n' "$add_line" >> "$HOME/.bashrc" && appended=1 && log "Added shim sourcing to ~/.bashrc"
    fi
  fi
  if [ -n "${ZSH_VERSION-}" ] && [ -f "$HOME/.zshrc" ]; then
    if ! grep -Fq "$add_line" "$HOME/.zshrc" 2>/dev/null; then
      printf '\n%s\n' "$add_line" >> "$HOME/.zshrc" && appended=1 && log "Added shim sourcing to ~/.zshrc"
    fi
  fi
  # Fallback to .profile if nothing else matched
  if [ $appended -eq 0 ]; then
    if ! grep -Fq "$add_line" "$HOME/.profile" 2>/dev/null; then
      printf '\n%s\n' "$add_line" >> "$HOME/.profile" && appended=1 && log "Added shim sourcing to ~/.profile"
    fi
  fi
  if [ $appended -eq 0 ]; then
    log "Shim source line already present in your shell rc."
  else
    log "Reload your shell or 'source' your rc file to enable 'zg' cd shim."
  fi
fi

log "✅ Installed Zweig [$LABEL] to $DEST"