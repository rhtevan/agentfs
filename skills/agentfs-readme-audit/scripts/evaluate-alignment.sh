#!/usr/bin/env bash
# evaluate-alignment.sh — Run SDM alignment evaluation on gathered state
# Usage: bash evaluate-alignment.sh <state-file>
#
# Combines extract-comparison.sh + per-dimension SDM calls into a single
# workflow. Sends isolated evidence per dimension to avoid evidence dilution
# on mid-range models (14B).
#
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
SDM_CALL="${HOME}/.agents/scripts/sdm-call.sh"
SCHEMA="${HOME}/.agents/skills/schemas/readme-alignment.yaml"

# Read scope from state file to filter dimensions (user vs project)
DETECTED_SCOPE=$(grep '^Scope:' "$STATE_FILE" | head -1 | awk '{print tolower($2)}')
DETECTED_SCOPE="${DETECTED_SCOPE:-user}"

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

# --- Step 1: Extract comparison evidence ---
trace 0 "extract_comparison" 0 "input=$STATE_FILE"
if ! bash "$EXTRACT_SCRIPT" "$STATE_FILE" > "$COMPARISON_FILE" 2>/dev/null; then
  trace 1 "extract_comparison_failed" 1 "script=$EXTRACT_SCRIPT"
  echo "❌ extract-comparison.sh failed" >&2
  [[ "$(type -t trace_end)" == "function" ]] && trace_end
  exit 1
fi

# --- Step 2: Check SDM availability ---
if ! bash "$SDM_CALL" --input "ping" --questions '{"ping": {"type": "noul", "instructions": "Is this a test?"}}' >/dev/null 2>&1; then
  trace 1 "sdm_unavailable" 2 "endpoint unreachable"
  echo "⚠️ SDM unavailable — fall through to manual comparison" >&2
  [[ "$(type -t trace_end)" == "function" ]] && trace_end
  exit 2
fi

# --- Step 3: Per-dimension SDM evaluation ---
# Read dimensions from schema, filter by scope, call SDM per-dimension
# with isolated evidence to avoid evidence dilution.

EVIDENCE_FULL=$(cat "$COMPARISON_FILE")
DIMENSION_COUNT=$(yq -r '.dimensions | length' "$SCHEMA")

