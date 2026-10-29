#!/bin/bash
# sdm-call.sh — Make a structured decision call via SystemOne API (/v1/systemone)
#
# Usage:
#   sdm-call.sh --input "evidence text" --questions '<json-object>'
#   sdm-call.sh --input "evidence text" --predicate "question_name" "Is X true?"
#   sdm-call.sh --input "evidence text" --choice "question_name" "Which option?" "a,b,c"
#   sdm-call.sh --input "evidence text" --score "question_name" "Rate X." "low,medium,high"
#   sdm-call.sh --input "evidence text" --questions-file questions.json
#
# Environment:
#   SDM_ENDPOINT  — Base URL (default: http://localhost:9000)
#   SDM_MODEL     — Model ID (default: auto-detect from /v1/models)
#   SDM_TIMEOUT   — Request timeout in seconds (default: 10)
#   SDM_RETRIES   — Max retries on 429 (default: 3)
#
# Exit codes:
#   0 — Success (JSON response on stdout)
#   1 — SDM error (bad request, model error)
#   2 — Network error (endpoint unreachable)
#   3 — Usage error (bad arguments)
#
# API: SystemOne (/v1/systemone)
#   Request:  {model, state, questions: {name: {type, instructions, ...}}}
#   Response: {answers: {name: {type, noul|choice|score, probabilities, confidence}},
#              diagnostics: {name: {label_mass, argmax_is_label}}}
#   Question types: noul (yes/no), choice (multi-option), score (ordinal)

set -euo pipefail

SDM_ENDPOINT="${SDM_ENDPOINT:-http://localhost:9000}"
SDM_TIMEOUT="${SDM_TIMEOUT:-10}"
SDM_RETRIES="${SDM_RETRIES:-3}"

# --- Helpers ---

die()  { echo "ERROR: $*" >&2; exit 3; }
log()  { echo "[sdm-call] $*" >&2; }

resolve_model() {
  if [[ -n "${SDM_MODEL:-}" ]]; then
    echo "$SDM_MODEL"
    return
  fi
  local model
  model=$(curl -s --max-time "$SDM_TIMEOUT" "${SDM_ENDPOINT}/v1/models" 2>/dev/null \
    | jq -r '.data[0].id // empty' 2>/dev/null) || true
  if [[ -z "$model" ]]; then
    log "WARNING: Could not auto-detect model. Using 'default'."
    echo "default"
  else
    echo "$model"
  fi
}

# --- Question builders (SystemOne format) ---
# Each builds a JSON fragment: {"type": "...", "instructions": "...", ...}
# The name is used as the dict key, not embedded in the value.

build_predicate() {
  local name="$1" instructions="$2"
  # SystemOne uses "noul" type for yes/no predicates
  jq -n --arg n "$name" --arg i "$instructions" \
    '{($n): {type: "noul", instructions: $i}}'
}

build_choice() {
  local name="$1" instructions="$2" choices_csv="$3"
  # SystemOne uses criteria dict: {option: null} for each choice
  local criteria
  criteria=$(echo "$choices_csv" | tr ',' '\n' | jq -R '{(.): null}' | jq -s 'add')
  jq -n --arg n "$name" --arg i "$instructions" --argjson c "$criteria" \
    '{($n): {type: "choice", instructions: $i, criteria: $c}}'
}

build_score() {
  local name="$1" instructions="$2" levels_csv="$3"
  # SystemOne uses criteria array for score levels
  local criteria
  criteria=$(echo "$levels_csv" | tr ',' '\n' | jq -R '.' | jq -s '.')
  jq -n --arg n "$name" --arg i "$instructions" --argjson c "$criteria" \
    '{($n): {type: "score", instructions: $i, criteria: $c}}'
}

call_sdm() {
  local model="$1" state="$2" questions="$3"
  local payload
  payload=$(jq -n --arg m "$model" --arg s "$state" --argjson q "$questions" \
    '{model: $m, state: $s, questions: $q}')

  local attempt=0 response http_code
  while (( attempt < SDM_RETRIES )); do
    attempt=$((attempt + 1))

    local tmpfile
    tmpfile=$(mktemp)
    http_code=$(curl -s -o "$tmpfile" -w '%{http_code}' \
      --max-time "$SDM_TIMEOUT" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "${SDM_ENDPOINT}/v1/systemone" 2>/dev/null) || http_code="000"
    response=$(cat "$tmpfile")
    rm -f "$tmpfile"

    case "$http_code" in
      200)
        echo "$response"
        return 0
        ;;
      429)
        log "Rate limited (attempt $attempt/$SDM_RETRIES). Retrying in 1s..."
        sleep 1
        continue
        ;;
      000)
        log "Connection refused — SDM endpoint not reachable at ${SDM_ENDPOINT}"
        return 2
        ;;
      400|422)
        log "Bad request (HTTP $http_code): $response"
        return 1
        ;;
      *)
        log "SDM error (HTTP $http_code): $response"
        return 1
        ;;
    esac
  done

  log "Exhausted $SDM_RETRIES retries on 429."
  return 1
}

# --- Main ---

INPUT=""
QUESTIONS="{}"
QUESTIONS_FILE=""
QUESTION_PARTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)
      [[ $# -ge 2 ]] || die "--input requires a value"
      INPUT="$2"; shift 2 ;;
    --questions)
      [[ $# -ge 2 ]] || die "--questions requires a JSON object"
      QUESTIONS="$2"; shift 2 ;;
    --questions-file)
      [[ $# -ge 2 ]] || die "--questions-file requires a file path"
      QUESTIONS_FILE="$2"; shift 2 ;;
    --predicate)
      [[ $# -ge 3 ]] || die "--predicate requires <name> <instructions>"
      QUESTION_PARTS+=("$(build_predicate "$2" "$3")")
      shift 3 ;;
    --choice)
      [[ $# -ge 4 ]] || die "--choice requires <name> <instructions> <choices-csv>"
      QUESTION_PARTS+=("$(build_choice "$2" "$3" "$4")")
      shift 4 ;;
    --score)
      [[ $# -ge 4 ]] || die "--score requires <name> <instructions> <levels-csv>"
      QUESTION_PARTS+=("$(build_score "$2" "$3" "$4")")
      shift 4 ;;
    -h|--help)
      sed -n '2,/^$/{ s/^# //; s/^#//; p }' "$0"
      exit 0 ;;
    *)
      die "Unknown argument: $1" ;;
  esac
done

[[ -n "$INPUT" ]] || die "--input is required"

# Build questions from parts, file, or direct JSON
if [[ ${#QUESTION_PARTS[@]} -gt 0 ]]; then
  # Merge individual question dicts into one object
  QUESTIONS=$(printf '%s\n' "${QUESTION_PARTS[@]}" | jq -s 'add')
elif [[ -n "$QUESTIONS_FILE" ]]; then
  [[ -f "$QUESTIONS_FILE" ]] || die "Questions file not found: $QUESTIONS_FILE"
  QUESTIONS=$(cat "$QUESTIONS_FILE")
fi

# Validate questions is a non-empty object
q_count=$(echo "$QUESTIONS" | jq 'keys | length' 2>/dev/null) || die "Invalid questions JSON"
[[ "$q_count" -gt 0 ]] || die "At least one question is required"

MODEL=$(resolve_model)
call_sdm "$MODEL" "$INPUT" "$QUESTIONS"
