#!/usr/bin/env bash
# preflight-reminder: arm the one-shot Pre-Flight reminder for this user turn.
# Called by UserPromptSubmit (every prompt). Re-arming each turn is intended:
# Rule 2 applies per task, and a new prompt is a new task.
set -euo pipefail
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[[ -z "$session_id" ]] && exit 0
mkdir -p /tmp/goose-preflight
flag="/tmp/goose-preflight/${session_id}"
# 1.2.0: a reply that follows a Pre-Flight hold is the approval. goose appends
# "Do not retry; this is a policy denial" to every hook denial, so a model that
# obeys it stops after writing the plan. Re-arming here would block the
# approved change again (loop). Models that retry in the same turn already
# cleared the flag, so they are unaffected.
# 1.3.0: a short approval reply ("yes", "go", ...) approves a plan the model
# proposed in a turn that made no change (so no hold was recorded). Exact
# match only; longer messages are new tasks and arm the reminder. A false
# match skips one reminder (fail-open).
message="$(printf '%s' "$payload" | jq -r '.message // empty')"
norm="$(printf '%s' "$message" | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[[:punct:]]+/ /g; s/(^| )please( |$)/ /g; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
if [[ "$(cat "$flag" 2>/dev/null || true)" == blocked* ]]; then
  rm -f "$flag"
elif [[ "$norm" =~ ^(yes|y|yep|go|go ahead|ok|okay|approve|approved|proceed|do it|apply|lgtm|sure)$ ]] \
  || [[ "$norm" =~ ^(option )?([a-e]|[1-5])$ ]]; then
  # 1.3.1: an option pick ("A", "b.", "Option 2") answers a choice the model offered.
  rm -f "$flag"
else
  echo armed > "$flag"
fi
