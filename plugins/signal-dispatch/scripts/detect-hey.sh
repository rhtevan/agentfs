#!/usr/bin/env bash
# signal-dispatch: flag a "hey" dispatch as pending for this session.
# Called by UserPromptSubmit hook when prompt matches ^[Hh]ey .
# Also saves the keywords (everything after "hey ") for the block reason.
#
# Reads table-matched patterns from patterns.txt (single source of truth).
# If keywords match a pattern → Path A (no flag, model handles directly).
# If no match → Path B (flag set, enforce search_nodes via Signal Dispatch rule).
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
message="$(printf '%s' "$payload" | jq -r '.message // ""')"

dispatch_dir="/tmp/goose-dispatch"
mkdir -p "$dispatch_dir"

# Extract keywords: strip leading "hey " (case-insensitive)
keywords="$(echo "$message" | sed -E 's/^[Hh]ey[[:space:]]+//')"
keywords_lower="$(echo "$keywords" | tr '[:upper:]' '[:lower:]')"

# Load table-matched patterns from patterns.txt
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="$SCRIPT_DIR/../patterns.txt"

table_match=false
if [[ -f "$PATTERNS_FILE" ]]; then
  while IFS='|' read -r prefix _action; do
    # Skip comments and empty lines
    [[ -z "$prefix" || "$prefix" =~ ^# ]] && continue
    # Trim whitespace
    prefix="$(echo "$prefix" | sed 's/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
    # Match if keywords start with this prefix
    if [[ "$keywords_lower" == "$prefix"* ]]; then
      table_match=true
      break
    fi
  done < "$PATTERNS_FILE"
else
  echo "[signal-dispatch] WARNING: patterns.txt not found at $PATTERNS_FILE" >&2
fi

if [ "$table_match" = false ]; then
  # Unmatched signal — enforce search_nodes first via Signal Dispatch rule
  echo "pending" > "${dispatch_dir}/${session_id}"
  echo "$keywords" > "${dispatch_dir}/${session_id}.keywords"
fi
