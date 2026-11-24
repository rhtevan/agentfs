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
#   SDM_MIN_CONFIDENCE — Flag dimensions below this model confidence (default: 0.7).
#                   Adds low_confidence:true + "low confidence (x.xx)" to detail and a
#                   top-level low_confidence_count. Scores are NOT changed. Needed because
#                   some models (e.g. D3 pooling) always return label_mass=1.0 and
#                   argmax_is_label=true, so the diagnostics-based checks never fire.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDM_CALL="${SDM_CALL:-${SCRIPT_DIR}/sdm-call.sh}"   # F30: t4-score-call.sh is a drop-in (see t4-static-score.sh)

die()  { echo "ERROR: $*" >&2; exit 3; }
log()  { echo "[sdm-evaluate] $*" >&2; }

# --- Dependency check ---
command -v yq >/dev/null 2>&1 || die "yq is required but not found. Install: pip install yq"
command -v jq >/dev/null 2>&1 || die "jq is required but not found."
[[ -x "$SDM_CALL" ]] || die "sdm-call.sh not found at $SDM_CALL"

# --- Arguments ---
EVIDENCE_FILE=""
PHASE_FILTER=""
SCOPE_FILTER=""
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--evidence" ]]; then
    EVIDENCE_FILE="__next__"
  elif [[ "$EVIDENCE_FILE" == "__next__" ]]; then
    EVIDENCE_FILE="$arg"
  elif [[ "$arg" == "--phase" ]]; then
    PHASE_FILTER="__next__"
  elif [[ "$PHASE_FILTER" == "__next__" ]]; then
    PHASE_FILTER="$arg"
  elif [[ "$arg" == "--scope" ]]; then
    SCOPE_FILTER="__next__"
  elif [[ "$SCOPE_FILTER" == "__next__" ]]; then
    SCOPE_FILTER="$arg"
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
ARTIFACT_TYPE=$(yq -r '.["artifact-type"] // "skill"' "$SCHEMA")
SKILL_NAME=$(yq -r '.skill // "unknown"' "$SCHEMA")

log "Schema: $SCHEMA_TYPE v$SCHEMA_VERSION (artifact: $ARTIFACT_TYPE) for skill: $SKILL_NAME"

# --- Extract evidence based on schema type and artifact type ---

extract_evidence_quality_skill() {
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

extract_evidence_agents_md() {
  # Target is an AGENTS.md file — use gather-skill-state.sh --target agents-md
  # Extracts per-rule metrics AND BMBT evidence for adapted schemas.
  local agents_file="$1"
  local gather_script="${SCRIPT_DIR}/gather-skill-state.sh"

  if [[ -x "$gather_script" ]]; then
    "$gather_script" --target agents-md "$agents_file"
  else
    # Fallback: raw AGENTS.md content
    log "WARNING: gather-skill-state.sh not found. Using raw AGENTS.md as evidence."
    cat "$agents_file"
  fi
}

extract_evidence_operable() {
  # Target is a trace file — read JSONL
  cat "$1"
}

extract_evidence_operable_agents_md() {
  # Target is benchmark evidence file (pre-composed by caller)
  local target="$1"
  if [[ -f "$target" ]]; then
    cat "$target"
  else
    die "Benchmark evidence file not found: $target"
  fi
}

case "$SCHEMA_TYPE" in
  quality|observable|readme-alignment)
    if [[ -n "$EVIDENCE_FILE" && -f "$EVIDENCE_FILE" ]]; then
      # For observable schema, strip step excerpts to avoid evidence dilution.
      # The 14B SDM model can't reliably locate facts in 200+ line evidence.
      if [[ "$SCHEMA_TYPE" == "observable" ]]; then
        EVIDENCE=$(sed '/^Step excerpts:/,$d' "$EVIDENCE_FILE")
      else
        EVIDENCE=$(cat "$EVIDENCE_FILE")
      fi
      if [[ "$SKILL_NAME" == "unknown" ]]; then
        SKILL_NAME=$(basename "$TARGET" .md)
      fi
    elif [[ "$ARTIFACT_TYPE" == "agents-md" ]]; then
      # Adapted schema for AGENTS.md — target is the AGENTS.md file itself
      [[ -f "$TARGET" ]] || die "For agents-md schemas, target must be an AGENTS.md file (or use --evidence <file>)"
      EVIDENCE=$(extract_evidence_agents_md "$TARGET")
      SKILL_NAME="AGENTS.md"
    else
      [[ -d "$TARGET" ]] || die "For $SCHEMA_TYPE schemas, target must be a skill directory (or use --evidence <file>)"
      EVIDENCE=$(extract_evidence_quality_skill "$TARGET")
      if [[ "$SKILL_NAME" == "unknown" ]]; then
        SKILL_NAME=$(basename "$TARGET")
      fi
    fi
    ;;
  operable)
    if [[ -n "$EVIDENCE_FILE" && -f "$EVIDENCE_FILE" ]]; then
      EVIDENCE=$(cat "$EVIDENCE_FILE")
    elif [[ "$ARTIFACT_TYPE" == "agents-md" ]]; then
      # Adapted operable schema for AGENTS.md — target is benchmark evidence
      [[ -f "$TARGET" ]] || die "For agents-md operable schema, target must be a benchmark evidence file (or use --evidence <file>)"
      EVIDENCE=$(extract_evidence_operable_agents_md "$TARGET")
      SKILL_NAME="AGENTS.md"
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
DIMENSION_QUESTIONS=()

