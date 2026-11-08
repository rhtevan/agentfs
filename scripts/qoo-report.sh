#!/bin/bash
# qoo-report.sh — Portfolio QOO Dashboard
#
# Reads all scores.yaml files and produces a portfolio-level report.
#
# Usage:
#   qoo-report.sh [--tier T1|T2|T3|T4] [--unqualified-only]
#
# Exit codes:
#   0 — Report generated
#   1 — No skills found

set -euo pipefail

SKILLS_DIR="$HOME/.agents/skills"
TIER_FILTER=""
UNQUALIFIED_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER_FILTER="$2"; shift 2 ;;
    --unqualified-only) UNQUALIFIED_ONLY=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# --- Counters ---
TOTAL=0
SCORED=0
UNSCORED=0
QUALIFIED=0
EXEMPT=0

T1_TOTAL=0; T1_SCORED=0; T1_QUALIFIED=0
T2_TOTAL=0; T2_SCORED=0; T2_QUALIFIED=0
T3_TOTAL=0; T3_SCORED=0; T3_QUALIFIED=0
T4_TOTAL=0; T4_SCORED=0; T4_QUALIFIED=0
NA_TOTAL=0

UNQUALIFIED_LIST=""
UNSCORED_LIST=""
IMPROVEMENT_LIST=""

for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skill_name=$(basename "$skill_dir")
  [[ "$skill_name" == "schemas" ]] && continue

  model_tier=$(grep -oP 'model-tier:\s*\K\S+' "$skill_dir/SKILL.md" 2>/dev/null || echo "unknown")

  # Apply tier filter
  if [[ -n "$TIER_FILTER" && "$model_tier" != "$TIER_FILTER" ]]; then
    continue
  fi

  TOTAL=$((TOTAL + 1))

  # Count by tier
  case "$model_tier" in
    T1) T1_TOTAL=$((T1_TOTAL + 1)) ;;
    T2) T2_TOTAL=$((T2_TOTAL + 1)) ;;
    T3) T3_TOTAL=$((T3_TOTAL + 1)) ;;
    T4) T4_TOTAL=$((T4_TOTAL + 1)) ;;
    n/a) NA_TOTAL=$((NA_TOTAL + 1)); EXEMPT=$((EXEMPT + 1)); continue ;;
  esac

  # Check if scored
  if [[ ! -f "$skill_dir/scores.yaml" ]] || ! grep -q '^quality:' "$skill_dir/scores.yaml" 2>/dev/null; then
    UNSCORED=$((UNSCORED + 1))
    UNSCORED_LIST="${UNSCORED_LIST}  ${skill_name} (${model_tier})\n"
    continue
  fi

  SCORED=$((SCORED + 1))
  case "$model_tier" in
    T1) T1_SCORED=$((T1_SCORED + 1)) ;;
    T2) T2_SCORED=$((T2_SCORED + 1)) ;;
    T3) T3_SCORED=$((T3_SCORED + 1)) ;;
    T4) T4_SCORED=$((T4_SCORED + 1)) ;;
  esac

  # Check qualification — match only top-level qoo-qualified, not inside notes
  qoo=$(grep -m1 '^qoo-qualified:' "$skill_dir/scores.yaml" 2>/dev/null | sed 's/.*: *//' || echo "false")
  q_score=$(grep -A5 '^quality:' "$skill_dir/scores.yaml" | grep 'aggregate_score' | head -1 | sed 's/.*: *//' || echo "0")
  q_band=$(grep -A5 '^quality:' "$skill_dir/scores.yaml" | grep 'band:' | head -1 | sed 's/.*: *//' || echo "?")
  o_score=$(grep -A5 '^observable:' "$skill_dir/scores.yaml" | grep 'aggregate_score' | head -1 | sed 's/.*: *//' || echo "0")
  o_band=$(grep -A5 '^observable:' "$skill_dir/scores.yaml" | grep 'band:' | head -1 | sed 's/.*: *//' || echo "?")

  # Build score
  b_band="n/a"
  if grep -q '  build:' "$skill_dir/scores.yaml" 2>/dev/null; then
    b_band=$(sed -n '/  build:/,/  runtime:/p' "$skill_dir/scores.yaml" | grep 'band:' | head -1 | sed 's/.*: *//' || echo "n/a")
  fi

  if [[ "$qoo" == "true" ]]; then
    QUALIFIED=$((QUALIFIED + 1))
    case "$model_tier" in
      T1) T1_QUALIFIED=$((T1_QUALIFIED + 1)) ;;
      T2) T2_QUALIFIED=$((T2_QUALIFIED + 1)) ;;
      T3) T3_QUALIFIED=$((T3_QUALIFIED + 1)) ;;
      T4) T4_QUALIFIED=$((T4_QUALIFIED + 1)) ;;
    esac
    if [[ "$UNQUALIFIED_ONLY" == "true" ]]; then
      continue
    fi
  else
    UNQUALIFIED_LIST="${UNQUALIFIED_LIST}  ${skill_name} (${model_tier}) — Q:${q_score}/${q_band} O:${o_score}/${o_band} B:${b_band}\n"
  fi
