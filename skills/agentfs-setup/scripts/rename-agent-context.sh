#!/usr/bin/env bash
# rename-agent-context.sh — Rename the agent-specific context file to AGENTS.md.
#
# Usage: bash rename-agent-context.sh [PROJECT_ROOT]
#
# This script is for PROJECT mode only.
#
# After `specify init --integration <agent>`, the CLI may create a file like
# CLAUDE.md, COPILOT.md, GEMINI.md, etc. This script finds that file and
# renames it to AGENTS.md (the vendor-neutral DotAgents convention).
#
# If AGENTS.md already exists (e.g., from seed-agents-md.sh), the content
# from the agent-specific file is merged into it.

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"

KNOWN_AGENT_FILES=(
  "CLAUDE.md"
  "COPILOT.md"
  "GEMINI.md"
  "CURSOR.md"
  "CODEX.md"
  "GOOSE.md"
)

AGENTS_FILE="$ROOT/AGENTS.md"
FOUND=""

for af in "${KNOWN_AGENT_FILES[@]}"; do
  if [[ -f "$ROOT/$af" ]]; then
    FOUND="$ROOT/$af"
    break
  fi
done

if [[ -z "$FOUND" ]]; then
  echo "[agentfs-setup] No agent-specific context file found to rename."
  echo "  (Checked: ${KNOWN_AGENT_FILES[*]})"
  echo "  If AGENTS.md already exists, nothing to do."
  exit 0
fi

FOUND_NAME="$(basename "$FOUND")"

if [[ -f "$AGENTS_FILE" ]]; then
  # AGENTS.md exists — merge the agent file content into it
  echo "[agentfs-setup] AGENTS.md already exists. Merging $FOUND_NAME content."

  if grep -q '<!-- SPECKIT START -->' "$AGENTS_FILE"; then
    # Extract content between SPECKIT markers from the agent file (if any)
    if grep -q '<!-- SPECKIT START -->' "$FOUND"; then
      # Extract the SPECKIT block (markers inclusive) from the agent file
      SPECKIT_CONTENT=$(sed -n '/<!-- SPECKIT START -->/,/<!-- SPECKIT END -->/p' "$FOUND")
      # Use awk to replace the SPECKIT block in AGENTS.md — sed's c\ command
      # cannot handle multi-line replacement text containing regex metacharacters
      awk -v replacement="$SPECKIT_CONTENT" '
        /<!-- SPECKIT START -->/ { printing=1; print replacement; next }
        /<!-- SPECKIT END -->/   { printing=0; next }
        !printing { print }
      ' "$AGENTS_FILE" > "${AGENTS_FILE}.tmp" && mv "${AGENTS_FILE}.tmp" "$AGENTS_FILE"
      echo "  ✓ Merged SPECKIT block from $FOUND_NAME into AGENTS.md"
    fi
  else
    # No markers in AGENTS.md — append entire agent file content
    printf '\n---\n\n' >> "$AGENTS_FILE"
    cat "$FOUND" >> "$AGENTS_FILE"
    echo "  ✓ Appended $FOUND_NAME content to AGENTS.md"
  fi

  # Remove the original agent file
  rm "$FOUND"
  echo "  ✓ Removed $FOUND_NAME"

  # Append to .agents/log.md
  LOG_FILE="$ROOT/.agents/log.md"
  if [[ -f "$LOG_FILE" ]]; then
    NOW=$(date '+%Y-%m-%d %H:%M')
    ENTRY="- Merged \`$FOUND_NAME\` into AGENTS.md and removed the original."
    if grep -q "^## $NOW" "$LOG_FILE"; then
      sed -i "/^## $NOW$/a\\$ENTRY" "$LOG_FILE"
    else
      sed -i "3a\\\\n## $NOW\\n\\n$ENTRY" "$LOG_FILE"
    fi
  fi
else
  # No AGENTS.md — simple rename
  mv "$FOUND" "$AGENTS_FILE"
  echo "[agentfs-setup] Renamed $FOUND_NAME → AGENTS.md"

  # Append to .agents/log.md
  LOG_FILE="$ROOT/.agents/log.md"
  if [[ -f "$LOG_FILE" ]]; then
    NOW=$(date '+%Y-%m-%d %H:%M')
    ENTRY="- Renamed \`$FOUND_NAME\` → AGENTS.md."
    if grep -q "^## $NOW" "$LOG_FILE"; then
      sed -i "/^## $NOW$/a\\$ENTRY" "$LOG_FILE"
    else
      sed -i "3a\\\\n## $NOW\\n\\n$ENTRY" "$LOG_FILE"
    fi
  fi
fi
