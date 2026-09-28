#!/usr/bin/env bash
# signal-dispatch: flag a "hey" dispatch as pending for this session.
# Called by UserPromptSubmit hook when prompt matches ^[Hh]ey .
# Also saves the keywords (everything after "hey ") for the block reason.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
message="$(printf '%s' "$payload" | jq -r '.message // ""')"

dispatch_dir="/tmp/goose-dispatch"
mkdir -p "$dispatch_dir"

# Extract keywords: strip leading "hey " (case-insensitive)
keywords="$(echo "$message" | sed -E 's/^[Hh]ey[[:space:]]+//')"
keywords_lower="$(echo "$keywords" | tr '[:upper:]' '[:lower:]')"

# Check if keywords match a Signal Dispatch table pattern.
# Table-matched signals have explicit routing (memory writes, preference
# saves, rule proposals) — they do NOT need search_nodes enforcement.
# Only unmatched signals (skill dispatch fallthrough) get the flag.
table_match=false
case "$keywords_lower" in
  remember*|note\ *|keep\ in\ mind*)   table_match=true ;;
  forget*|remove*)                       table_match=true ;;
  what\ do\ you\ remember*|check\ your\ notes*) table_match=true ;;
  i\ prefer*|i\ like*|my\ style*)       table_match=true ;;
  always*|never*|this\ is\ a\ rule*)    table_match=true ;;
esac

if [ "$table_match" = false ]; then
  # Unmatched signal — enforce search_nodes first via Rule 2 fallthrough
  echo "pending" > "${dispatch_dir}/${session_id}"
  echo "$keywords" > "${dispatch_dir}/${session_id}.keywords"
fi
