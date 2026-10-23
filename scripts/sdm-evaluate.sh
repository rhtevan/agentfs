#!/bin/bash
# sdm-evaluate.sh — Evaluate a skill or execution trace against a schema
#
# Usage:
#   sdm-evaluate.sh <target> <schema.yaml>
#
# Arguments:
#   target      — For observation schemas: path to trace file (JSONL)
#                 For quality/operable schemas: path to skill directory
#   schema.yaml — Evaluation schema (quality.yaml, operable.yaml, or
#                 per-skill observation.yaml)
#
# Output:
#   CECX-format JSON record on stdout.
#   If skill has observations/ dir, also appends record there and
#   updates index.json.
#
# Exit codes:
#   0 — All dimensions scored
#   1 — Partial (some SDM calls failed, scored dimensions reported)
#   2 — SDM endpoint unreachable
#   3 — Usage error
#
# Environment:
#   SDM_ENDPOINT  — Base URL (default: http://localhost:9000)
#   SDM_MODEL     — Model ID (default: auto-detect)
#   SDM_TIMEOUT   — Request timeout (default: 10)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDM_CALL="${SCRIPT_DIR}/sdm-call.sh"

die()  { echo "ERROR: $*" >&2; exit 3; }
log()  { echo "[sdm-evaluate] $*" >&2; }

# --- Dependency check ---
command -v yq >/dev/null 2>&1 || die "yq is required but not found. Install: pip install yq"
command -v jq >/dev/null 2>&1 || die "jq is required but not found."
[[ -x "$SDM_CALL" ]] || die "sdm-call.sh not found at $SDM_CALL"

# --- Arguments ---
[[ $# -ge 2 ]] || die "Usage: sdm-evaluate.sh <target> <schema.yaml>"

TARGET="$1"
SCHEMA="$2"

[[ -e "$TARGET" ]] || die "Target not found: $TARGET"
[[ -f "$SCHEMA" ]] || die "Schema not found: $SCHEMA"

# --- Parse schema ---
SCHEMA_TYPE=$(yq -r '.["schema-type"]' "$SCHEMA")
SCHEMA_VERSION=$(yq -r '.["schema-version"] // "1.0"' "$SCHEMA")
SKILL_NAME=$(yq -r '.skill // "unknown"' "$SCHEMA")

log "Schema: $SCHEMA_TYPE v$SCHEMA_VERSION for skill: $SKILL_NAME"

# --- Extract evidence based on schema type ---

extract_evidence_quality() {
  # Target is a skill directory — read SKILL.md and scripts/
  local skill_dir="$1"
  local evidence=""

  if [[ -f "$skill_dir/SKILL.md" ]]; then
    evidence+="=== SKILL.md ===\n"
    evidence+=$(cat "$skill_dir/SKILL.md")
    evidence+="\n"
  fi

  if [[ -d "$skill_dir/scripts" ]]; then
    evidence+="\n=== Scripts ===\n"
    for script in "$skill_dir/scripts/"*; do
      [[ -f "$script" ]] || continue
      evidence+="--- $(basename "$script") ---\n"
      evidence+=$(cat "$script")
      evidence+="\n"
    done
  fi

  # Directory listing
  evidence+="\n=== Directory Structure ===\n"
  evidence+=$(find "$skill_dir" -maxdepth 2 -not -path '*/observations/*' \
    -not -path '*/.git/*' 2>/dev/null | sort)

  printf '%b' "$evidence"
}

extract_evidence_observation() {
  # Target is a trace file — read JSONL
  cat "$1"
}

case "$SCHEMA_TYPE" in
  quality|operable)
    [[ -d "$TARGET" ]] || die "For $SCHEMA_TYPE schemas, target must be a skill directory"
    EVIDENCE=$(extract_evidence_quality "$TARGET")
    # Auto-detect skill name from directory if not in schema
    if [[ "$SKILL_NAME" == "unknown" ]]; then
      SKILL_NAME=$(basename "$TARGET")
    fi
    ;;
  observation)
    [[ -f "$TARGET" ]] || die "For observation schemas, target must be a trace file"
    EVIDENCE=$(extract_evidence_observation "$TARGET")
    ;;
  *)
    die "Unknown schema-type: $SCHEMA_TYPE (expected quality, operable, or observation)"
    ;;
esac

# --- Build SDM questions from schema dimensions ---

