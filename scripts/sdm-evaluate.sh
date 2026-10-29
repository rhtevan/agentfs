#!/bin/bash
# sdm-evaluate.sh — Evaluate a skill or execution trace against a schema
#
# Usage:
#   sdm-evaluate.sh <target> <schema.yaml>
#
# Arguments:
#   target      — For operable schema: path to trace file (JSONL)
#                 For quality/observable schemas: path to skill directory
#   schema.yaml — Evaluation schema (quality.yaml, observable.yaml, or
#                 operable.yaml for runtime trace evaluation)
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
EVIDENCE_FILE=""
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--evidence" ]]; then
    EVIDENCE_FILE="__next__"
  elif [[ "$EVIDENCE_FILE" == "__next__" ]]; then
    EVIDENCE_FILE="$arg"
  else
    ARGS+=("$arg")
  fi
done

[[ ${#ARGS[@]} -ge 2 ]] || die "Usage: sdm-evaluate.sh <target> <schema.yaml> [--evidence <file>]"

TARGET="${ARGS[0]}"
SCHEMA="${ARGS[1]}"

[[ -e "$TARGET" ]] || die "Target not found: $TARGET"
[[ -f "$SCHEMA" ]] || die "Schema not found: $SCHEMA"

# --- Parse schema ---
SCHEMA_TYPE=$(yq -r '.["schema-type"]' "$SCHEMA")
SCHEMA_VERSION=$(yq -r '.["schema-version"] // "1.0"' "$SCHEMA")
SKILL_NAME=$(yq -r '.skill // "unknown"' "$SCHEMA")

log "Schema: $SCHEMA_TYPE v$SCHEMA_VERSION for skill: $SKILL_NAME"

# --- Extract evidence based on schema type ---

extract_evidence_quality() {
  # Target is a skill directory — use gather-skill-state.sh for
  # concise, explicit facts (~20 lines vs 3,000+ raw SKILL.md).
  # SDM judges meaning, not computes — facts must be pre-computed.
  local skill_dir="$1"
  local gather_script="${SCRIPT_DIR}/gather-skill-state.sh"

  if [[ -x "$gather_script" ]]; then
    "$gather_script" "$skill_dir"
  else
    # Fallback: raw SKILL.md (imprecise — legacy behavior)
    log "WARNING: gather-skill-state.sh not found. Using raw SKILL.md as evidence (imprecise)."
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
    evidence+="\n=== Directory Structure ===\n"
    evidence+=$(find "$skill_dir" -maxdepth 2 -not -path '*/observations/*' \
      -not -path '*/.git/*' 2>/dev/null | sort)
    printf '%b' "$evidence"
  fi
}

extract_evidence_operable() {
  # Target is a trace file — read JSONL
  cat "$1"
}

case "$SCHEMA_TYPE" in
  quality|observable|readme-alignment)
    if [[ -n "$EVIDENCE_FILE" && -f "$EVIDENCE_FILE" ]]; then
      EVIDENCE=$(cat "$EVIDENCE_FILE")
      if [[ "$SKILL_NAME" == "unknown" ]]; then
        SKILL_NAME=$(basename "$TARGET" .md)
      fi
    else
      [[ -d "$TARGET" ]] || die "For $SCHEMA_TYPE schemas, target must be a skill directory (or use --evidence <file>)"
      EVIDENCE=$(extract_evidence_quality "$TARGET")
      if [[ "$SKILL_NAME" == "unknown" ]]; then
        SKILL_NAME=$(basename "$TARGET")
      fi
    fi
    ;;
  operable)
    if [[ -n "$EVIDENCE_FILE" && -f "$EVIDENCE_FILE" ]]; then
      EVIDENCE=$(cat "$EVIDENCE_FILE")
    else
      [[ -f "$TARGET" ]] || die "For operable schema, target must be a trace file (or use --evidence <file>)"
      EVIDENCE=$(extract_evidence_operable "$TARGET")
    fi
    ;;
  *)
    die "Unknown schema-type: $SCHEMA_TYPE (expected quality, observable, or operable)"
    ;;
