#!/usr/bin/env bash
# scan-memories.sh — Discover and display all MEMORY.md and USER.md files
#                    under the .agents/ directory tree.
#
# Usage: bash scan-memories.sh <DOTAGENTS_ROOT>
#
# Scans:
#   <root>/memories/MEMORY.md         — default agent
#   <root>/memories/USER.md           — default agent
#   <root>/profiles/*/memories/MEMORY.md  — named agent profiles
#   <root>/profiles/*/memories/USER.md    — named agent profiles
#
# For each file found, prints the source (default or profile name),
# the file type (MEMORY or USER), and the §-delimited entries parsed
# into numbered lines.
#
# Output is designed for the agent to read and use as input for
# pattern extraction — structured, parseable, and complete.

set -euo pipefail

DOTAGENTS_ROOT="${1:?Usage: scan-memories.sh <DOTAGENTS_ROOT>}"
DOTAGENTS_ROOT="$(cd "$DOTAGENTS_ROOT" && pwd)"

echo "═══════════════════════════════════════════════════════════════"
echo "  Memory Scan"
echo "  Root: $DOTAGENTS_ROOT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TOTAL_FILES=0
TOTAL_ENTRIES=0

# Function: parse and display a memory file
display_memory_file() {
  local filepath="$1"
  local source_label="$2"
  local file_type="$3"

  if [[ ! -f "$filepath" ]]; then
    return
  fi

  local content
  content="$(cat "$filepath")"

  # Skip empty files
  [[ -z "$(echo "$content" | tr -d '[:space:]')" ]] && return

  TOTAL_FILES=$((TOTAL_FILES + 1))

  echo "── $file_type ($source_label) ──"
  echo "   File: ${filepath#$DOTAGENTS_ROOT/}"
  echo ""

  # Parse §-delimited entries
  local entry_num=0
  local IFS_BAK="$IFS"

  # Split on § character, handling multiline entries
  while IFS= read -r entry; do
    # Trim whitespace
    entry="$(echo "$entry" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    [[ -z "$entry" ]] && continue
    entry_num=$((entry_num + 1))
    TOTAL_ENTRIES=$((TOTAL_ENTRIES + 1))
    echo "   [$entry_num] $entry"
  done <<< "$(echo "$content" | awk -v RS='§' '{gsub(/^\n+|\n+$/, ""); if (NF) print}')"

  IFS="$IFS_BAK"
  echo ""
}

# 1. Default agent memories
display_memory_file "$DOTAGENTS_ROOT/memories/MEMORY.md" "default-agent" "MEMORY"
display_memory_file "$DOTAGENTS_ROOT/memories/USER.md" "default-agent" "USER"

# 2. Named agent profile memories
if [[ -d "$DOTAGENTS_ROOT/profiles" ]]; then
  while IFS= read -r -d '' profile_dir; do
    profile_name="$(basename "$profile_dir")"
    display_memory_file "$profile_dir/memories/MEMORY.md" "profile:$profile_name" "MEMORY"
    display_memory_file "$profile_dir/memories/USER.md" "profile:$profile_name" "USER"
  done < <(find "$DOTAGENTS_ROOT/profiles" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

# Summary
echo "═══════════════════════════════════════════════════════════════"
echo "  Total files scanned: $TOTAL_FILES"
echo "  Total entries found: $TOTAL_ENTRIES"
echo "═══════════════════════════════════════════════════════════════"
