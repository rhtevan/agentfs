#!/usr/bin/env bash
# merge-log-entry.sh — Prepend a new log entry to any log.md file.
#
# Usage: bash merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>
#
# Writes ENTRY_TEXT verbatim under a timestamped ## YYYY-MM-DD HH:MM
# heading. If that heading already exists, appends under it. Otherwise
# creates a new heading above all existing date sections (reverse
# chronological order).
#
# Multiple lines can be passed as a single string with embedded
# newlines (\n). The script interprets \n escape sequences via printf.

set -euo pipefail

LOG_FILE="${1:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
ENTRY_TEXT_RAW="${2:?Usage: merge-log-entry.sh <LOG_FILE> <ENTRY_TEXT>}"
# Interpret \n escape sequences so callers can pass multi-line entries
# as a single argument: "- line1\n- line2"
ENTRY_TEXT="$(printf '%b' "$ENTRY_TEXT_RAW")"
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

# Check if current timestamp heading already exists
if grep -q "^## ${NOW}" "$LOG_FILE"; then
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
