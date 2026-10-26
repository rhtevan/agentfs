#!/bin/bash
# trace-lib.sh — Agent-agnostic execution trace capture for Observable Skills
#
# Source this file in any skill script to enable trace capture.
# Traces are written as JSONL to the file specified by AGENTFS_TRACE.
#
# Usage in a skill script:
#   source ~/.agents/scripts/trace-lib.sh
#   trace_init "readme-audit" "2.1.0"
#   trace_step 1 "gather_skill_count" 0 "count=61"
#   trace_step 2 "read_readme" 0 "lines=850"
#   trace_end
#
# Environment:
#   AGENTFS_TRACE — Output file path. If unset, defaults to
#                   /tmp/agentfs-trace-<pid>.jsonl
#
# The LLM's only job: set AGENTFS_TRACE before the first script,
# pass the path to sdm-evaluate.sh at the end. Two instructions.
#
# Token Cost Tracking:
#   Call trace_tokens after any LLM or SDM call to record token usage.
#   trace_end aggregates totals for showback/ROI analysis.
#   Token data sources:
#     - SDM responses: usage.total_tokens in response JSON
#     - LLM tool calls: inferred from response metadata
#   Cost insight: "This skill costs N tokens per execution on 14B"

AGENTFS_TRACE="${AGENTFS_TRACE:-/tmp/agentfs-trace-$$.jsonl}"

# Running token counters (accumulated across the trace session)
_TRACE_PROMPT_TOKENS=0
_TRACE_COMPLETION_TOKENS=0
_TRACE_TOTAL_TOKENS=0

# Initialize a new trace session.
# Args: <skill-name> <skill-version>
trace_init() {
  local skill="${1:-unknown}" version="${2:-0.0.0}"
  printf '{"type":"init","ts":"%s","skill":"%s","version":"%s","pid":%d}\n' \
    "$(date -Iseconds)" "$skill" "$version" "$$" > "$AGENTFS_TRACE"
}

# Record a single execution step.
# Args: <step-number> <action-name> <exit-code> <detail>
trace_step() {
  local step="${1:-0}" action="${2:-unknown}" exit_code="${3:-0}" detail="${4:-}"
  printf '{"type":"step","ts":"%s","step":%d,"action":"%s","exit":%d,"detail":"%s"}\n' \
    "$(date -Iseconds)" "$step" "$action" "$exit_code" "$detail" >> "$AGENTFS_TRACE"
}

# Record token usage from an LLM or SDM call.
# Args: <step-number> <source> <prompt-tokens> <completion-tokens>
# Source: "sdm" | "llm" | "tool" — identifies the model tier
# Example: trace_tokens 3 "sdm" 596 6
trace_tokens() {
  local step="${1:-0}" source="${2:-unknown}" prompt="${3:-0}" completion="${4:-0}"
  local total=$((prompt + completion))
  _TRACE_PROMPT_TOKENS=$((_TRACE_PROMPT_TOKENS + prompt))
  _TRACE_COMPLETION_TOKENS=$((_TRACE_COMPLETION_TOKENS + completion))
  _TRACE_TOTAL_TOKENS=$((_TRACE_TOTAL_TOKENS + total))
  printf '{"type":"tokens","ts":"%s","step":%d,"source":"%s","prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d}\n' \
    "$(date -Iseconds)" "$step" "$source" "$prompt" "$completion" "$total" >> "$AGENTFS_TRACE"
}

# Finalize the trace session with summary metrics.
# Args: none (reads from trace file)
trace_end() {
  local step_count
  step_count=$(grep -c '"type":"step"' "$AGENTFS_TRACE" 2>/dev/null || echo 0)
  local error_count
  error_count=$(grep '"type":"step"' "$AGENTFS_TRACE" 2>/dev/null \
    | grep -vc '"exit":0' 2>/dev/null || true)
  error_count="${error_count:-0}"
  # Strip whitespace/newlines that grep -c may leave
  error_count=$(echo "$error_count" | tr -d '[:space:]')
  printf '{"type":"end","ts":"%s","total_steps":%d,"errors":%d,"prompt_tokens":%d,"completion_tokens":%d,"total_tokens":%d,"trace_file":"%s"}\n' \
    "$(date -Iseconds)" "$step_count" "$error_count" \
    "$_TRACE_PROMPT_TOKENS" "$_TRACE_COMPLETION_TOKENS" "$_TRACE_TOTAL_TOKENS" \
    "$AGENTFS_TRACE" >> "$AGENTFS_TRACE"
}