RESULTS="[]"
PASSED=0
TOTAL=0
WEIGHTED_SUM=0
WEIGHT_TOTAL=0

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name=$(yq -r ".dimensions[$i].name" "$SCHEMA")
  dim_scope=$(yq -r ".dimensions[$i].scope // \"\"" "$SCHEMA")
  question=$(yq -r ".dimensions[$i].question" "$SCHEMA")
  metric=$(yq -r ".dimensions[$i].metric" "$SCHEMA")
  polarity=$(yq -r ".dimensions[$i].polarity // \"positive\"" "$SCHEMA")
  weight=$(yq -r ".dimensions[$i].weight // 1.0" "$SCHEMA")

  # Skip dimensions that don't match the detected scope
  if [[ -n "$dim_scope" && "$dim_scope" != "$DETECTED_SCOPE" ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Extract per-dimension evidence section
  # Sections are delimited by "--- <PREFIX>: ... ---" markers
  # Extract the prefix (D1, D2, P1, etc.) from the dimension name
  prefix=$(echo "$name" | grep -oP '^[A-Z]+[0-9]+' || echo "")

  if [[ -n "$prefix" ]]; then
    # Extract section between this marker and the next "--- " marker
    dim_evidence=$(echo "$EVIDENCE_FULL" | sed -n "/^--- ${prefix}:/,/^--- [A-Z]/p" | head -n -1)
    if [[ -z "$dim_evidence" ]]; then
      # Last section — no next marker
      dim_evidence=$(echo "$EVIDENCE_FULL" | sed -n "/^--- ${prefix}:/,\$p")
    fi
  else
    # No prefix match — use full evidence (fallback)
    dim_evidence="$EVIDENCE_FULL"
  fi

  # Build single-question SDM request
  case "$metric" in
    boolean)
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "noul", instructions: $i}}')
      ;;
    *)
      # Only boolean metrics used in readme-alignment currently
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "noul", instructions: $i}}')
      ;;
  esac

  # Call SDM with isolated evidence
  SDM_RESPONSE=$(bash "$SDM_CALL" --input "$dim_evidence" --questions "$q" 2>/dev/null) || {
    # SDM call failed for this dimension — mark as unavailable
    dim_result=$(jq -n \
      --arg n "$name" --argjson w "$weight" \
      '{name: $n, pass: null, score: -1, confidence: 0, detail: "SDM call failed", weight: $w,
        label_mass: 0, argmax_is_label: false}')
    RESULTS=$(echo "$RESULTS" | jq --argjson d "$dim_result" '. + [$d]')
    continue
  }

  # Parse answer
  answer=$(echo "$SDM_RESPONSE" | jq --arg n "$name" '.answers[$n]')

  # Apply pass/fail logic (mirrors sdm-evaluate.sh boolean handling)
  pass=false
  score_val=0
  detail=""

  if [[ "$polarity" == "negative" ]]; then
    prob=$(echo "$answer" | jq -r '.probabilities.no // 0')
  else
    prob=$(echo "$answer" | jq -r '.probabilities.yes // .noul // 0')
  fi

  # Normalize scientific notation
  prob=$(awk "BEGIN {printf \"%.10f\", $prob}")
  confidence=$(echo "$answer" | jq -r '.confidence // 0')
  label_mass=$(echo "$SDM_RESPONSE" | jq --arg n "$name" '.diagnostics[$n].label_mass // 0')
  argmax_is_label=$(echo "$SDM_RESPONSE" | jq --arg n "$name" '.diagnostics[$n].argmax_is_label // false')

  if (( $(echo "$prob >= 0.7" | bc -l) )); then
    pass=true; score_val=100
  elif (( $(echo "$prob >= 0.3" | bc -l) )); then
    score_val=50; detail="uncertain"
  else
    score_val=0
  fi

  if [[ "$pass" == "true" ]]; then
    PASSED=$((PASSED + 1))
  fi

  # Accumulate weighted scores
  WEIGHTED_SUM=$(echo "$WEIGHTED_SUM + $score_val * $weight" | bc -l)
  WEIGHT_TOTAL=$(echo "$WEIGHT_TOTAL + $weight * 100" | bc -l)

  # Build dimension result
  dim_result=$(jq -n \
    --arg n "$name" \
    --argjson p "$pass" \
    --argjson s "$score_val" \
    --argjson c "$confidence" \
    --arg d "$detail" \
    --argjson w "$weight" \
    --argjson lm "$label_mass" \
    --argjson ail "$argmax_is_label" \
    '{name: $n, pass: $p, score: $s, confidence: $c, detail: $d, weight: $w,
      label_mass: $lm, argmax_is_label: $ail}')
  RESULTS=$(echo "$RESULTS" | jq --argjson d "$dim_result" '. + [$d]')

  trace "$i" "$name" 0 "pass=$pass score=$score_val conf=$confidence"
done

# --- Step 4: Compute aggregate ---
if (( $(echo "$WEIGHT_TOTAL > 0" | bc -l) )); then
  AGGREGATE=$(echo "$WEIGHTED_SUM / $WEIGHT_TOTAL * 100" | bc -l)
else
  AGGREGATE=0
fi

if (( $(echo "$AGGREGATE >= 90" | bc -l) )); then
  BAND="Operable"
elif (( $(echo "$AGGREGATE >= 75" | bc -l) )); then
  BAND="Tunable"
elif (( $(echo "$AGGREGATE >= 50" | bc -l) )); then
  BAND="Re-engineer"
else
  BAND="Redesign"
fi

if [[ "$TOTAL" -gt 0 ]]; then
  PASS_RATE=$(echo "$PASSED / $TOTAL * 100" | bc -l)
else
  PASS_RATE=0
fi

# --- Output CECX JSON ---
SKILL_NAME=$(basename "$COMPARISON_FILE" .txt)
jq -n \
  --arg skill "$SKILL_NAME" \
  --arg schema_type "readme-alignment" \
  --arg schema_version "1.0" \
  --arg ts "$(date -Iseconds)" \
  --argjson agg "$(printf '%.4f' "$AGGREGATE")" \
  --arg band "$BAND" \
  --argjson pr "$(printf '%.1f' "$PASS_RATE")" \
  --argjson total "$TOTAL" \
  --argjson passed "$PASSED" \
  --argjson dims "$RESULTS" \
  '{
    skill: $skill,
    schema_type: $schema_type,
    schema_version: $schema_version,
    timestamp: $ts,
    aggregate_score: $agg,
    band: $band,
    pass_rate: $pr,
    dimensions_total: $total,
    dimensions_passed: $passed,
    dimensions: $dims
  }'

trace "$TOTAL" "evaluation_complete" 0 "total=$TOTAL passed=$PASSED aggregate=$AGGREGATE"
[[ "$(type -t trace_end)" == "function" ]] && trace_end
