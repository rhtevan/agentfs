#!/usr/bin/env bash
# signal-dispatch: enforce mandatory search_nodes first when a "hey" prompt is pending.
# Called by PreToolUse hook for ALL tools (no matcher — runs on every tool call).
# Only search_nodes passes through. All other tools (including load_skill) are
# blocked with a one-shot JIT reminder pointing to the Signal Dispatch rule.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"')"

flag="/tmp/goose-dispatch/${session_id}"

# KGM tool name from the AgentFS contract (goose derives the prefix from the
# extension's display name). Contract missing -> accept any *__search_nodes
# rather than block dispatch.
KGM_SEARCH_TOOL=""
# shellcheck source=/dev/null
source "$HOME/.agents/scripts/agentfs-contract.sh" 2>/dev/null || true
allow_any_prefix=false; [[ -z "$KGM_SEARCH_TOOL" ]] && allow_any_prefix=true

clear_dispatch() {
  rm -f "$flag" "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null || true
}

# Allow search_nodes through — mandatory first tool per Signal Dispatch rule
if [[ "$tool_name" == "search_nodes" || "$tool_name" == "$KGM_SEARCH_TOOL" ]] \
   || { $allow_any_prefix && [[ "$tool_name" == *__search_nodes ]]; }; then
  clear_dispatch   # dispatch is happening correctly
  exit 0
fi

# search_nodes under a different prefix while a dispatch is pending: the KGM
# extension's display name changed. Block once with the cause and the fix.
if [[ "$tool_name" == *__search_nodes && -f "$flag" ]]; then
  clear_dispatch
  reason="KGM tool name mismatch: '${tool_name}' is not the AgentFS knowledge index tool '${KGM_SEARCH_TOOL}'. goose derives the tool prefix from the KGM extension's name field. Tell the user: set name: \"${KGM_EXT_NAME}\" under extensions.${KGM_EXT_KEY} in ~/.config/goose/config.yaml and restart goose (check: bash ~/.agents/skills/goose-kgm/scripts/status-kgm.sh). Then continue the task without dispatch."
  printf '{"decision":"block","reason":"%s"}' "$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')"
  exit 0
fi

# For all other tools, check if hey dispatch is pending
if [ -f "$flag" ]; then
  rm -f "$flag"
  # Extract the user's keywords (everything after "hey ")
  keywords="$(cat "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null || echo '<keywords>')"
  rm -f "/tmp/goose-dispatch/${session_id}.keywords" 2>/dev/null

  reason="This tool is not needed yet. The user said: hey ${keywords}. Follow the Signal Dispatch rule in AGENTS.md: first tool call MUST be search_nodes with the keywords. You CAN and SHOULD call search_nodes right now."

  printf '{"decision":"block","reason":"%s"}' "$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')"
  exit 0
fi
