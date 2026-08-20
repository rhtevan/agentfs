#!/usr/bin/env bash
# gen-profile-recipe.sh — Generate an on-demand task recipe for a named profile.
#
# Usage:
#   bash gen-profile-recipe.sh <profile-name> <task-description> [OPTIONS]
#
# Options:
#   --root <dir>           Project root (default: .)
#   --output <file>        Output recipe file path
#                          (default: .agents/profiles/<name>/output/recipe-<timestamp>.yaml)
#   --structured           Add response.json_schema for structured JSON output
#   --max-turns <n>        Max turns for the recipe session (default: 15)
#   --provider <name>      Override provider for this session
#   --model <name>         Override model for this session
#   --run                  Execute the generated recipe immediately after generating
#   --quiet                Suppress non-response output when running (implies --run)
#
# Exit codes:
#   0 = recipe written (and optionally run successfully)
#   1 = error
#
# Examples:
#   # Generate only
#   bash gen-profile-recipe.sh verifier "Review the current plan for gaps"
#
#   # Generate and run, capturing output
#   bash gen-profile-recipe.sh verifier "Review plan" --run --quiet
#
#   # Generate with structured JSON output
#   bash gen-profile-recipe.sh verifier "Review plan" --structured --run --quiet

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────
if [[ $# -lt 2 ]]; then
  echo "[gen-profile-recipe] ERROR: profile-name and task-description required." >&2
  echo "  Usage: bash gen-profile-recipe.sh <profile-name> <task-description> [OPTIONS]" >&2
  exit 1
fi

PROFILE_NAME="$1"
TASK_DESC="$2"
shift 2

ROOT="."
OUTPUT_FILE=""
STRUCTURED=false
MAX_TURNS=15
PROVIDER_OVERRIDE=""
MODEL_OVERRIDE=""
RUN_AFTER=false
QUIET=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --structured)
      STRUCTURED=true
      shift
      ;;
    --max-turns)
      MAX_TURNS="$2"
      shift 2
      ;;
    --provider)
      PROVIDER_OVERRIDE="$2"
      shift 2
      ;;
    --model)
      MODEL_OVERRIDE="$2"
      shift 2
      ;;
    --run)
      RUN_AFTER=true
      shift
      ;;
    --quiet)
      QUIET=true
      RUN_AFTER=true
      shift
      ;;
    *)
      echo "[gen-profile-recipe] ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
AGENTS="$ROOT/.agents"
PROFILE_DIR="$AGENTS/profiles/$PROFILE_NAME"

# ── Validate ─────────────────────────────────────────────────────────
if [[ ! -d "$PROFILE_DIR" ]]; then
  echo "[gen-profile-recipe] ERROR: Profile '$PROFILE_NAME' not found at $PROFILE_DIR" >&2
  echo "  Run: bash create-profile.sh $PROFILE_NAME" >&2
  exit 1
fi

if [[ ! -f "$PROFILE_DIR/SOUL.md" ]]; then
  echo "[gen-profile-recipe] ERROR: $PROFILE_DIR/SOUL.md not found." >&2
  echo "  Run: bash author-soul.sh --path $PROFILE_DIR/SOUL.md --role-hint $PROFILE_NAME" >&2
  exit 1
fi

# ── Resolve output path ───────────────────────────────────────────────
mkdir -p "$PROFILE_DIR/output"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
if [[ -z "$OUTPUT_FILE" ]]; then
  # Slugify task description for filename
  SLUG=$(echo "$TASK_DESC" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | cut -c1-40 | sed 's/-$//')
  OUTPUT_FILE="$PROFILE_DIR/output/recipe-${TIMESTAMP}-${SLUG}.yaml"
fi

# ── Read SOUL content ─────────────────────────────────────────────────
SOUL_CONTENT=$(cat "$PROFILE_DIR/SOUL.md")

# ── Build settings block ──────────────────────────────────────────────
SETTINGS_BLOCK=""
if [[ -n "$PROVIDER_OVERRIDE" || -n "$MODEL_OVERRIDE" || "$MAX_TURNS" != "15" ]]; then
  SETTINGS_BLOCK="settings:"
  [[ -n "$PROVIDER_OVERRIDE" ]] && SETTINGS_BLOCK+="\n  goose_provider: $PROVIDER_OVERRIDE"
  [[ -n "$MODEL_OVERRIDE" ]] && SETTINGS_BLOCK+="\n  goose_model: $MODEL_OVERRIDE"
  SETTINGS_BLOCK+="\n  max_turns: $MAX_TURNS"
fi

# ── Build response block (structured output) ──────────────────────────
RESPONSE_BLOCK=""
if [[ "$STRUCTURED" == true ]]; then
  RESPONSE_BLOCK=$(cat << 'RESPONSEEOF'
response:
  json_schema:
    type: object
    properties:
      summary:
        type: string
        description: "Brief summary of findings or output"
      findings:
        type: array
        items:
          type: string
        description: "List of specific findings, issues, or results"
      verdict:
        type: string
        enum: [pass, fail, warn, info]
        description: "Overall verdict"
      recommendations:
        type: array
        items:
          type: string
        description: "Actionable recommendations (optional)"
    required: [summary, findings, verdict]
RESPONSEEOF
  )
fi

# ── Write recipe YAML ─────────────────────────────────────────────────
{
  cat << HEADEREOF
version: "1.0.0"
title: "$PROFILE_NAME — $(echo "$TASK_DESC" | cut -c1-60)"
description: >-
  On-demand task recipe for $PROFILE_NAME profile.
  Generated: $(date '+%Y-%m-%d %H:%M')
  Task: $TASK_DESC
HEADEREOF

  if [[ -n "$SETTINGS_BLOCK" ]]; then
    echo -e "$SETTINGS_BLOCK"
  fi

  echo "instructions: |"
  echo "$SOUL_CONTENT" | sed 's/^/  /'
  echo ""
  echo "prompt: |"
  echo "  $TASK_DESC"
  echo ""
  echo "  Work through this task systematically. When complete, provide a"
  echo "  clear summary of your findings and any recommendations."

  if [[ -n "$RESPONSE_BLOCK" ]]; then
    echo ""
    echo "$RESPONSE_BLOCK"
  fi
} > "$OUTPUT_FILE"

echo "[gen-profile-recipe] ✓ Recipe written: $OUTPUT_FILE"

# ── Optionally run the recipe ─────────────────────────────────────────
if [[ "$RUN_AFTER" == true ]]; then
  echo "[gen-profile-recipe] Running recipe..."
  echo ""

  RUN_ARGS=("--recipe" "$OUTPUT_FILE" "--no-session")
  [[ "$QUIET" == true ]] && RUN_ARGS+=("--quiet")
  [[ -n "$PROVIDER_OVERRIDE" ]] && RUN_ARGS+=("--provider" "$PROVIDER_OVERRIDE")
  [[ -n "$MODEL_OVERRIDE" ]] && RUN_ARGS+=("--model" "$MODEL_OVERRIDE")

  RESULT_FILE="$PROFILE_DIR/output/result-${TIMESTAMP}.md"

  if goose run "${RUN_ARGS[@]}" > "$RESULT_FILE" 2>&1; then
    echo "[gen-profile-recipe] ✓ Result saved: $RESULT_FILE"
    echo ""
    cat "$RESULT_FILE"
  else
    echo "[gen-profile-recipe] ⚠ Recipe run exited with error. Output at: $RESULT_FILE" >&2
    cat "$RESULT_FILE" >&2
    exit 1
  fi
fi
