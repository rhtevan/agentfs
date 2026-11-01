#!/usr/bin/env bash
# evaluate-alignment.sh — Run SDM alignment evaluation on gathered state
# Usage: bash evaluate-alignment.sh <state-file>
#
# Combines extract-comparison.sh + sdm-evaluate.sh into a single call.
# Outputs SDM CECX JSON to stdout. Writes comparison evidence to
# /tmp/readme-comparison.txt as side effect.
#
# Exit codes:
#   0 — Evaluation complete, JSON on stdout
#   1 — Extract or evaluate failed
#   2 — SDM unavailable (caller should fall through to manual)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="${1:-}"

if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  echo "Usage: evaluate-alignment.sh <state-file>" >&2
  exit 2
fi

COMPARISON_FILE="/tmp/readme-comparison.txt"
EXTRACT_SCRIPT="${SCRIPT_DIR}/extract-comparison.sh"
SDM_EVALUATE="${HOME}/.agents/scripts/sdm-evaluate.sh"
SCHEMA="${HOME}/.agents/skills/schemas/readme-alignment.yaml"

# --- Trace setup ---
TRACE_LIB="${HOME}/.agents/scripts/trace-lib.sh"
_trace=false
if [[ -f "$TRACE_LIB" ]]; then
  source "$TRACE_LIB"
  trace_init "agentfs-readme-audit" "evaluate-alignment"
  _trace=true
fi

trace() {
  if [[ "$_trace" == "true" ]]; then
    trace_step "$@"
  fi
}

# Step 1: Extract comparison evidence
trace 0 "extract_comparison" 0 "input=$STATE_FILE"
if ! bash "$EXTRACT_SCRIPT" "$STATE_FILE" > "$COMPARISON_FILE" 2>/dev/null; then
  trace 1 "extract_comparison_failed" 1 "script=$EXTRACT_SCRIPT"
  echo "❌ extract-comparison.sh failed" >&2
  [[ "$(type -t trace_end)" == "function" ]] && trace_end
  exit 1
fi

# Step 2: Run SDM evaluation
trace 1 "sdm_evaluate" 0 "schema=readme-alignment.yaml"
SDM_EXIT=0
SDM_OUTPUT=$(bash "$SDM_EVALUATE" "$COMPARISON_FILE" "$SCHEMA" \
  --evidence "$COMPARISON_FILE" 2>/dev/null) || SDM_EXIT=$?

if [[ "$SDM_EXIT" -eq 2 ]]; then
  trace 2 "sdm_unavailable" 2 "exit=2"
  echo "⚠️ SDM unavailable — fall through to manual comparison" >&2
  [[ "$(type -t trace_end)" == "function" ]] && trace_end
  exit 2
fi

if [[ "$SDM_EXIT" -ne 0 ]]; then
  trace 2 "sdm_evaluate_failed" 1 "exit=$SDM_EXIT"
  echo "❌ sdm-evaluate.sh failed with exit $SDM_EXIT" >&2
  [[ "$(type -t trace_end)" == "function" ]] && trace_end
  exit 1
fi

# Output JSON
trace 2 "evaluation_complete" 0 "done"
echo "$SDM_OUTPUT"

[[ "$(type -t trace_end)" == "function" ]] && trace_end