for i in $(seq 0 $((DIMENSION_COUNT - 1))); do
  name=$(yq -r ".dimensions[$i].name" "$SCHEMA")
  phase=$(yq -r ".dimensions[$i].phase // \"\"" "$SCHEMA")
  dim_scope=$(yq -r ".dimensions[$i].scope // \"\"" "$SCHEMA")

  # Skip dimensions that don't match the phase filter
  if [[ -n "$PHASE_FILTER" && -n "$phase" && "$phase" != "$PHASE_FILTER" ]]; then
    continue
  fi

  # Skip dimensions that don't match the scope filter
  if [[ -n "$SCOPE_FILTER" && -n "$dim_scope" && "$dim_scope" != "$SCOPE_FILTER" ]]; then
    continue
  fi

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
  DIMENSION_QUESTIONS+=("$question")

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
      criteria=$(yq -r ".dimensions[$i].choices | .[] " "$SCHEMA" \
        | jq -R '{(.): null}' | jq -s 'add')
      q=$(jq -n --arg n "$name" --arg i "$question" --argjson c "$criteria" \
        '{($n): {type: "choice", instructions: $i, criteria: $c}}')
      ;;
    score)
      # Ordinal score with criteria defined in schema YAML.
      # Used for semantic dimensions (step_clarity, prose_executability).
      score_criteria=$(yq -r ".dimensions[$i].criteria | .[]" "$SCHEMA" \
        | jq -R '.' | jq -s '.')
      q=$(jq -n --arg n "$name" --arg i "$question" --argjson c "$score_criteria" \
        '{($n): {type: "score", instructions: $i, criteria: $c}}')
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

