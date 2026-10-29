#!/usr/bin/env bash
# template-eval.sh — Tier 0 AGENTS.md deterministic quality check
#
# Usage: bash template-eval.sh [TARGET_DIR]
#
# Runs deterministic template checks (A1-A9) only.
# Behavioral tests (B1-B3) deprecated — subsumed by QOO benchmark
# (benchmark.sh auto-discovered dispatch tests).
# Runtime Operable evaluation is now in agentfs-eval SKILL.md
# QOO Operable section using benchmark.sh + sdm-evaluate.sh.
#
# Exit code: 0 on success, non-zero on check failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="."

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    *) TARGET="$1"; shift ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"

echo "=== AgentFS Tier 0 Evaluation ==="
echo "  Target: $TARGET"
echo ""

# ── Step 1: Deterministic template check (A1-A9) ────────────────────
echo "── Template Quality Check ──"
TEMPLATE_EXIT=0
TEMPLATE_OUTPUT=$(bash "$SCRIPT_DIR/template-check.sh" "$TARGET" 2>&1) || TEMPLATE_EXIT=$?
echo "$TEMPLATE_OUTPUT"

# Extract score from captured output
TEMPLATE_SCORE=$(echo "$TEMPLATE_OUTPUT" | grep "Score:" | grep -oP '[0-9]+(?=/100)' || echo "—")

# ── Behavioral tests DEPRECATED ─────────────────────────────────────
# B1-B3 behavioral tests (template-behavioral.sh) are deprecated.
# Subsumed by QOO auto-discovered dispatch tests in benchmark.sh.

# ── Step 2: Report ───────────────────────────────────────────────────
VERSION_TAG=$(grep -oP 'agentfs-template-version: \K[0-9.]+' "$TARGET/AGENTS.md" 2>/dev/null || echo "unknown")

echo ""
echo "── Tier 0 Complete ──"
echo "  Version: $VERSION_TAG"
echo "  Score:   $TEMPLATE_SCORE/100"
echo ""
echo "For runtime Operable evaluation (QOO Tier 2), use:"
echo "  hey eval agentfs"
echo "  → runs benchmark.sh + sdm-evaluate.sh operable.yaml"
echo ""
echo "For build-time Quality evaluation (QOO Tier 1), use:"
echo "  hey upgrade agentfs"
echo "  → runs gather-skill-state.sh + sdm-evaluate.sh quality.yaml"

exit $TEMPLATE_EXIT
