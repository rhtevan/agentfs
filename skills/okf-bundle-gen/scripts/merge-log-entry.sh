#!/usr/bin/env bash
# merge-log-entry.sh — Prepend a new log entry to an OKF log.md file.
#
# Usage: bash merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>
#
# If today's date heading already exists at the top of the log, the new
# entry lines are inserted under it. Otherwise a new date section is
# created above all existing date sections (reverse chronological order).
#
# ENTRY_TEXT should be one or more bullet lines, e.g.:
#   "* **Creation**: Generated 5 concept docs from session context."
#
# Multiple lines can be passed as a single string with embedded newlines.

set -euo pipefail

LOG_FILE="${1:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
ENTRY_TEXT="${2:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
NOW="$(date '+%Y-%m-%d %H:%M')"

if [[ ! -f "$LOG_FILE" ]]; then
  # Create fresh log.md
  cat > "$LOG_FILE" << EOF
# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## ${NOW}

${ENTRY_TEXT}
EOF
  echo "Created $LOG_FILE with current entry."
  exit 0
fi

# Read existing log
EXISTING="$(cat "$LOG_FILE")"

# Check if current timestamp heading already exists
if echo "$EXISTING" | grep -q "^## ${NOW}"; then
  # Heading exists — insert new entries right after it
  awk -v heading="## ${NOW}" -v entry="$ENTRY_TEXT" '
    $0 == heading {
      print
      print entry
      next
    }
    { print }
  ' "$LOG_FILE" > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" "$LOG_FILE"
  echo "Appended entries under existing ## ${NOW} heading."
else
  # Heading does not exist — insert new section after the
  # "# Directory Update Log" heading (and any comment/blank lines after it)
  {
    echo "# Directory Update Log"
    echo ""
    # Preserve the comment line if it exists
    if head -3 "$LOG_FILE" | grep -q '<!-- Append-only'; then
      echo "<!-- Append-only. Newest entries at top. -->"
      echo ""
    fi
    echo "## ${NOW}"
    echo ""
    echo "$ENTRY_TEXT"
    echo ""
    # Skip the original heading + comment + trailing blank lines, keep the rest
    awk '
      BEGIN { skip=1 }
      skip && /^#[^#]/ { next }
      skip && /^<!--/ { next }
      skip && /^[[:space:]]*$/ { next }
      { skip=0; print }
    ' "$LOG_FILE"
  } > "$LOG_FILE.tmp"
  mv "$LOG_FILE.tmp" "$LOG_FILE"
  echo "Inserted new ## ${NOW} section at top of log."
fi
