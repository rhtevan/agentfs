#!/bin/bash
# score-all.sh — Batch score all skills for Quality + Observable
#
# Iterates skills, runs gather-skill-state.sh + sdm-evaluate.sh
# for Quality and Observable schemas, persists results to scores.yaml.
#
# Usage:
#   score-all.sh [--force] [--tier T1|T2|T3|T4] [--dry-run] [--sleep N]
#
# Flags:
#   --force     Re-score skills that already have scores.yaml
#   --tier TX   Only score skills matching the given model-tier
#   --dry-run   List what would be scored without making SDM calls
#   --sleep N   Seconds to sleep between skills (default: 2)
#
# Exit codes:
#   0 — All skills scored successfully
#   1 — One or more skills failed (partial results persisted)
#
# Prerequisites:
#   - SDM endpoint running at localhost:9000
#   - gather-skill-state.sh, sdm-evaluate.sh in ~/.agents/scripts/
#   - Quality and Observable schemas in ~/.agents/skills/schemas/

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.agents/skills"
QUALITY_SCHEMA="$SKILLS_DIR/schemas/quality.yaml"
OBSERVABLE_SCHEMA="$SKILLS_DIR/schemas/observable.yaml"
OPERABLE_SCHEMA="$SKILLS_DIR/schemas/operable.yaml"

# --- Argument parsing ---
FORCE=false
TIER_FILTER=""
DRY_RUN=false
SLEEP_SECS=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --tier) TIER_FILTER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --sleep) SLEEP_SECS="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Validate prerequisites ---
if [[ ! -f "$QUALITY_SCHEMA" ]]; then
  echo "ERROR: Quality schema not found at $QUALITY_SCHEMA" >&2
  exit 1
fi
if [[ ! -f "$OBSERVABLE_SCHEMA" ]]; then
  echo "ERROR: Observable schema not found at $OBSERVABLE_SCHEMA" >&2
  exit 1
fi

# --- Collect skills to score ---
TOTAL=0
SKIPPED=0
SCORED=0
FAILED=0
FAILED_LIST=""

echo "═══════════════════════════════════════════"
echo "  score-all.sh — Batch QOO Scoring"
echo "═══════════════════════════════════════════"
echo ""

