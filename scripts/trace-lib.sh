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

AGENTFS_TRACE="${AGENTFS_TRACE:-/tmp/agentfs-trace-$$.jsonl}"

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

# Finalize the trace session with summary metrics.
# Args: none (reads from trace file)
trace_end() {
  local step_count
  step_count=$(grep -c '"type":"step"' "$AGENTFS_TRACE" 2>/dev/null || echo 0)
  local error_count
  error_count=$(grep '"type":"step"' "$AGENTFS_TRACE" 2>/dev/null \
    | grep -vc '"exit":0' 2>/dev/null || echo 0)
  printf '{"type":"end","ts":"%s","total_steps":%d,"errors":%d,"trace_file":"%s"}\n' \
    "$(date -Iseconds)" "$step_count" "$error_count" "$AGENTFS_TRACE" >> "$AGENTFS_TRACE"
}
