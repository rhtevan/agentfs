#!/usr/bin/env bash
# post-write.sh — Single-call post-write orchestrator for AgentFS files.
#
# Replaces the manual 4-step sequence (merge-log, merge-changelog,
# post-edit, link check) with one invocation per modified file.
#
# Usage:
#   bash post-write.sh <modified-file> "<description>" [--version <ver>]
#
# Arguments:
#   modified-file   Path to the file that was written/edited
#   description     What changed (will be bullet-prefixed if not already)
#   --version <ver> Optional: version string for skill changelog entry
#
# Behaviour:
#   1. Detects scope (USER vs PROJECT vs knowledge bundle)
#   2. Calls merge-log-entry.sh for the correct log(s)
#   3. Calls merge-changelog-entry.sh if file is under skills/*/ and --version given
#   4. Calls post-edit.sh for the detected scope
#
# Self-referential files (log.md, CHANGELOG.md, index.md) are skipped
# to avoid infinite loops or noise from auto-generated content.
#
# Exit codes:
#   0 = success
#   1 = error (bad args, path not under .agents/)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse args ─────────────────────────────────────────────────────
MODIFIED_FILE="${1:?Usage: post-write.sh <modified-file> \"<description>\" [--version <ver>]}"
DESCRIPTION="${2:?Usage: post-write.sh <modified-file> \"<description>\" [--version <ver>]}"
VERSION=""

shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?--version requires a value}"; shift 2 ;;
    *) echo "[post-write] Unknown arg: $1"; exit 1 ;;
  esac
done

# ── Normalize path ─────────────────────────────────────────────────
# Resolve to absolute for reliable prefix matching
ABS_FILE="$(realpath -m "$MODIFIED_FILE")"
USER_ROOT="$(realpath -m "${HOME}/.agents")"
# PROJECT_ROOT is relative to cwd
PROJECT_ROOT="$(realpath -m "./.agents")"

# ── Skip self-referential files ────────────────────────────────────
BASENAME="$(basename "$ABS_FILE")"
case "$BASENAME" in
  log.md)
    echo "[post-write] Skipping self-referential file: $BASENAME"
    exit 0
    ;;
  CHANGELOG.md)
    echo "[post-write] Skipping self-referential file: $BASENAME"
    exit 0
    ;;
  index.md)
    echo "[post-write] Skipping auto-generated file: $BASENAME"
    exit 0
    ;;
esac

# ── Scope detection ───────────────────────────────────────────────
SCOPE=""
LOGS=()
POST_EDIT_FLAG=""

if [[ "$ABS_FILE" == "$USER_ROOT/knowledge/"* ]]; then
  # Knowledge bundle — triple-log
  SCOPE="USER/knowledge"
  # Extract bundle name: ~/.agents/knowledge/<bundle>/...
  BUNDLE_REL="${ABS_FILE#"$USER_ROOT/knowledge/"}"
  BUNDLE_NAME="${BUNDLE_REL%%/*}"
  BUNDLE_LOG="$USER_ROOT/knowledge/$BUNDLE_NAME/log.md"
  KNOWLEDGE_LOG="$USER_ROOT/knowledge/log.md"

  LOGS+=("$BUNDLE_LOG")
  # Only add knowledge log if it's a different file than bundle log
  if [[ "$BUNDLE_LOG" != "$KNOWLEDGE_LOG" ]]; then
    LOGS+=("$KNOWLEDGE_LOG")
  fi
  LOGS+=("$USER_ROOT/log.md")
  POST_EDIT_FLAG="--user"

elif [[ "$ABS_FILE" == "$USER_ROOT/"* ]]; then
  SCOPE="USER"
  LOGS+=("$USER_ROOT/log.md")
  POST_EDIT_FLAG="--user"

elif [[ "$ABS_FILE" == "$PROJECT_ROOT/"* ]]; then
  SCOPE="PROJECT"
  LOGS+=("$PROJECT_ROOT/log.md")
  POST_EDIT_FLAG="--project"

else
  echo "[post-write] ERROR: $MODIFIED_FILE is not under .agents/ or ~/.agents/"
  exit 1
fi

# ── Prepare descriptions ───────────────────────────────────────────
# Log entries include the relative filename for traceability.
# Format: "- <description> (<relative-path>)"
# This ensures batch invocations with the same description still
# produce distinguishable log entries.

# Build a short relative path for the log entry
REL_PATH=""
if [[ "$ABS_FILE" == "$USER_ROOT/"* ]]; then
  REL_PATH="${ABS_FILE#"$USER_ROOT/"}"
elif [[ "$ABS_FILE" == "$PROJECT_ROOT/"* ]]; then
  REL_PATH="${ABS_FILE#"$PROJECT_ROOT/"}"
else
  REL_PATH="$BASENAME"
fi

LOG_DESCRIPTION="$DESCRIPTION"
if [[ "$LOG_DESCRIPTION" != "- "* ]]; then
  LOG_DESCRIPTION="- $DESCRIPTION"
fi
# Append relative path if not already present in the description
if [[ "$LOG_DESCRIPTION" != *"$REL_PATH"* ]] && [[ "$LOG_DESCRIPTION" != *"$BASENAME"* ]]; then
  LOG_DESCRIPTION="$LOG_DESCRIPTION ($REL_PATH)"
fi
# Strip bullet prefix for changelog (table row, not a list)
CHANGELOG_DESCRIPTION="${DESCRIPTION#- }"

# ── Step 1: Log entries ────────────────────────────────────────────
for log in "${LOGS[@]}"; do
  # Ensure parent directory exists (knowledge bundle logs may not exist yet)
  log_dir="$(dirname "$log")"
  if [[ ! -d "$log_dir" ]]; then
    echo "[post-write] Skipping log $log (parent dir does not exist)"
    continue
  fi
  echo "[post-write] Logging to $log"
  bash "$SCRIPT_DIR/merge-log-entry.sh" "$log" "$LOG_DESCRIPTION"
done

# ── Step 2: Changelog (if skill + version provided) ───────────────
# Detect if file is under a skills/*/ directory
SKILL_DIR=""
if [[ "$ABS_FILE" == */skills/*/* ]]; then
  # Extract the skill directory path
  # e.g., ~/.agents/skills/my-skill/scripts/foo.sh → ~/.agents/skills/my-skill
  REMAINDER="${ABS_FILE#*skills/}"
  SKILL_NAME="${REMAINDER%%/*}"
  if [[ "$ABS_FILE" == "$USER_ROOT/"* ]]; then
    SKILL_DIR="$USER_ROOT/skills/$SKILL_NAME"
  else
    SKILL_DIR="$PROJECT_ROOT/skills/$SKILL_NAME"
  fi
fi

if [[ -n "$SKILL_DIR" ]]; then
  if [[ -n "$VERSION" ]]; then
    echo "[post-write] Updating changelog: $SKILL_DIR/CHANGELOG.md v$VERSION"
    bash "$SCRIPT_DIR/merge-changelog-entry.sh" "$SKILL_DIR/CHANGELOG.md" "$VERSION" "$CHANGELOG_DESCRIPTION"
  else
    echo "[post-write] ⚠️  Skill file modified ($SKILL_DIR) but no --version provided — skipping changelog"
  fi
fi

# ── Step 3: Post-edit checks ──────────────────────────────────────
echo "[post-write] Running post-edit checks ($POST_EDIT_FLAG)"
bash "$SCRIPT_DIR/post-edit.sh" "$POST_EDIT_FLAG"

echo "[post-write] ✓ Complete (scope: $SCOPE)"
