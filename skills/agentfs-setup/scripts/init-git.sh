#!/usr/bin/env bash
# init-git.sh — Initialize a git repository if not already initialized.
#
# Usage: bash init-git.sh [ROOT_DIR]
#
#   ROOT_DIR   Directory to initialize git in (default: .)
#
# Idempotent — skips if already a git repository.

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

echo "[agentfs-setup] Checking git status in $ROOT"

if git -C "$ROOT" rev-parse --is-inside-work-tree &>/dev/null; then
  echo "  ✓ Already a git repository — skipping git init."
else
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