esac

# --- Build SDM questions from schema dimensions ---

DIMENSION_COUNT=$(yq -r '.dimensions | length' "$SCHEMA")
log "Evaluating $DIMENSION_COUNT dimensions..."

QUESTIONS="{}"
DIMENSION_NAMES=()
DIMENSION_WEIGHTS=()
DIMENSION_TARGETS=()
DIMENSION_METRICS=()
DIMENSION_POLARITIES=()

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name=$(yq -r ".dimensions[$i].name" "$SCHEMA")
  question=$(yq -r ".dimensions[$i].question" "$SCHEMA")
  metric=$(yq -r ".dimensions[$i].metric" "$SCHEMA")
  target=$(yq -r ".dimensions[$i].target // \"\"" "$SCHEMA")
  weight=$(yq -r ".dimensions[$i].weight // 1.0" "$SCHEMA")
  polarity=$(yq -r ".dimensions[$i].polarity // \"positive\"" "$SCHEMA")

  DIMENSION_NAMES+=("$name")
  DIMENSION_WEIGHTS+=("$weight")
  DIMENSION_TARGETS+=("$target")
  DIMENSION_METRICS+=("$metric")
  DIMENSION_POLARITIES+=("$polarity")

  # Map metric type to SystemOne question type
  case "$metric" in
    boolean)
      # SystemOne uses "noul" for yes/no predicates
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "noul", instructions: $i}}')
      ;;
    count)
      # SystemOne uses criteria array for score levels
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "score", instructions: $i,
          criteria: ["0","1","2","3","4","5+"]}}')
      ;;
    ratio)
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "score", instructions: $i,
          criteria: ["0-20%","20-40%","40-60%","60-80%","80-100%"]}}')
      ;;
    choice)
      # SystemOne uses criteria dict: {option: null}
      local criteria
      criteria=$(yq -r ".dimensions[$i].choices | .[] " "$SCHEMA" \
        | jq -R '{(.): null}' | jq -s 'add')
      q=$(jq -n --arg n "$name" --arg i "$question" --argjson c "$criteria" \
        '{($n): {type: "choice", instructions: $i, criteria: $c}}')
      ;;
    *)
      log "WARNING: Unknown metric type '$metric' for dimension '$name'. Using noul."
      q=$(jq -n --arg n "$name" --arg i "$question" \
        '{($n): {type: "noul", instructions: $i}}')
      ;;
  esac

  # Merge question dict into QUESTIONS object
  QUESTIONS=$(echo "$QUESTIONS" | jq --argjson q "$q" '. + $q')
done

# --- Call SDM ---

SDM_RESPONSE=$("$SDM_CALL" --input "$EVIDENCE" --questions "$QUESTIONS" 2>/dev/null) || {
  exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    log "WARNING: SDM endpoint unreachable. Returning SDM_UNAVAILABLE."
    # Build CECX JSON with all dimensions marked N/A
    UNAVAIL_DIMS="[]"
    for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
      dim=$(jq -n \
        --arg n "${DIMENSION_NAMES[$i]}" \
        --argjson w "${DIMENSION_WEIGHTS[$i]}" \
        '{name: $n, pass: null, score: -1, confidence: 0, detail: "SDM unavailable", weight: $w}')
      UNAVAIL_DIMS=$(echo "$UNAVAIL_DIMS" | jq --argjson d "$dim" '. + [$d]')
    done
    jq -n \
      --arg skill "$SKILL_NAME" \
      --arg schema_type "$SCHEMA_TYPE" \
      --arg schema_version "$SCHEMA_VERSION" \
      --arg ts "$(date -Iseconds)" \
      --argjson dims "$UNAVAIL_DIMS" \
      --argjson total "$DIMENSION_COUNT" \
      '{
        skill: $skill,
        schema_type: $schema_type,
        schema_version: $schema_version,
        timestamp: $ts,
        aggregate_score: -1,
        band: "SDM_UNAVAILABLE",
        pass_rate: -1,
        dimensions_total: $total,
        dimensions_passed: 0,
        dimensions: $dims
      }'
    log "Evaluation skipped: $SKILL_NAME — SDM_UNAVAILABLE"
    exit 0
  fi
  log "SDM call failed (exit $exit_code)."
  exit 1
}

