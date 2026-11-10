#!/usr/bin/env bash
# init-git.sh — Initialize a git repository if not already initialized.
#
# Usage: bash init-git.sh [ROOT_DIR]
#
#   ROOT_DIR   Directory to initialize git in (default: .)
#
# Idempotent — skips if already a git repository.

set -euo pipefail

DRY_RUN=false
CHANGES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in --dry-run|--check) ;; *) POSITIONAL+=("$arg") ;; esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
else
  trace_step() { echo "[trace] $*" >&2; }
fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

echo "[agentfs-setup] Checking git status in $ROOT"

if git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  echo "  ✓ Already a git repository — skipping git init."
  if $DRY_RUN; then echo "DRY_RUN_RESULT=CONVERGED"; fi
else
  if $DRY_RUN; then
    echo "[dry-run] WOULD: Initialize git repository in $ROOT"
    CHANGES=$((CHANGES + 1))
    [[ ! -f "$ROOT/.gitignore" ]] && { echo "[dry-run] WOULD: Create .gitignore"; CHANGES=$((CHANGES + 1)); }
    echo "DRY_RUN_RESULT=PENDING"
    echo "Changes: ${CHANGES}"
    exit 0
  fi
  git -C "$ROOT" init
  echo "  ✓ Initialized new git repository in $ROOT"

  # Create a minimal .gitignore if one doesn't exist
  if [[ ! -f "$ROOT/.gitignore" ]]; then
    cat > "$ROOT/.gitignore" << 'EOF'
# OS
.DS_Store
Thumbs.db

# Editor
*.swp
*.swo
*~
.idea/
.vscode/

# Agent checkpoint files (eval-managed, transient)
.agents/.checkpoint
.agents/.session-marker
EOF
    echo "  ✓ Created .gitignore"
  fi
fi
