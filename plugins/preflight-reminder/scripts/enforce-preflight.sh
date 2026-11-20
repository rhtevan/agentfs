#!/usr/bin/env bash
# preflight-reminder: block the first MUTATING tool call of a user turn once,
# with a just-in-time reminder of AGENTS.md Rule 2 (Pre-Flight).
# Called by PreToolUse for ALL tools. Read-only calls pass and keep the flag.
# Flag states: "armed" (turn started, no mutation yet) -> "blocked <ms>"
# after the reminder. Mutating calls arriving within BATCH_MS of the block
# belong to the same parallel tool batch (the model has not seen the
# reminder yet) and are denied too; the retry after a model round-trip
# passes. 2026-11-17: gemma batched 3 edits — a pure one-shot denied the
# first and let the other two run before any plan was written.
set -euo pipefail
payload="$(cat)"
session_id="$(printf '%s' "$payload" | jq -r '.session_id // empty')"
[[ -z "$session_id" ]] && exit 0
flag="/tmp/goose-preflight/${session_id}"
[[ -f "$flag" ]] || exit 0
BATCH_MS="${PREFLIGHT_BATCH_MS:-2000}"
state="$(cat "$flag" 2>/dev/null || true)"
now_ms=$(( $(date +%s%N) / 1000000 ))
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
case "$tool_name" in
  write|edit) target="$(printf '%s' "$payload" | jq -r '.tool_input.path // ""')" ;;
  shell)
    command="$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')"
    bash "$SCRIPT_DIR/is-readonly.sh" "$command" && exit 0
    target="shell: $(printf '%s' "$command" | head -c 80)" ;;
  *) exit 0 ;;   # search_nodes, load_skill, tree, read_image, other extensions
esac
if [[ "$state" == blocked* ]]; then
  blocked_ms="${state#blocked }"
  if [[ "$blocked_ms" =~ ^[0-9]+$ ]] && (( now_ms - blocked_ms <= BATCH_MS )); then
    reason="Pre-Flight check (AGENTS.md Rule 2): this call (${target}) was issued in the same batch as a call that was just held for Pre-Flight. State the plan once, then retry all held calls yourself in this same turn — do not stop and wait for the user unless the plan needs their confirmation (git push). goose appends \"Do not retry; this is a policy denial\" to every hook denial: it does not apply to this Pre-Flight hold."
    printf '{"decision":"block","reason":"%s"}' "$(printf '%s' "$reason" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
    exit 0
  fi
  rm -f "$flag"; exit 0   # the retry after a model round-trip: allowed, turn done
fi
echo "blocked $now_ms" > "$flag"
reason="Pre-Flight check (AGENTS.md Rule 2) before the first change of this task (${target}). If the task modifies 2 or more files, has step dependencies, or includes git push: write the plan in your reply first (files that change, in what order, expected outcome; for git push also show git diff --stat and ask for confirmation, then wait), then retry this call yourself in this same turn — do not stop and wait for the user otherwise. If it is a single-file change, retry it as is. (Read-only calls are never held; this one was classified as a change — python3, bash <script> (except named read-only scripts such as verify-bundle.sh) and unlisted commands count as changes.) goose appends \"Do not retry; this is a policy denial\" to every hook denial: it does not apply to this Pre-Flight hold — retrying after the plan is the expected path."
printf '{"decision":"block","reason":"%s"}' "$(printf '%s' "$reason" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')"
exit 0