for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skill_name=$(basename "$skill_dir")

  # Skip schemas directory and other non-skill dirs
  [[ "$skill_name" == "schemas" ]] && continue

  # Read model-tier from frontmatter
  model_tier=$(grep -oP 'model-tier:\s*\K\S+' "$skill_dir/SKILL.md" 2>/dev/null | head -1 || echo "unknown")

  # Apply tier filter
  if [[ -n "$TIER_FILTER" && "$model_tier" != "$TIER_FILTER" ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Skip if already scored (unless --force)
  if [[ "$FORCE" == "false" && -f "$skill_dir/scores.yaml" ]]; then
    # Check if quality section exists
    if grep -q '^quality:' "$skill_dir/scores.yaml" 2>/dev/null; then
      SKIPPED=$((SKIPPED + 1))
      if [[ "$DRY_RUN" == "true" ]]; then
        echo "  SKIP  $skill_name ($model_tier) — already scored"
      fi
      continue
    fi
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  SCORE $skill_name ($model_tier)"
    SCORED=$((SCORED + 1))
    continue
  fi

  # --- Score this skill ---
  echo "────────────────────────────────────────"
  echo "Scoring: $skill_name ($model_tier)"
  echo "────────────────────────────────────────"

  # Step 1: Gather evidence
  evidence_file="/tmp/score-all-evidence-${skill_name}.txt"
  if ! bash "$SCRIPTS_DIR/gather-skill-state.sh" "$skill_dir" > "$evidence_file" 2>/dev/null; then
    echo "  ❌ gather-skill-state.sh failed for $skill_name"
    FAILED=$((FAILED + 1))
    FAILED_LIST="$FAILED_LIST $skill_name"
    continue
  fi

  # Step 2: Quality evaluation
  echo "  Evaluating Quality..."
  quality_json=$(bash "$SCRIPTS_DIR/sdm-evaluate.sh" "$skill_dir" \
    "$QUALITY_SCHEMA" \
    --evidence "$evidence_file" 2>/dev/null) || {
    echo "  ❌ Quality SDM evaluation failed for $skill_name"
    FAILED=$((FAILED + 1))
    FAILED_LIST="$FAILED_LIST $skill_name"
    continue
  }

  quality_score=$(echo "$quality_json" | jq -r '.aggregate_score // 0')
  quality_band=$(echo "$quality_json" | jq -r '.band // "Unknown"')

  # Step 3: Observable evaluation
  # Uses --evidence with stripped gather output. The sdm_delegation evidence line
  # is formatted as "sdm_delegation: YES/NO" to match what the 14B SDM expects.
  # Raw SKILL.md evidence causes false negatives on meta-skills (skill-eval, etc.)
  # whose domain content mentions trace/SDM/fabrication.
  echo "  Evaluating Observable..."
  observable_json=$(bash "$SCRIPTS_DIR/sdm-evaluate.sh" "$skill_dir" \
    "$OBSERVABLE_SCHEMA" \
    --evidence "$evidence_file" 2>/dev/null) || {
    echo "  ❌ Observable SDM evaluation failed for $skill_name"
    FAILED=$((FAILED + 1))
    FAILED_LIST="$FAILED_LIST $skill_name"
    continue
  }

  observable_score=$(echo "$observable_json" | jq -r '.aggregate_score // 0')
  observable_band=$(echo "$observable_json" | jq -r '.band // "Unknown"')

  # Step 3b: Operable (Build) evaluation — BMBT only
  # Runtime CECX dimensions require trace evidence from actual execution.
  # Without traces, CECX scores are unreliable (SDM guesses from static analysis).
  # --phase build restricts to BMBT (has_bones, has_muscle, has_brain, has_harness).
  echo "  Evaluating Operable (Build)..."
  build_json=$(bash "$SCRIPTS_DIR/sdm-evaluate.sh" "$evidence_file" \
    "$OPERABLE_SCHEMA" \
    --phase build 2>/dev/null) || {
    echo "  ⚠️  Operable SDM evaluation failed for $skill_name (continuing with Q+O only)"
    build_json=""
  }

  build_score=""
  build_band="not-evaluated"
  if [[ -n "$build_json" ]]; then
    build_score=$(echo "$build_json" | jq -r '.aggregate_score // 0')
    build_band=$(echo "$build_json" | jq -r '.band // "Unknown"')
  fi

  # Step 4: Compute qoo-qualified (tier-aware thresholds)
  # T1/T2: Q≥75 + O≥75 + B≥75 (all three gated)
  # T3:    Q≥50 + O≥50 + B≥75 (relaxed Q+O thresholds)
  # T4:    B≥75 only (Q+O informational)
  qoo_qualified="false"
  qualification_rule="$model_tier"
  if [[ "$build_band" != "not-evaluated" ]]; then
    case "$model_tier" in
      T4)
        # T4: Only Build is gated. Quality + Observable are informational.
        if [[ "$build_band" =~ ^(Tunable|Operable)$ ]]; then
          qoo_qualified="true"
        fi
        ;;
      T3)
        # T3: Relaxed — Q≥50 (Re-engineer+), O≥50 (Re-engineer+), B≥75 (Tunable+)
        q_int=$(echo "$quality_score" | awk '{printf "%d", $1}')
        o_int=$(echo "$observable_score" | awk '{printf "%d", $1}')
        if [[ $q_int -ge 50 && $o_int -ge 50 ]] && \
           [[ "$build_band" =~ ^(Tunable|Operable)$ ]]; then
          qoo_qualified="true"
        fi
        ;;
      T1|T2|*)
        # T1/T2 (and unknown): Strict — Q≥75, O≥75, B≥75 (all Tunable+)
        if [[ "$quality_band" =~ ^(Tunable|Operable)$ ]] && \
           [[ "$observable_band" =~ ^(Tunable|Operable)$ ]] && \
           [[ "$build_band" =~ ^(Tunable|Operable)$ ]]; then
          qoo_qualified="true"
        fi
        ;;
    esac
  fi

  # Step 5: Write scores.yaml
  version=$(grep -oP 'version:\s*"\K[^"]+' "$skill_dir/SKILL.md" 2>/dev/null | head -1 || echo "unknown")
  timestamp=$(date -Iseconds)

  # Build quality dimensions YAML
  quality_dims=""
  dim_count=$(echo "$quality_json" | jq '.dimensions | length')
  for ((i=0; i<dim_count; i++)); do
    dim_name=$(echo "$quality_json" | jq -r ".dimensions[$i].name")
    dim_score=$(echo "$quality_json" | jq -r ".dimensions[$i].score")
    dim_pass=$(echo "$quality_json" | jq -r ".dimensions[$i].pass")
    dim_conf=$(echo "$quality_json" | jq -r ".dimensions[$i].confidence")
    quality_dims="${quality_dims}    ${dim_name}:
      score: ${dim_score}
      pass: ${dim_pass}
      confidence: ${dim_conf}
