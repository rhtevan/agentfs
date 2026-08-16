#!/usr/bin/env bash
# checkpoint.sh — Checkpoint and backup for destructive .agents/ operations.
#
# Usage:
#   bash checkpoint.sh create <file1> [file2...]   Record files + hashes
#   bash checkpoint.sh clear                       Remove checkpoint after success
#   bash checkpoint.sh check                       Report non-empty checkpoint
#   bash checkpoint.sh backup <file>               Backup untracked file
#
# Checkpoint file: .agents/.checkpoint (relative to project root)
#
# Exit codes:
#   0 = success
#   1 = checkpoint exists (for 'check'), or error
#   2 = usage error

set -euo pipefail

# ── Find .agents/ root ─────────────────────────────────────────────
find_agents_root() {
  if [[ -d "./.agents" ]]; then
    echo "./.agents"
  elif [[ -d "$HOME/.agents" ]]; then
    echo "$HOME/.agents"
  else
    echo "ERROR: No .agents/ directory found." >&2
    exit 1
  fi
}

AGENTS_ROOT=$(find_agents_root)
CHECKPOINT_FILE="$AGENTS_ROOT/.checkpoint"

# ── Commands ───────────────────────────────────────────────────────
cmd_create() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: checkpoint.sh create <file1> [file2...]" >&2
    exit 2
  fi

  # Write checkpoint with timestamp, files, and hashes
  {
    echo "# Checkpoint created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# Files:"
    for f in "$@"; do
      if [[ -f "$f" ]]; then
        local hash
        hash=$(sha256sum "$f" | awk '{print $1}')
        echo "$f  $hash"
      else
        echo "$f  DOES_NOT_EXIST"
      fi
    done
  } > "$CHECKPOINT_FILE"

  echo "✅ Checkpoint created: $CHECKPOINT_FILE"
  echo "   Files recorded: $#"
}

cmd_clear() {
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    rm -f "$CHECKPOINT_FILE"
    echo "✅ Checkpoint cleared."
  else
    echo "No checkpoint to clear."
  fi
}

cmd_check() {
  if [[ -f "$CHECKPOINT_FILE" ]]; then
    echo "⚠️  Non-empty checkpoint found: $CHECKPOINT_FILE"
    echo ""
    cat "$CHECKPOINT_FILE"
    echo ""
    echo "A previous operation may not have completed."
    echo "Options: resume the operation, or revert affected files."
    exit 1
  else
    echo "✅ No pending checkpoint."
    exit 0
  fi
}

cmd_backup() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: checkpoint.sh backup <file>" >&2
    exit 2
  fi

  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "File does not exist: $file" >&2
    exit 1
  fi

  # Check if file is tracked by git
  local is_tracked=false
  if git ls-files --error-unmatch "$file" &>/dev/null; then
    is_tracked=true
  fi

  if $is_tracked; then
    echo "✅ $file is git-tracked — no backup needed."
  else
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${file}.bak.${timestamp}"
    cp "$file" "$backup_path"
    echo "✅ Backed up untracked file: $file → $backup_path"
  fi
}

# ── Main ───────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: checkpoint.sh {create|clear|check|backup} [args...]" >&2
  exit 2
fi

COMMAND="$1"
shift

case "$COMMAND" in
  create) cmd_create "$@" ;;
  clear)  cmd_clear ;;
  check)  cmd_check ;;
  backup) cmd_backup "$@" ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: checkpoint.sh {create|clear|check|backup} [args...]" >&2
    exit 2
    ;;
esac