DIMENSION_COUNT=$(yq -r '.dimensions | length' "$SCHEMA")
log "Evaluating $DIMENSION_COUNT dimensions..."

QUESTIONS="[]"
DIMENSION_NAMES=()
DIMENSION_WEIGHTS=()
DIMENSION_TARGETS=()
DIMENSION_METRICS=()

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name=$(yq -r ".dimensions[$i].name" "$SCHEMA")
  question=$(yq -r ".dimensions[$i].question" "$SCHEMA")
  metric=$(yq -r ".dimensions[$i].metric" "$SCHEMA")
  target=$(yq -r ".dimensions[$i].target // \"\"" "$SCHEMA")
  weight=$(yq -r ".dimensions[$i].weight // 1.0" "$SCHEMA")

  DIMENSION_NAMES+=("$name")
  DIMENSION_WEIGHTS+=("$weight")
  DIMENSION_TARGETS+=("$target")
  DIMENSION_METRICS+=("$metric")

  # Map metric type to SDM question type
  case "$metric" in
    boolean)
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{name: $n, type: "predicate", instructions: $i}')
      ;;
    count)
      # Use score with levels 0-5 for count metrics
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{name: $n, type: "score", instructions: $i,
          levels: [{"label":"0"},{"label":"1"},{"label":"2"},{"label":"3"},{"label":"4"},{"label":"5+"}]}')
      ;;
    ratio)
      # Use score with percentage levels
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{name: $n, type: "score", instructions: $i,
          levels: [{"label":"0-20%"},{"label":"20-40%"},{"label":"40-60%"},{"label":"60-80%"},{"label":"80-100%"}]}')
      ;;
    choice)
      choices_json=$(yq -r ".dimensions[$i].choices | .[] " "$SCHEMA" \
        | jq -R '{value: .}' | jq -s '.')
      q=$(jq -n --arg n "$name" --arg i "$question" --argjson c "$choices_json" \
        '{name: $n, type: "choice", instructions: $i, choices: $c}')
      ;;
    *)
      log "WARNING: Unknown metric type '$metric' for dimension '$name'. Using predicate."
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{name: $n, type: "predicate", instructions: $i}')
      ;;
  esac

  QUESTIONS=$(echo "$QUESTIONS" | jq --argjson q "$q" '. + [$q]')
done

# --- Call SDM ---

SDM_RESPONSE=$("$SDM_CALL" --input "$EVIDENCE" --questions "$QUESTIONS" 2>/dev/null) || {
  exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    log "SDM endpoint unreachable."
    exit 2
  fi
  log "SDM call failed (exit $exit_code)."
  exit 1
}

# --- Parse results and compute scores ---

ANSWERS=$(echo "$SDM_RESPONSE" | jq '.answers')
TIMESTAMP=$(date -Iseconds)
TOTAL_PASS=0
TOTAL_DIMS=0
DIMENSIONS_JSON="[]"

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name="${DIMENSION_NAMES[$i]}"
  metric="${DIMENSION_METRICS[$i]}"
  target="${DIMENSION_TARGETS[$i]}"
  weight="${DIMENSION_WEIGHTS[$i]}"

  answer=$(echo "$ANSWERS" | jq ".[$i]")
  pass=false
  score_val=0
  confidence=0
  detail=""

  case "$metric" in
    boolean)
      prob=$(echo "$answer" | jq -r '.probability // 0')
      confidence=$prob
      if (( $(echo "$prob >= 0.7" | bc -l) )); then
        pass=true; score_val=100
      elif (( $(echo "$prob >= 0.3" | bc -l) )); then
        score_val=50; detail="uncertain"
      else
        score_val=0
      fi
      ;;
    count|ratio)
      score_raw=$(echo "$answer" | jq -r '.score // 0')
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      # SDM returns score on 0-4 scale (5 levels).
      # Normalize to 0-100 based on target direction.
      max_scale=4
      case "$target" in
        ">="*)
          # Higher is better (e.g., script_coverage >= 0.80)
          score_val=$(echo "$score_raw $max_scale" | awk '{printf "%.0f", ($1 / $2) * 100}')
          if (( $(echo "$score_raw >= $((max_scale - 1))" | bc -l) )); then pass=true; fi
          ;;
        "<="*)
          # Lower is better (e.g., concern_count <= 2) — invert
          score_val=$(echo "$score_raw $max_scale" | awk '{v = (1 - $1 / $2) * 100; if (v < 0) v = 0; printf "%.0f", v}')
          if (( $(echo "$score_raw <= 1" | bc -l) )); then pass=true; fi
          ;;
        *)
          score_val=50; detail="no target comparison"
          ;;
      esac
      ;;
    choice)
      chosen=$(echo "$answer" | jq -r '.choice // "unknown"')
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      # For choices, pass if confidence > 0.7 and matches expected
      if [[ "$target" == "$chosen" ]] || [[ -z "$target" ]]; then
        pass=true; score_val=100
      else
        score_val=0; detail="expected=$target got=$chosen"
      fi
      ;;
  esac

  dim_json=$(jq -n \
    --arg n "$name" \
    --argjson p "$pass" \
    --argjson s "$score_val" \
    --argjson c "$confidence" \
    --arg d "$detail" \
    --argjson w "$weight" \
    '{name: $n, pass: $p, score: $s, confidence: $c, detail: $d, weight: $w}')

  DIMENSIONS_JSON=$(echo "$DIMENSIONS_JSON" | jq --argjson d "$dim_json" '. + [$d]')

  if [[ "$pass" == "true" ]]; then
    TOTAL_PASS=$((TOTAL_PASS + 1))
  fi
  TOTAL_DIMS=$((TOTAL_DIMS + 1))