# --- Parse results and compute scores ---

# SystemOne returns answers as a dict keyed by question name
ANSWERS=$(echo "$SDM_RESPONSE" | jq '.answers')
DIAGNOSTICS=$(echo "$SDM_RESPONSE" | jq '.diagnostics // {}')
TIMESTAMP=$(date -Iseconds)
TOTAL_PASS=0
TOTAL_DIMS=0
DIMENSIONS_JSON="[]"

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name="${DIMENSION_NAMES[$i]}"
  metric="${DIMENSION_METRICS[$i]}"
  target="${DIMENSION_TARGETS[$i]}"
  weight="${DIMENSION_WEIGHTS[$i]}"
  polarity="${DIMENSION_POLARITIES[$i]}"

  # SystemOne: answers keyed by name, not by index
  answer=$(echo "$ANSWERS" | jq --arg n "$name" '.[$n]')
  diag=$(echo "$DIAGNOSTICS" | jq --arg n "$name" '.[$n] // {}')
  label_mass=$(echo "$diag" | jq -r '.label_mass // 1')
  argmax_ok=$(echo "$diag" | jq -r '.argmax_is_label // true')

  pass=false
  score_val=0
  confidence=0
  detail=""

  # Flag unreliable results from diagnostics
  if [[ "$argmax_ok" == "false" ]]; then
    detail="unreliable — argmax not a label"
  fi

  case "$metric" in
    boolean)
      # SystemOne noul: read probabilities.yes or probabilities.no directly
      # No inversion hack needed — just read the right field
      if [[ "$polarity" == "negative" ]]; then
        prob=$(echo "$answer" | jq -r '.probabilities.no // 0')
      else
        prob=$(echo "$answer" | jq -r '.probabilities.yes // .noul // 0')
      fi
      # Normalize scientific notation for bc
      prob=$(awk "BEGIN {printf \"%.10f\", $prob}")
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      if (( $(echo "$prob >= 0.7" | bc -l) )); then
        pass=true; score_val=100
      elif (( $(echo "$prob >= 0.3" | bc -l) )); then
        score_val=50; detail="${detail:+$detail; }uncertain"
      else
        score_val=0
      fi
      ;;
    count|ratio)
      score_raw=$(echo "$answer" | jq -r '.score // 0')
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      max_scale=4
      case "$target" in
        ">="*)
          score_val=$(echo "$score_raw $max_scale" | awk '{printf "%.0f", ($1 / $2) * 100}')
          if (( $(echo "$score_raw >= $((max_scale - 1))" | bc -l) )); then pass=true; fi
          ;;
        "<="*)
          score_val=$(echo "$score_raw $max_scale" | awk '{v = (1 - $1 / $2) * 100; if (v < 0) v = 0; printf "%.0f", v}')
          if (( $(echo "$score_raw <= 1" | bc -l) )); then pass=true; fi
          ;;
        *)
          score_val=50; detail="${detail:+$detail; }no target comparison"
          ;;
      esac
      ;;
    choice)
      chosen=$(echo "$answer" | jq -r '.choice // "unknown"')
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      if [[ "$target" == "$chosen" ]] || [[ -z "$target" ]]; then
        pass=true; score_val=100
      else
        score_val=0; detail="${detail:+$detail; }expected=$target got=$chosen"
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
    --argjson lm "$label_mass" \
    --argjson ao "$(echo "$argmax_ok" | jq -R 'if . == "true" then true else false end')" \
    '{name: $n, pass: $p, score: $s, confidence: $c, detail: $d, weight: $w, label_mass: $lm, argmax_is_label: $ao}')

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

if [[ "$SCHEMA_TYPE" == "operable" ]]; then
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
