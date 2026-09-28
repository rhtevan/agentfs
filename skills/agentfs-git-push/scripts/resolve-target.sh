#!/usr/bin/env bash
# resolve-target.sh — Resolve which git repo(s) to operate on.
#
# Usage: bash resolve-target.sh [EXPLICIT_TARGET]
#
# Output (stdout, machine-readable KEY=VALUE):
#   TARGET=/absolute/path/to/repo
#   CWD_ALSO=true|false
#   CWD_PATH=/absolute/path/to/cwd/repo  (only when CWD_ALSO=true)
#
# Exit codes:
#   0 = resolved successfully
#   1 = resolved target is not a git repo
#   2 = usage error

set -euo pipefail

EXPLICIT="${1:-}"
DEFAULT_TARGET="$HOME/.agents"

# ── Resolve primary target ───────────────────────────────────────────
if [[ -n "$EXPLICIT" ]]; then
  # User specified a target explicitly
  if [[ ! -d "$EXPLICIT" ]]; then
    echo "❌ Target directory does not exist: $EXPLICIT" >&2
    exit 1
  fi
  TARGET="$(cd "$EXPLICIT" && pwd)"
else
  # Default to ~/.agents/
  TARGET="$DEFAULT_TARGET"
fi

# Verify target is a git repo
if ! git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "❌ Not a git repository: $TARGET" >&2
  exit 1
fi

TARGET="$(git -C "$TARGET" rev-parse --show-toplevel)"

# ── Check CWD for uncommitted changes ───────────────────────────────
CWD_ALSO=false
CWD_PATH=""
CWD="$(pwd)"

# Only check CWD if it differs from the resolved target
if [[ "$CWD" != "$TARGET" ]]; then
  # Check if CWD is inside a git repo
  if CWD_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"; then
    if [[ "$CWD_ROOT" != "$TARGET" ]]; then
      # Check for uncommitted changes (staged + unstaged + untracked)
      if [[ -n "$(git -C "$CWD_ROOT" status --porcelain 2>/dev/null)" ]]; then
        CWD_ALSO=true
        CWD_PATH="$CWD_ROOT"
      fi
    fi
  fi
fi

# ── Output ───────────────────────────────────────────────────────────
echo "TARGET=$TARGET"
echo "CWD_ALSO=$CWD_ALSO"
if [[ "$CWD_ALSO" == "true" ]]; then
  echo "CWD_PATH=$CWD_PATH"
fi