EVALUATED_COUNT=${#DIMENSION_NAMES[@]}
if [[ -n "$PHASE_FILTER" ]]; then
  log "Phase filter: $PHASE_FILTER — evaluating $EVALUATED_COUNT of $DIMENSION_COUNT dimensions"
fi
if [[ -n "$SCOPE_FILTER" ]]; then
  log "Scope filter: $SCOPE_FILTER — evaluating $EVALUATED_COUNT of $DIMENSION_COUNT dimensions"
fi

# --- Call SDM ---

SDM_RESPONSE=$("$SDM_CALL" --input "$EVIDENCE" --questions "$QUESTIONS" 2>/dev/null) || {
  exit_code=$?
  if [[ $exit_code -eq 2 ]]; then
    log "WARNING: SDM endpoint unreachable. Returning SDM_UNAVAILABLE."
    # Build CECX JSON with all dimensions marked N/A. Each dimension carries
    # its question/metric/target/polarity so the calling T4 agent can answer
    # it in-session (T4 fallback, report only — see schemas/sdm-endpoint.md).
    UNAVAIL_DIMS="[]"
    for i in $(seq 0 $((EVALUATED_COUNT - 1))); do
      dim=$(jq -n \
        --arg n "${DIMENSION_NAMES[$i]}" \
        --argjson w "${DIMENSION_WEIGHTS[$i]}" \
        --arg q "${DIMENSION_QUESTIONS[$i]}" \
        --arg m "${DIMENSION_METRICS[$i]}" \
        --arg t "${DIMENSION_TARGETS[$i]}" \
        --arg p "${DIMENSION_POLARITIES[$i]}" \
        '{name: $n, pass: null, score: -1, confidence: 0, detail: "SDM unavailable", weight: $w,
          question: $q, metric: $m, target: $t, polarity: $p}')
      UNAVAIL_DIMS=$(echo "$UNAVAIL_DIMS" | jq --argjson d "$dim" '. + [$d]')
    done
    jq -n \
      --arg skill "$SKILL_NAME" \
      --arg schema_type "$SCHEMA_TYPE" \
      --arg schema_version "$SCHEMA_VERSION" \
      --arg ts "$(date -Iseconds)" \
      --argjson dims "$UNAVAIL_DIMS" \
      --argjson total "$EVALUATED_COUNT" \
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
        dimensions: $dims,
        fallback: {
          mode: "t4-in-session",
          persist: false,
          instruction: "SDM is unavailable. The current (T4) session model answers each dimension question as a classifier against the same evidence and reports the result labelled T4-fallback (<model>, not persisted). Do NOT write these answers to scores.yaml or observations. SDM scores resume automatically when SDM is reachable."
        }
      }'
    log "Evaluation skipped: $SKILL_NAME — SDM_UNAVAILABLE (T4 fallback questions included)"
    exit 0
  fi
  log "SDM call failed (exit $exit_code)."
  exit 1
}

# --- Parse results and compute scores ---

# SystemOne returns answers as a dict keyed by question name
ANSWERS=$(echo "$SDM_RESPONSE" | jq '.answers')
SCORER=$(echo "$SDM_RESPONSE" | jq -r '.scorer // "sdm"')   # "t4:<model>" from t4-score-call.sh
DIAGNOSTICS=$(echo "$SDM_RESPONSE" | jq '.diagnostics // {}')
if [[ "$DIAGNOSTICS" == "{}" ]]; then
  log "WARNING: SDM response has no diagnostics (label_mass/argmax_is_label unavailable) — reliability checks skipped"
fi
TIMESTAMP=$(date -Iseconds)
TOTAL_PASS=0
TOTAL_DIMS=0
MIN_CONF="${SDM_MIN_CONFIDENCE:-0.7}"
LOW_CONF_COUNT=0
LOW_CONF_NAMES=""
DIMENSIONS_JSON="[]"

# --- Deterministic overrides -------------------------------------------
# Some dimensions are declared `evidence_source: filesystem` and are already
# answered exactly by gather-skill-state.sh (Tier 1). Asking a probabilistic
# model to re-derive a fact it was handed produces false negatives: on
# 2026-11-16 the SDM returned has_bones=0 for goose-setup and
# headroom-litellm-proxy, both of which ship an executable scripts/setup.sh.
# Build fell 100 -> 50 and both lost QOO qualification with no change to the
# skill. Facts are read here; only judgment goes to the model.
#
# det_override <dimension-name>
#   echoes "<score> <pass> <detail>" and returns 0 when it owns the dimension,
#   returns 1 when the model's answer should stand.
det_override() {
  case "$1" in
    has_bones)
      # "Does scripts/ contain at least one shell script?" — countable.
      local n
      n=$(printf '%s\n' "$EVIDENCE" | sed -n 's/^Scripts in scripts\/ directory:[[:space:]]*//p' | head -1)
      [[ "$n" =~ ^[0-9]+$ ]] || return 1
      if [[ "$n" -gt 0 ]]; then
        echo "100 true deterministic: $n script(s) in scripts/"
      else
        echo "0 false deterministic: no scripts in scripts/"
      fi
      return 0 ;;
    prose_executability)
      # Scores only steps marked [SCRIPTED: no]. At 100% script coverage the
      # input set is empty and the model returns 0 — i.e. reaching the goal
      # lowers the score. Report full marks on an empty set, the way
      # build_band already reports not-evaluated.
      local cov tot
      cov=$(printf '%s\n' "$EVIDENCE" | sed -n 's/^Script coverage:[[:space:]]*\([0-9]\+\) of \([0-9]\+\).*/\1 \2/p' | head -1)
      [[ -n "$cov" ]] || return 1
      read -r sc tot <<<"$cov"
      [[ "$tot" =~ ^[0-9]+$ && "$sc" =~ ^[0-9]+$ ]] || return 1
      # Only override when there is genuinely nothing to judge.
      if [[ "$tot" -gt 0 && "$sc" -eq "$tot" ]]; then
        echo "100 true not-evaluated: no prose-only steps (script coverage ${sc}/${tot})"
        return 0
      fi
      return 1 ;;
  esac
  return 1
}