done

# --- Generate progress bars ---
make_bar() {
  local filled=$1
  local total=$2
  local width=20
  if [[ "$total" -eq 0 ]]; then
    printf '%0.s░' $(seq 1 $width)
    return
  fi
  local fill=$((filled * width / total))
  local empty=$((width - fill))
  printf '%0.s█' $(seq 1 $fill) 2>/dev/null || true
  printf '%0.s░' $(seq 1 $empty) 2>/dev/null || true
}

t1_pct=0; [[ $T1_TOTAL -gt 0 ]] && t1_pct=$((T1_QUALIFIED * 100 / T1_TOTAL))
t2_pct=0; [[ $T2_TOTAL -gt 0 ]] && t2_pct=$((T2_QUALIFIED * 100 / T2_TOTAL))
t3_pct=0; [[ $T3_TOTAL -gt 0 ]] && t3_pct=$((T3_QUALIFIED * 100 / T3_TOTAL))
t4_pct=0; [[ $T4_TOTAL -gt 0 ]] && t4_pct=$((T4_QUALIFIED * 100 / T4_TOTAL))
all_qual=$((QUALIFIED + EXEMPT))
all_pct=0; [[ $TOTAL -gt 0 ]] && all_pct=$((all_qual * 100 / TOTAL))

# --- Output report ---
echo ""
echo "QOO Portfolio Report — $TOTAL skills"
echo "═══════════════════════════════════════════════════"
echo ""
echo "Tier Distribution:"
echo "  T1 (Any model):   $T1_TOTAL skills"
echo "  T2 (Mid-range):   $T2_TOTAL skills"
echo "  T3 (Strong):      $T3_TOTAL skills"
echo "  T4 (Frontier):    $T4_TOTAL skills"
if [[ $NA_TOTAL -gt 0 ]]; then
  echo "  n/a (Exempt):     $NA_TOTAL skills"
fi
echo ""
echo "Scoring Status:"
echo "  Scored:   $SCORED / $TOTAL"
echo "  Unscored: $UNSCORED"
echo ""
echo "Qualification Status by Tier:"
printf "  T1:  %2d/%-2d qualified (%3d%%)  %s\n" "$T1_QUALIFIED" "$T1_TOTAL" "$t1_pct" "$(make_bar $T1_QUALIFIED $T1_TOTAL)"
printf "  T2:  %2d/%-2d qualified (%3d%%)  %s\n" "$T2_QUALIFIED" "$T2_TOTAL" "$t2_pct" "$(make_bar $T2_QUALIFIED $T2_TOTAL)"
printf "  T3:  %2d/%-2d qualified (%3d%%)  %s\n" "$T3_QUALIFIED" "$T3_TOTAL" "$t3_pct" "$(make_bar $T3_QUALIFIED $T3_TOTAL)"
printf "  T4:  %2d/%-2d qualified (%3d%%)  %s\n" "$T4_QUALIFIED" "$T4_TOTAL" "$t4_pct" "$(make_bar $T4_QUALIFIED $T4_TOTAL)"
echo "  ─────────────────────────────────────────"
printf "  ALL: %2d/%-2d qualified (%3d%%)  %s\n" "$all_qual" "$TOTAL" "$all_pct" "$(make_bar $all_qual $TOTAL)"
echo ""

if [[ -n "$UNSCORED_LIST" ]]; then
  echo "Unscored Skills:"
  printf "$UNSCORED_LIST"
  echo ""
fi

if [[ -n "$UNQUALIFIED_LIST" ]]; then
  echo "Unqualified Skills:"
  printf "$UNQUALIFIED_LIST"
  echo ""
fi

echo "═══════════════════════════════════════════════════"
