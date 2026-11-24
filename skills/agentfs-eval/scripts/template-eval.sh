#!/usr/bin/env bash
# template-eval.sh — Stage S0 AGENTS.md deterministic quality check
#
# Usage: bash template-eval.sh [TARGET_DIR]
#
# Runs deterministic template checks (A1-A10) only.
# Behavioral tests (B1-B3) deprecated — subsumed by the compliance
# benchmark (benchmark.sh / run-parallel.sh).
# Runtime compliance: agentfs-eval Steps 6-7 (compliance-profile.yaml,
# runtime-compliance.sh). Build-time Operable: Step 8 (SDM).
# "Tier" is reserved for model tiers T1-T4.
#
# Exit code: 0 on success, non-zero on check failure

set -euo pipefail

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
else
  trace_step() { echo "[trace] $*" >&2; }
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="."

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    *) TARGET="$1"; shift ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"

echo "=== AgentFS Stage S0 Evaluation ==="
echo "  Target: $TARGET"
echo ""

# ── Step 1: Deterministic template check (A1-A10) ───────────────────
echo "── Template Quality Check ──"
TEMPLATE_EXIT=0
TEMPLATE_OUTPUT=$(bash "$SCRIPT_DIR/template-check.sh" "$TARGET" 2>&1) || TEMPLATE_EXIT=$?
echo "$TEMPLATE_OUTPUT"

# Extract score from captured output
TEMPLATE_SCORE=$(echo "$TEMPLATE_OUTPUT" | grep "Score:" | grep -oP '[0-9]+(?=/100)' || echo "—")

# ── Behavioral tests DEPRECATED ─────────────────────────────────────
# B1-B3 behavioral tests (template-behavioral.sh) are deprecated.
# Subsumed by the compliance benchmark (benchmark.sh).

# ── Step 2: Report ───────────────────────────────────────────────────
VERSION_TAG=$(grep -oP 'agentfs-template-version: \K[0-9.]+' "$TARGET/AGENTS.md" 2>/dev/null || echo "unknown")

echo ""
echo "── Stage S0 Complete ──"
echo "  Version: $VERSION_TAG"
echo "  Score:   $TEMPLATE_SCORE/100"
echo ""
echo "For the full eval (S1-S3, runtime compliance, build-time Operable), use:"
echo "  hey eval agentfs"
echo "  → Steps 6-7 read compliance-profile.yaml (runtime-compliance.sh); Step 8 SDM build"
echo ""
echo "For build-time Quality evaluation, use:"
echo "  hey upgrade agentfs"
echo "  → runs gather-skill-state.sh + sdm-evaluate.sh quality.yaml"

exit $TEMPLATE_EXIT
