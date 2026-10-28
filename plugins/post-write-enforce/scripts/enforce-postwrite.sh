#!/usr/bin/env bash
# post-write-enforce: block tools when post-write is pending.
# Called by PreToolUse hook for ALL tools.
# Allows shell calls (model might be running post-write.sh).
# Blocks all other tools with a JIT reminder.
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // "unknown"')"

flag_dir="/tmp/goose-postwrite"
flag_file="${flag_dir}/${session_id}"

# No pending post-write — allow everything
[[ ! -f "$flag_file" ]] && exit 0

# Allow shell calls through — model may be running post-write.sh
case "$tool_name" in
  shell|developer__shell)
    exit 0
    ;;
esac

# Allow search_nodes through — don't conflict with signal-dispatch
case "$tool_name" in
  search_nodes|knowledgegraphmemory__search_nodes)
    exit 0
    ;;
esac

# Block other tools — post-write is pending
files="$(cat "$flag_file" | sort -u | head -3 | tr '\n' ', ')"
reason="Post-Write rule: you wrote to .agents/ (${files%,}) but have not run post-write.sh yet. Run: bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh <file> \"<description>\" for each modified file before continuing."

printf '{"decision":"block","reason":"%s"}' "$(echo "$reason" | tr '\n' ' ' | sed 's/"/\\"/g')"
exit 0
