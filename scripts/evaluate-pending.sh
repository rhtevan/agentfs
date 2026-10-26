#!/bin/bash
# evaluate-pending.sh — Batch evaluator for accumulated execution traces
#
# Scans ~/.agents/.traces/ for unevaluated JSONL trace files, runs
# sdm-evaluate.sh against the universal observation schema, and
# persists scores to <skill>/scores.yaml.
#
# Trigger points:
#   - Manual: bash evaluate-pending.sh
#   - From skill-evolve: evaluates traces before computing upgrades
#   - From benchmark harness: evaluates test run traces
#
# Usage:
#   evaluate-pending.sh [--skill <name>] [--dry-run]
#
# Options:
#   --skill <name>  Only evaluate traces for this skill
#   --dry-run       List pending traces without evaluating
#
# Exit codes:
#   0 — All pending traces evaluated (or none pending)
#   1 — Some evaluations failed
#   2 — SDM endpoint unreachable
#   3 — Usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRACES_DIR="${HOME}/.agents/.traces"
SCHEMAS_DIR="${HOME}/.agents/skills/schemas"
SKILLS_DIR="${HOME}/.agents/skills"
SDM_EVALUATE="${SCRIPT_DIR}/sdm-evaluate.sh"
OBS_SCHEMA="${SCHEMAS_DIR}/observation.yaml"

die()  { echo "ERROR: $*" >&2; exit 3; }
log()  { echo "[evaluate-pending] $*" >&2; }

# --- Dependency check ---
[[ -x "$SDM_EVALUATE" ]] || die "sdm-evaluate.sh not found at $SDM_EVALUATE"
[[ -f "$OBS_SCHEMA" ]]   || die "observation.yaml not found at $OBS_SCHEMA"

# --- Parse arguments ---
FILTER_SKILL=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill)  FILTER_SKILL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) echo "Usage: evaluate-pending.sh [--skill <name>] [--dry-run]"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

# --- Ensure traces directory exists ---
if [[ ! -d "$TRACES_DIR" ]]; then
  log "No traces directory at $TRACES_DIR. Nothing to evaluate."
  exit 0
fi

# --- Find pending traces ---
# Trace files follow naming: <skill>-<timestamp>.jsonl
# Evaluated traces get a companion .scored marker file

PENDING=()
EVALUATED=0
FAILED=0

for trace_file in "$TRACES_DIR"/*.jsonl; do
  [[ -f "$trace_file" ]] || continue

  base=$(basename "$trace_file" .jsonl)
  scored_marker="${TRACES_DIR}/${base}.scored"

  # Skip already evaluated
  if [[ -f "$scored_marker" ]]; then
    continue
  fi

  # Extract skill name from trace init record
  skill_name=$(jq -r 'select(.type=="init") | .skill' "$trace_file" 2>/dev/null | head -1)
  if [[ -z "$skill_name" || "$skill_name" == "null" ]]; then
    log "WARNING: No init record in $trace_file — skipping"
    continue
  fi

  # Apply skill filter
  if [[ -n "$FILTER_SKILL" && "$skill_name" != "$FILTER_SKILL" ]]; then
    continue
  fi

  PENDING+=("$trace_file|$skill_name")
done

TOTAL_PENDING=${#PENDING[@]}

if [[ $TOTAL_PENDING -eq 0 ]]; then
  log "No pending traces to evaluate."
  exit 0
fi

log "Found $TOTAL_PENDING pending trace(s)."

# --- Dry run ---
if [[ "$DRY_RUN" == "true" ]]; then
  echo "Pending traces:"
  for entry in "${PENDING[@]}"; do
    IFS='|' read -r file skill <<< "$entry"
    echo "  $(basename "$file") — skill: $skill"
  done
  exit 0
fi

# --- Evaluate each trace ---
for entry in "${PENDING[@]}"; do
  IFS='|' read -r trace_file skill_name <<< "$entry"
  base=$(basename "$trace_file" .jsonl)

  log "Evaluating: $(basename "$trace_file") (skill: $skill_name)"

  # Run sdm-evaluate against observation schema
  result=""
  eval_exit=0
  result=$("$SDM_EVALUATE" "$trace_file" "$OBS_SCHEMA" 2>/dev/null) || eval_exit=$?

  if [[ $eval_exit -eq 2 ]]; then
    log "SDM endpoint unreachable. Stopping."
    exit 2
  fi

  if [[ $eval_exit -ne 0 || -z "$result" ]]; then
    log "FAILED: $(basename "$trace_file") — sdm-evaluate exit $eval_exit"
    FAILED=$((FAILED + 1))
    continue
  fi

  # Extract score and band
  score=$(echo "$result" | jq -r '.aggregate_score // 0')
  band=$(echo "$result" | jq -r '.band // "unknown"')

  log "  Score: $score ($band)"

  # --- Persist to scores.yaml ---
  skill_dir="${SKILLS_DIR}/${skill_name}"
  if [[ -d "$skill_dir" ]]; then
    scores_file="${skill_dir}/scores.yaml"
    timestamp=$(date -Iseconds)
    trace_basename=$(basename "$trace_file")

    # Append score entry
    cat >> "$scores_file" <<SCORE_ENTRY

- timestamp: "$timestamp"
  schema: observation
  schema_version: "1.0"
  aggregate_score: $score
  band: "$band"
  trace_file: "$trace_basename"
  dimensions:
$(echo "$result" | jq -r '.dimensions[] | "    - name: \(.name)\n      score: \(.score)\n      pass: \(.pass)"')
SCORE_ENTRY

    log "  Saved to $scores_file"
  else
    log "  WARNING: Skill directory not found at $skill_dir — score not persisted"
  fi

  # Write scored marker
  echo "$score $band $timestamp" > "${TRACES_DIR}/${base}.scored"
  EVALUATED=$((EVALUATED + 1))
done

# --- Summary ---
log "Complete: $EVALUATED evaluated, $FAILED failed, $TOTAL_PENDING total"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
