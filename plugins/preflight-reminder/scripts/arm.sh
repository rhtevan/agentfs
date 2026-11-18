#!/usr/bin/env bash
# preflight-reminder: arm the one-shot Pre-Flight reminder for this user turn.
# Called by UserPromptSubmit (every prompt). Re-arming each turn is intended:
# Rule 2 applies per task, and a new prompt is a new task.
set -euo pipefail
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[[ -z "$session_id" ]] && exit 0
mkdir -p /tmp/goose-preflight
echo armed > "/tmp/goose-preflight/${session_id}"
