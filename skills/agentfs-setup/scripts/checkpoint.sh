#!/usr/bin/env bash
# checkpoint.sh — Checkpoint and backup for destructive .agents/ operations.
#
# Usage:
#   bash checkpoint.sh create <file1> [file2...]   Record files + hashes
#   bash checkpoint.sh clear  [--root DIR]         Remove checkpoint(s) after success
#   bash checkpoint.sh check  [--root DIR]         Report pending checkpoint(s)
#   bash checkpoint.sh backup <file>               Backup untracked file
#
# Checkpoint location (independent of the caller's cwd for create):
#   create  → <root>/.checkpoint, where <root> is the nearest ancestor
#             directory named ".agents" of each file's absolute path.
#             Files outside any .agents/ fall back to ./.agents, then
#             ~/.agents. Files spanning several roots get one checkpoint
#             per root (each lists only its own files).
#   clear / check → every candidate root: ./.agents and ~/.agents
#             (deduplicated), or only DIR with --root.
#   Paths are recorded absolute, so 'check' output is valid from any cwd.
#
# Exit codes:
#   0 = success
#   1 = checkpoint exists (for 'check'), or error
#   2 = usage error

set -euo pipefail

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
else
  trace_step() { echo "[trace] $*" >&2; }
fi

# ── Root resolution ────────────────────────────────────────────────
# Fallback root for files outside any .agents/ (old behaviour)
fallback_root() {
  if [[ -d "./.agents" ]]; then
    realpath "./.agents"
  elif [[ -d "$HOME/.agents" ]]; then
    realpath "$HOME/.agents"
  else
    echo "ERROR: No .agents/ directory found." >&2
    exit 1
  fi
}

# Nearest ancestor named .agents of an absolute path (empty if none)
root_of() {
  local d
  d=$(dirname "$1")
  while [[ "$d" != "/" && -n "$d" ]]; do
    if [[ "$(basename "$d")" == ".agents" && -d "$d" ]]; then
      echo "$d"
      return
    fi
    d=$(dirname "$d")
  done
}

# Candidate roots for clear/check
candidate_roots() {
  local seen="" r
  for r in "./.agents" "$HOME/.agents"; do
    [[ -d "$r" ]] || continue
    r=$(realpath "$r")
    [[ " $seen " == *" $r "* ]] && continue
    seen="$seen $r"
    echo "$r"
  done
}

parse_root_opt() {
  ROOTS=()
  if [[ $# -ge 1 ]]; then
    if [[ "$1" == "--root" && $# -eq 2 ]]; then
      [[ -d "$2" ]] || { echo "ERROR: --root $2: not a directory" >&2; exit 1; }
      ROOTS=("$(realpath "$2")")
      return
    fi
    echo "Usage: checkpoint.sh {clear|check} [--root DIR]" >&2
    exit 2
  fi
  mapfile -t ROOTS < <(candidate_roots)
}

# ── Commands ───────────────────────────────────────────────────────
cmd_create() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: checkpoint.sh create <file1> [file2...]" >&2
    exit 2
  fi

  # Group absolute paths by root
  declare -A by_root=()
  local f abs root fb=""
  for f in "$@"; do
    abs=$(realpath -m -- "$f")
    root=$(root_of "$abs")
    if [[ -z "$root" ]]; then
      [[ -n "$fb" ]] || fb=$(fallback_root)
      root="$fb"
    fi
    by_root["$root"]+="$abs"$'\n'
  done

  local stamp n
  stamp=$(date '+%Y-%m-%d %H:%M:%S')
  for root in "${!by_root[@]}"; do
    n=0
    {
      echo "# Checkpoint created: $stamp"
      echo "# Created from: $(pwd)"
      echo "# Files:"
      while IFS= read -r abs; do
        [[ -n "$abs" ]] || continue
        n=$((n + 1))
        if [[ -f "$abs" ]]; then
          echo "$abs  $(sha256sum "$abs" | awk '{print $1}')"
        else
          echo "$abs  DOES_NOT_EXIST"
        fi
      done <<< "${by_root[$root]}"
    } > "$root/.checkpoint"
    echo "✅ Checkpoint created: $root/.checkpoint"
  done
  echo "   Files recorded: $#"
}

cmd_clear() {
  parse_root_opt "$@"
  local r cleared=0
  for r in "${ROOTS[@]}"; do
    if [[ -f "$r/.checkpoint" ]]; then
      rm -f "$r/.checkpoint"
      echo "✅ Checkpoint cleared: $r/.checkpoint"
      cleared=$((cleared + 1))
    fi
  done
  [[ $cleared -gt 0 ]] || echo "No checkpoint to clear (looked in: ${ROOTS[*]:-none})."
}

cmd_check() {
  parse_root_opt "$@"
  local r found=0
  for r in "${ROOTS[@]}"; do
    if [[ -f "$r/.checkpoint" ]]; then
      echo "⚠️  Non-empty checkpoint found: $r/.checkpoint"
      echo ""
      cat "$r/.checkpoint"
      echo ""
      found=$((found + 1))
    fi
  done
  if [[ $found -gt 0 ]]; then
    echo "A previous operation may not have completed."
    echo "Options: resume the operation, or revert affected files."
    exit 1
  fi
  echo "✅ No pending checkpoint."
  exit 0
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

  # Check if file is tracked by git (run git from the file's directory)
  local is_tracked=false
  if git -C "$(dirname "$file")" ls-files --error-unmatch "$(basename "$file")" &>/dev/null; then
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
  clear)  cmd_clear "$@" ;;
  check)  cmd_check "$@" ;;
  backup) cmd_backup "$@" ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: checkpoint.sh {create|clear|check|backup} [args...]" >&2
    exit 2
    ;;
esac