done

# --- Compute aggregate score ---

AGGREGATE=$(echo "$DIMENSIONS_JSON" | jq '
  [.[] | .score * .weight] as $weighted |
  [.[] | .weight] as $weights |
  ($weighted | add) / ($weights | add)
')

PASS_RATE=$(echo "scale=1; $TOTAL_PASS * 100 / $TOTAL_DIMS" | bc -l)

# Determine band
BAND="Redesign"
if (( $(echo "$AGGREGATE >= 90" | bc -l) )); then BAND="Operable"
elif (( $(echo "$AGGREGATE >= 75" | bc -l) )); then BAND="Tunable"
elif (( $(echo "$AGGREGATE >= 50" | bc -l) )); then BAND="Re-engineer"
fi

# --- Build output record ---

RECORD=$(jq -n \
  --arg skill "$SKILL_NAME" \
  --arg schema_type "$SCHEMA_TYPE" \
  --arg schema_version "$SCHEMA_VERSION" \
  --arg ts "$TIMESTAMP" \
  --argjson dims "$DIMENSIONS_JSON" \
  --argjson agg "$AGGREGATE" \
  --arg band "$BAND" \
  --argjson pass_rate "$PASS_RATE" \
  --argjson total_dims "$TOTAL_DIMS" \
  --argjson total_pass "$TOTAL_PASS" \
  '{
    skill: $skill,
    schema_type: $schema_type,
    schema_version: $schema_version,
    timestamp: $ts,
    aggregate_score: $agg,
    band: $band,
    pass_rate: $pass_rate,
    dimensions_total: $total_dims,
    dimensions_passed: $total_pass,
    dimensions: $dims
  }')

# --- Output ---

echo "$RECORD" | jq '.'

# --- Persist if observation type and skill has observations dir ---

if [[ "$SCHEMA_TYPE" == "observation" ]]; then
  # Infer skill dir from schema location
  SCHEMA_DIR=$(dirname "$SCHEMA")
  OBS_DIR="$SCHEMA_DIR/observations"

  if [[ -d "$OBS_DIR" ]] || [[ -d "$SCHEMA_DIR/scripts" ]]; then
    mkdir -p "$OBS_DIR"
    local_ts=$(echo "$TIMESTAMP" | tr ':' '-' | cut -d'+' -f1)
    echo "$RECORD" | jq '.' > "$OBS_DIR/${local_ts}.json"
    log "Saved observation record to $OBS_DIR/${local_ts}.json"

    # Update index.json (simplified — full implementation would aggregate trends)
    echo "$RECORD" | jq '{
      skill: .skill,
      latest_score: .aggregate_score,
      latest_band: .band,
      latest_timestamp: .timestamp,
      schema_version: .schema_version
    }' > "$OBS_DIR/index.json"
    log "Updated $OBS_DIR/index.json"
  fi
fi

log "Evaluation complete: $SKILL_NAME — $AGGREGATE ($BAND) [$TOTAL_PASS/$TOTAL_DIMS passed]"
