#!/usr/bin/env bash
# signal-dispatch: enforce mandatory search_nodes first when a "hey" prompt is pending.
# Called by PreToolUse hook for ALL tools (no matcher — runs on every tool call).
# Only search_nodes passes through. All other tools (including load_skill) are
# blocked with a one-shot JIT reminder pointing to Rule 2.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"')"

flag="/tmp/goose-dispatch/${session_id}"

# Allow search_nodes through — this is the mandatory first tool per Rule 2
case "$tool_name" in
  search_nodes|knowledgegraphmemory__search_nodes)
    # Clear flag — dispatch is happening correctly
    rm -f "$flag" 2>/dev/null
    rm -f "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null
    exit 0
    ;;
esac

# For all other tools, check if hey dispatch is pending
if [ -f "$flag" ]; then
  rm -f "$flag"
  # Extract the user's keywords (everything after "hey ")
  keywords="$(cat "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null || echo '<keywords>')"
  rm -f "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null

  reason="This tool is not needed yet. The user said: hey ${keywords}. Follow AGENTS.md Rule 2: first tool call MUST be search_nodes with the keywords. You CAN and SHOULD call search_nodes right now."

  printf '{"decision":"block","reason":"%s"}' "$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')"
  exit 0
fi
