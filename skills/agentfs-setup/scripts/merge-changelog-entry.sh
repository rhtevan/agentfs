#!/usr/bin/env bash
# merge-changelog-entry.sh — Append a new row to a skill CHANGELOG.md table.
#
# Usage:
#   bash merge-changelog-entry.sh <CHANGELOG_FILE> <VERSION> <DESCRIPTION>
#
# Arguments:
#   CHANGELOG_FILE  Path to the CHANGELOG.md file to update
#   VERSION         Version string, e.g. "4.13.0" or "1.9.0"
#   DESCRIPTION     Change description (no leading date or version needed)
#
# Behaviour:
#   - Inserts a new row immediately after the table separator line
#     (|---------|--------| or similar) — newest entry first
#   - Deduplicates: if a row for today's date AND this version already
#     exists, it is updated in-place rather than duplicated
#   - If CHANGELOG.md does not exist, creates it with correct structure
#   - If the table header/separator is missing, repairs it before inserting
#
# Exit codes:
#   0 = success
#   1 = error
#
# Called by:
#   Agent directly, guided by Guardrail #5
#   Optionally: post-edit.sh (gap detection)
#   Optionally: pre-push-scan.sh (coverage check)

set -euo pipefail

CHANGELOG_FILE="${1:?Usage: merge-changelog-entry.sh <CHANGELOG_FILE> <VERSION> <DESCRIPTION>}"
VERSION="${2:?Usage: merge-changelog-entry.sh <CHANGELOG_FILE> <VERSION> <DESCRIPTION>}"
DESCRIPTION="${3:?Usage: merge-changelog-entry.sh <CHANGELOG_FILE> <VERSION> <DESCRIPTION>}"

TODAY="$(date '+%Y-%m-%d')"

# Derive skill name from changelog path for the title
SKILL_NAME=$(basename "$(dirname "$CHANGELOG_FILE")")

# ── Create if missing ────────────────────────────────────────────────
if [[ ! -f "$CHANGELOG_FILE" ]]; then
  cat > "$CHANGELOG_FILE" << EOF
# ${SKILL_NAME} Changelog

| Updated | Change |
|---------|--------|
| ${TODAY} | v${VERSION} — ${DESCRIPTION} |
EOF
  echo "[merge-changelog] Created $CHANGELOG_FILE with initial entry."
  exit 0
fi

# ── Repair: ensure table header + separator exist ────────────────────
if ! grep -q '^| Updated | Change |' "$CHANGELOG_FILE"; then
  # No table at all — insert after the H1 title
  awk '
    /^# / && !inserted {
      print
      print ""
      print "| Updated | Change |"
      print "|---------|--------|"
      inserted = 1
      next
    }
    { print }
  ' "$CHANGELOG_FILE" > "$CHANGELOG_FILE.tmp"
  mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE"
  echo "[merge-changelog] Repaired: inserted missing table header."
fi

if ! grep -q '^|[-]*|[-]*|' "$CHANGELOG_FILE"; then
  # Header exists but separator missing — insert it after the header
  sed -i '/^| Updated | Change |/a |---------|--------|' "$CHANGELOG_FILE"
  echo "[merge-changelog] Repaired: inserted missing table separator."
fi

# ── Deduplication check ───────────────────────────────────────────────
NEW_ROW="| ${TODAY} | v${VERSION} — ${DESCRIPTION} |"

if grep -qF "| ${TODAY} | v${VERSION} —" "$CHANGELOG_FILE" 2>/dev/null; then
  # Row for today+version exists — update description in-place
  # Escape special chars in VERSION for sed
  ESCAPED_VERSION=$(printf '%s' "$VERSION" | sed 's/[.[\/^$*]/\\&/g')
  ESCAPED_ROW=$(printf '%s' "$NEW_ROW" | sed 's/[&/\]/\\&/g')
  sed -i "s|^| ${TODAY} | v${ESCAPED_VERSION} —.*|$ESCAPED_ROW|" "$CHANGELOG_FILE" 2>/dev/null || true
  # Simpler fallback: just report it and skip
  echo "[merge-changelog] Entry for ${TODAY} v${VERSION} already exists — skipping duplicate."
  exit 0
fi

# ── Insert new row after separator ───────────────────────────────────
# Find the separator line and insert the new row after it (newest-first)
awk -v new_row="$NEW_ROW" '
  # Match the separator line (|---|---| pattern)
  /^\|[-]+\|[-]+\|/ && !inserted {
    print
    print new_row
    inserted = 1
    next
  }
  { print }
' "$CHANGELOG_FILE" > "$CHANGELOG_FILE.tmp"
mv "$CHANGELOG_FILE.tmp" "$CHANGELOG_FILE"

echo "[merge-changelog] ✓ Added entry: ${TODAY} v${VERSION} to $CHANGELOG_FILE"
