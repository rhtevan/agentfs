#!/usr/bin/env bash
# update-soul-links.sh — Manage the OKFGEN CONCEPTS section in SOUL.md files.
#
# Usage: bash update-soul-links.sh <DOTAGENTS_ROOT> <LINKS_CONTENT>
#
# Discovers ALL SOUL.md files under <DOTAGENTS_ROOT>:
#   <root>/SOUL.md                         — default agent
#   <root>/profiles/*/SOUL.md              — named agent profiles
#
# For each SOUL.md found, inserts or updates a managed section between
# marker comments:
#   <!-- OKFGEN CONCEPTS START -->
#   ...content...
#   <!-- OKFGEN CONCEPTS END -->
#
# The LINKS_CONTENT contains relative paths from the SOUL.md's own
# directory to the knowledge bundle. The script automatically adjusts
# path prefixes:
#   - Default agent SOUL.md at <root>/SOUL.md
#     → links use "knowledge/agent-patterns/..."
#   - Profile SOUL.md at <root>/profiles/<name>/SOUL.md
#     → links use "../../knowledge/agent-patterns/..."
#
# If markers already exist, content between them is replaced.
# If markers don't exist, the section is appended at the end.
# If SOUL.md doesn't exist, it is SKIPPED (not created).
#
# Human-authored content outside the markers is NEVER modified.

set -euo pipefail

DOTAGENTS_ROOT="${1:?Usage: update-soul-links.sh <DOTAGENTS_ROOT> <LINKS_CONTENT>}"
LINKS_CONTENT="${2:?Usage: update-soul-links.sh <DOTAGENTS_ROOT> <LINKS_CONTENT>}"
DOTAGENTS_ROOT="$(cd "$DOTAGENTS_ROOT" && pwd)"

START_MARKER="<!-- OKFGEN CONCEPTS START -->"
END_MARKER="<!-- OKFGEN CONCEPTS END -->"

UPDATED=0
SKIPPED=0

# Function: update a single SOUL.md file
update_one_soul() {
  local soul_file="$1"
  local path_prefix="$2"
  local label="$3"

  if [[ ! -f "$soul_file" ]]; then
    echo "  SKIP  $label — file does not exist"
    SKIPPED=$((SKIPPED + 1))
    return
  fi

  # Adjust link paths: replace "knowledge/" with the correct prefix
  local adjusted_content
  adjusted_content="$(echo "$LINKS_CONTENT" | sed "s|knowledge/|${path_prefix}knowledge/|g")"

  if grep -q "$START_MARKER" "$soul_file" && grep -q "$END_MARKER" "$soul_file"; then
    # Replace content between markers
    awk -v start="$START_MARKER" -v end_marker="$END_MARKER" -v content="$adjusted_content" '
      $0 == start {
        print
        print content
        skip = 1
        next
      }
      $0 == end_marker {
        print
        skip = 0
        next
      }
      !skip { print }
    ' "$soul_file" > "$soul_file.tmp"
    mv "$soul_file.tmp" "$soul_file"
    echo "  UPDATE  $label — replaced existing OKFGEN CONCEPTS section"
  else
    # Append the section at the end
    cat >> "$soul_file" << EOF

## Learned Patterns

$START_MARKER
$adjusted_content
$END_MARKER
EOF
    echo "  APPEND  $label — added OKFGEN CONCEPTS section"
  fi

  UPDATED=$((UPDATED + 1))
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Updating SOUL.md files with pattern concept links"
echo "  Root: $DOTAGENTS_ROOT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 1. Default agent SOUL.md (at .agents/ root)
#    Links are relative from .agents/ → knowledge/agent-patterns/
update_one_soul "$DOTAGENTS_ROOT/SOUL.md" "" "default agent"

# 2. Named agent profile SOUL.md files
#    Links are relative from .agents/profiles/<name>/ → ../../knowledge/agent-patterns/
if [[ -d "$DOTAGENTS_ROOT/profiles" ]]; then
  while IFS= read -r -d '' profile_dir; do
    profile_name="$(basename "$profile_dir")"
    update_one_soul "$profile_dir/SOUL.md" "../../" "profile:$profile_name"
  done < <(find "$DOTAGENTS_ROOT/profiles" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -z)
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Updated: $UPDATED    Skipped: $SKIPPED"
echo "═══════════════════════════════════════════════════════════════"