for i in $(seq 0 $((EVALUATED_COUNT - 1))); do
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
        # noul-only responses (e.g. llama.cpp /v1/systemone) omit probabilities: derive no = 1 - noul
        prob=$(echo "$answer" | jq -r '.probabilities.no // (if .noul != null then 1 - .noul else 0 end)')
      else
        prob=$(echo "$answer" | jq -r '.probabilities.yes // .noul // 0')
      fi
      # Normalize scientific notation for bc
      prob=$(awk "BEGIN {printf \"%.10f\", $prob}")
      confidence=$(echo "$answer" | jq -r '.confidence // (if .noul != null then ([.noul, 1 - .noul] | max) else 0 end)')
      if (( $(echo "$prob >= 0.7" | bc -l) )); then
        pass=true; score_val=100
      elif (( $(echo "$prob >= 0.3" | bc -l) )); then
        score_val=50; detail="${detail:+$detail; }uncertain"
      else
        score_val=0
      fi
      ;;
    count|ratio|score)
      # Normalize scientific notation (e.g., 6.47E-7) to decimal for bc.
      # SystemOne returns expected value (probability-weighted ordinal average),
      # not a discrete bucket index. Round to nearest integer since ordinal
      # buckets are whole numbers (both count and ratio metrics).
      score_raw=$(echo "$answer" | jq -r '.score // 0' | awk '{printf "%.0f", $1}')
      confidence=$(echo "$answer" | jq -r '.confidence // 0')
      # SystemOne score type returns ordinal index (0-based) into criteria array.
      # count: ["0","1","2","3","4","5+"] → 6 buckets, max_scale=5
      # ratio: ["0-20%","20-40%","40-60%","60-80%","80-100%"] → 5 buckets, max_scale=4
      # score: criteria from schema YAML → max_scale = len(criteria) - 1
      if [[ "$metric" == "count" ]]; then
        max_scale=5
      elif [[ "$metric" == "ratio" ]]; then
        max_scale=4
      else
        # score metric: compute max_scale from schema criteria array length
        max_scale=$(( $(yq -r ".dimensions[$i].criteria | length" "$SCHEMA") - 1 ))
        [[ "$max_scale" -le 0 ]] && max_scale=1
      fi

      # Parse target value (strip operator)
      target_op=""
      target_num=""
      case "$target" in
        ">="*) target_op=">="; target_num=$(echo "$target" | sed 's/>= *//') ;;
        "<="*) target_op="<="; target_num=$(echo "$target" | sed 's/<= *//') ;;
        [0-9]*) target_op="<="; target_num="$target" ;;  # bare number = exact/at-most
        *) target_op=""; target_num="" ;;
      esac

      if [[ -n "$target_op" && -n "$target_num" ]]; then
        if [[ "$target_op" == ">=" ]]; then
          # Higher is better. score_raw/max_scale → 0-100.
          score_val=$(echo "$score_raw $max_scale" | awk '{printf "%.0f", ($1 / $2) * 100}')
          # Map target to ordinal threshold.
          if [[ "$metric" == "ratio" ]]; then
            # ratio target like ">= 0.50" → need score_raw >= 2 (40-60% bucket or higher)
            target_bucket=$(echo "$target_num $max_scale" | awk '{printf "%.0f", $1 * $2}')
          else
            # count target like ">= 3" → need score_raw >= 3
            target_bucket=$(printf "%.0f" "$target_num")
          fi
          if (( $(echo "$score_raw >= $target_bucket" | bc -l) )); then pass=true; fi
        else
          # Lower is better (<=). Score 100 when at/below target, scale
          # down as score_raw exceeds target. Shows proximity to target,
          # not distance from worst.
          # score = max(0, 100 - ((score_raw - target_bucket) / max_scale) * 100)
          # When score_raw <= target_bucket → 100 (at or below target)
          # When score_raw > target_bucket → decreases toward 0
          if [[ "$metric" == "ratio" ]]; then
            _tb=$(echo "$target_num $max_scale" | awk '{printf "%.0f", $1 * $2}')
          else
            _tb=$(printf "%.0f" "$target_num")
          fi
          score_val=$(echo "$score_raw $_tb $max_scale" | awk '{
            if ($1 <= $2) printf "%.0f", 100;
            else { v = 100 - (($1 - $2) / $3) * 100; if (v < 0) v = 0; printf "%.0f", v }
          }')
          # Map target to ordinal threshold.
          if [[ "$metric" == "ratio" ]]; then
            # ratio target like "<= 0.30" → pass if score_raw <= 1 (20-40% bucket)
            target_bucket=$(echo "$target_num $max_scale" | awk '{printf "%.0f", $1 * $2}')
          else
            # count target like "<= 5" → pass if score_raw <= 4 (bucket "4")
            # count target like "0" → pass if score_raw == 0
            target_bucket=$(printf "%.0f" "$target_num")
          fi
          if (( $(echo "$score_raw <= $target_bucket" | bc -l) )); then pass=true; fi
        fi
      else
        score_val=50; detail="${detail:+$detail; }no target comparison"
      fi
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

  # Deterministic override wins over the model answer.
  if _det=$(det_override "$name"); then
    read -r _dscore _dpass _ddetail <<<"$_det"
    _ddetail="${_det#* * }"
    score_val="$_dscore"
    pass="$_dpass"
    confidence=1.0
    detail="$_ddetail"
  fi

  # T4 scorer: no logits, so no calibrated confidence (t4-static-score.sh
  # derives agreement across runs). Deterministic overrides keep 1.0.
  if [[ "$SCORER" != sdm && "$confidence" != 1.0 ]]; then confidence=null; fi

  # Confidence-based reliability flag (model-agnostic; informational, score unchanged)
  low_conf=false
  if [[ "$confidence" != null ]] && (( $(echo "$(awk "BEGIN {printf \"%.10f\", $confidence}") < $MIN_CONF" | bc -l) )); then
    low_conf=true
    LOW_CONF_COUNT=$((LOW_CONF_COUNT + 1))
    LOW_CONF_NAMES="${LOW_CONF_NAMES:+$LOW_CONF_NAMES, }$name"
    detail="${detail:+$detail; }low confidence ($(awk "BEGIN {printf \"%.2f\", $confidence}"))"
  fi

  dim_json=$(jq -n \
    --arg n "$name" \
    --argjson p "$pass" \
    --argjson s "$score_val" \
    --argjson c "$confidence" \
    --arg d "$detail" \
    --argjson w "$weight" \
    --argjson lm "$label_mass" \
    --argjson ao "$(echo "$argmax_ok" | jq -R 'if . == "true" then true else false end')" \
    --argjson lc "$low_conf" \
    '{name: $n, pass: $p, score: $s, confidence: $c, detail: $d, weight: $w, label_mass: $lm, argmax_is_label: $ao, low_confidence: $lc}')

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
  --argjson low_conf "$LOW_CONF_COUNT" \
  --arg scorer "$SCORER" \
  '{
    skill: $skill,
    schema_type: $schema_type,
    schema_version: $schema_version,
    scorer: $scorer,
    timestamp: $ts,
    aggregate_score: $agg,
    band: $band,
    pass_rate: $pass_rate,
    dimensions_total: $total_dims,
    dimensions_passed: $total_pass,
    low_confidence_count: $low_conf,
    dimensions: $dims
  }')

# --- Output ---

echo "$RECORD" | jq '.'

# --- Persist if observation type and skill has observations dir ---

if [[ "$SCHEMA_TYPE" == "operable" && "$SCORER" == sdm ]]; then   # T4 runs never persist here
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

if (( LOW_CONF_COUNT > 0 )); then
  log "WARNING: $LOW_CONF_COUNT dimension(s) below confidence $MIN_CONF: $LOW_CONF_NAMES — treat these scores as uncertain"
fi
log "Evaluation complete: $SKILL_NAME — $AGGREGATE ($BAND) [$TOTAL_PASS/$TOTAL_DIMS passed]"
