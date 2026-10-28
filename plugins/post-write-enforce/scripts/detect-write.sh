#!/usr/bin/env bash
# post-write-enforce: detect writes to .agents/ paths and set pending flag.
# Called by AfterFileEdit (matcher: .agents/) and PostToolUse (matcher: ^write$).
#
# Exempt files: log.md, CHANGELOG.md, index.md (auto-generated, no post-write needed)
set -euo pipefail

payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id')"
event="$(printf '%s' "$payload" | jq -r '.event // ""')"

# Get the file path from the event
file_path=""
if [[ "$event" == "AfterFileEdit" ]]; then
  # AfterFileEdit: path is in tool_input
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.path // ""')"
elif [[ "$event" == "PostToolUse" ]]; then
  # PostToolUse for write tool: path is in tool_input
  file_path="$(printf '%s' "$payload" | jq -r '.tool_input.path // ""')"
fi

# Only flag if path contains .agents/
case "$file_path" in
  *.agents/*) ;;
  *) exit 0 ;;
esac

# Exempt auto-generated files
basename="$(basename "$file_path")"
case "$basename" in
  log.md|CHANGELOG.md|index.md) exit 0 ;;
esac

# Set pending flag
flag_dir="/tmp/goose-postwrite"
mkdir -p "$flag_dir"
echo "$file_path" >> "${flag_dir}/${session_id}"