"
  done

  # Build observable dimensions YAML
  observable_dims=""
  dim_count=$(echo "$observable_json" | jq '.dimensions | length')
  for ((i=0; i<dim_count; i++)); do
    dim_name=$(echo "$observable_json" | jq -r ".dimensions[$i].name")
    dim_score=$(echo "$observable_json" | jq -r ".dimensions[$i].score")
    dim_pass=$(echo "$observable_json" | jq -r ".dimensions[$i].pass")
    dim_conf=$(echo "$observable_json" | jq -r ".dimensions[$i].confidence")
    observable_dims="${observable_dims}    ${dim_name}:
      score: ${dim_score}
      pass: ${dim_pass}
      confidence: ${dim_conf}
"
  done

  # Build operable dimensions YAML
  build_dims=""
  if [[ -n "$build_json" ]]; then
    dim_count=$(echo "$build_json" | jq '.dimensions | length')
    for ((i=0; i<dim_count; i++)); do
      dim_name=$(echo "$build_json" | jq -r ".dimensions[$i].name")
      dim_score=$(echo "$build_json" | jq -r ".dimensions[$i].score")
      dim_pass=$(echo "$build_json" | jq -r ".dimensions[$i].pass")
      dim_conf=$(echo "$build_json" | jq -r ".dimensions[$i].confidence")
      build_dims="${build_dims}      ${dim_name}:
        score: ${dim_score}
        pass: ${dim_pass}
        confidence: ${dim_conf}
"
    done
  fi

  cat > "$skill_dir/scores.yaml" <<SCORES_EOF
# scores.yaml — $skill_name
skill: $skill_name
version: $version
model_tier: $model_tier
qualification_rule: $qualification_rule
qoo-qualified: $qoo_qualified
quality:
  schema: quality.yaml
  aggregate_score: $quality_score
  band: $quality_band
  dimensions:
${quality_dims}  evaluated: '$timestamp'
observable:
  schema: observable.yaml
  aggregate_score: $observable_score
  band: $observable_band
  dimensions:
${observable_dims}  evaluated: '$timestamp'
operable:
  build:
    schema: operable.yaml
    aggregate_score: $build_score
    band: $build_band
    dimensions:
${build_dims}    evaluated: '$timestamp'
history:
- date: '$timestamp'
  type: full
  quality_score: $quality_score
  quality_band: $quality_band
  observable_score: $observable_score
  observable_band: $observable_band
  build_score: $build_score
  build_band: $build_band
  note: 'Batch scored by score-all.sh (build+observable gated, quality informational)'
SCORES_EOF

  echo "  ✅ $skill_name: Q=$quality_score($quality_band) O=$observable_score($observable_band) B=$build_score($build_band) qoo=$qoo_qualified"
  SCORED=$((SCORED + 1))

  # Rate limiting
  if [[ "$SLEEP_SECS" -gt 0 ]]; then
    sleep "$SLEEP_SECS"
  fi
done

# --- Summary ---
echo ""
echo "═══════════════════════════════════════════"
echo "  Batch Scoring Complete"
echo "═══════════════════════════════════════════"
echo "  Total skills:  $TOTAL"
echo "  Scored:        $SCORED"
echo "  Skipped:       $SKIPPED (already scored)"
echo "  Failed:        $FAILED"
if [[ -n "$FAILED_LIST" ]]; then
  echo "  Failed skills: $FAILED_LIST"
fi
echo "═══════════════════════════════════════════"

[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
