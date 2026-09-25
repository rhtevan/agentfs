#!/usr/bin/env bash
# template-check.sh — Deterministic assertions on AGENTS.md template quality
#
# Usage: bash template-check.sh [TARGET_DIR]
#
#   TARGET_DIR   Directory containing AGENTS.md (default: .)
#
# Validates structural properties that affect model instruction-following.
# No LLM required. Exit code 0 = all pass, non-zero = failures found.

set -euo pipefail

TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"
AGENTS_FILE="$TARGET/AGENTS.md"

PASS=0
FAIL=0
WARN=0

result_pass() { PASS=$((PASS + 1)); echo "  [✅] $1"; }
result_fail() { FAIL=$((FAIL + 1)); echo "  [❌] $1"; }
result_warn() { WARN=$((WARN + 1)); echo "  [⚠️ ] $1"; }

echo "=== AGENTS.md Template Quality Check ==="
echo "  Target: $AGENTS_FILE"
echo ""

if [ ! -f "$AGENTS_FILE" ]; then
  result_fail "A0: AGENTS.md not found at $AGENTS_FILE"
  echo ""
  echo "Results: $PASS pass, $FAIL fail, $WARN warn"
  exit 1
fi

CONTENT="$(cat "$AGENTS_FILE")"
# Template-owned content only (strip project-owned sections)
TEMPLATE_CONTENT="$(sed '/PROJECT-OWNED/,$d' "$AGENTS_FILE")"

# ── A1: Token Budget ──────────────────────────────────────────────────
# Template-owned section should stay under 2000 tokens (~8000 chars)
# to leave room for base system prompt + skills list + extensions
TEMPLATE_CHARS=$(echo "$TEMPLATE_CONTENT" | wc -c | tr -d ' ')
TOKEN_EST=$((TEMPLATE_CHARS / 4))
MAX_TOKENS=2000
if [ "$TOKEN_EST" -le "$MAX_TOKENS" ]; then
  result_pass "A1: Token budget — ~${TOKEN_EST} tokens (limit: ${MAX_TOKENS})"
else
  result_fail "A1: Token budget — ~${TOKEN_EST} tokens exceeds limit of ${MAX_TOKENS}"
fi

# ── A2: Section Order (dependency chain) ──────────────────────────────
# Required order: Scope Definitions before Rules
# Quick Orientation must not precede Rules
SECTIONS=$(grep "^## " "$AGENTS_FILE" | head -10)
SCOPE_LINE=$(echo "$SECTIONS" | grep -n "Scope" | head -1 | cut -d: -f1)
RULES_LINE=$(echo "$SECTIONS" | grep -n "Rules" | head -1 | cut -d: -f1)
ORIENT_LINE=$(echo "$SECTIONS" | grep -n "Orientation" | head -1 | cut -d: -f1)

if [ -n "$SCOPE_LINE" ] && [ -n "$RULES_LINE" ]; then
  if [ "$SCOPE_LINE" -lt "$RULES_LINE" ]; then
    result_pass "A2: Section order — Scopes before Rules (dependencies respected)"
  else
    result_fail "A2: Section order — Scopes must precede Rules (Scopes=$SCOPE_LINE Rules=$RULES_LINE)"
  fi
else
  result_fail "A2: Section order — missing Scope Definitions or Rules section"
fi

if [ -n "$ORIENT_LINE" ] && [ -n "$RULES_LINE" ]; then
  if [ "$ORIENT_LINE" -gt "$RULES_LINE" ]; then
    result_pass "A2b: Orientation after Rules (low-priority section not blocking)"
  else
    result_warn "A2b: Orientation (line $ORIENT_LINE) appears before Rules (line $RULES_LINE)"
  fi
fi

# ── A3: Rule Completeness ─────────────────────────────────────────────
# All 17 rules must be present
for i in $(seq 1 17); do
  if ! echo "$CONTENT" | grep -qP "^\| $i \| (Event|Signal|Always) \|"; then
    result_fail "A3: Rule $i missing from rules table"
  fi
done
RULE_COUNT=$(echo "$CONTENT" | grep -cP "^\| [0-9]+ \| (Event|Signal|Always) \|" || true)
if [ "$RULE_COUNT" -eq 17 ]; then
  result_pass "A3: Rule completeness — all 17 rules present"
elif [ "$RULE_COUNT" -gt 0 ]; then
  result_fail "A3: Rule completeness — found $RULE_COUNT rules, expected 17"
fi

# ── A4: Context Lookup Fallback ────────────────────────────────────────
# Must have a fallback note mentioning index.md for when search_nodes is unavailable
if echo "$CONTENT" | grep -q "index.md.*progressive disclosure\|Context lookup fallback"; then
  result_pass "A4: Context lookup fallback note present"
else
  result_warn "A4: No context lookup fallback note for when search_nodes is unavailable"
fi

# ── A5: Skill Discovery Instruction ───────────────────────────────────
# Rule 7 must name search_nodes and load_skill
RULE8=$(echo "$CONTENT" | grep -P "^\| 7 \\|" | head -1)
RULE8_HAS_LOAD_SKILL=false
RULE8_HAS_SEARCH_NODES=false
echo "$RULE8" | grep -q "load_skill" && RULE8_HAS_LOAD_SKILL=true
echo "$RULE8" | grep -q "search_nodes" && RULE8_HAS_SEARCH_NODES=true

if $RULE8_HAS_LOAD_SKILL && $RULE8_HAS_SEARCH_NODES; then
  result_pass "A5: Rule 7 names both \`search_nodes\` and \`load_skill\`"
elif $RULE8_HAS_LOAD_SKILL; then
  result_warn "A5: Rule 7 names \`load_skill\` but not \`search_nodes\`"
elif $RULE8_HAS_SEARCH_NODES; then
  result_warn "A5: Rule 7 names \`search_nodes\` but not \`load_skill\`"
else
  result_fail "A5: Rule 7 missing both \`search_nodes\` and \`load_skill\`"
fi

# ── A7: Redundancy Detection ─────────────────────────────────────────
# Count how many times load_skill instruction appears in template-owned content
LOAD_SKILL_MENTIONS=$(echo "$TEMPLATE_CONTENT" | grep -c "load_skill" || true)
if [ "$LOAD_SKILL_MENTIONS" -le 5 ]; then
  result_pass "A7: load_skill mentioned ${LOAD_SKILL_MENTIONS} times (acceptable)"
else
  result_warn "A7: load_skill mentioned ${LOAD_SKILL_MENTIONS} times — possible redundancy"
fi

# Count how many separate places define the skill lookup procedure
SKILL_PROCEDURE_BLOCKS=0
echo "$TEMPLATE_CONTENT" | grep -q "Check.*# Skills.*this prompt" && SKILL_PROCEDURE_BLOCKS=$((SKILL_PROCEDURE_BLOCKS + 1))
echo "$TEMPLATE_CONTENT" | grep -q "FIRST.*check.*# Skills" && SKILL_PROCEDURE_BLOCKS=$((SKILL_PROCEDURE_BLOCKS + 1))
echo "$TEMPLATE_CONTENT" | grep -q "CRITICAL.*Skill lookup" && SKILL_PROCEDURE_BLOCKS=$((SKILL_PROCEDURE_BLOCKS + 1))
if [ "$SKILL_PROCEDURE_BLOCKS" -le 2 ]; then
  result_pass "A7b: Skill lookup procedure defined in $SKILL_PROCEDURE_BLOCKS location(s)"
else
  result_fail "A7b: Skill lookup procedure defined in $SKILL_PROCEDURE_BLOCKS locations — redundant"
fi

# ── A8: WHY vs HOW Ratio ─────────────────────────────────────────────
# Rules should be HOW instructions, not WHY explanations
# Heuristic: flag rules with trailing explanatory sentences
WHY_PHRASES=0
while IFS= read -r line; do
  # Check for trailing "This combats...", "This prevents...", "(Rule N also fires..."
  if echo "$line" | grep -qP "This (combats|prevents|ensures|mitigates|addresses)|^\| .+\(Rule [0-9]+ also"; then
    WHY_PHRASES=$((WHY_PHRASES + 1))
  fi
done <<< "$(echo "$CONTENT" | grep -P '^\| [0-9]+ \|')"

if [ "$WHY_PHRASES" -eq 0 ]; then
  result_pass "A8: No WHY-not-HOW phrases detected in rules"
else
  result_warn "A8: $WHY_PHRASES rule(s) contain explanatory WHY phrases — consider trimming"
fi

# ── A9: Version Consistency ───────────────────────────────────────────
# Check template version tag matches installed skill version
TEMPLATE_VER=$(echo "$CONTENT" | grep -oP 'agentfs-template-version: \K[0-9.]+' | head -1)
SKILL_VER=""
SKILL_FILE="$HOME/.agents/skills/agentfs-setup/SKILL.md"
if [ -f "$SKILL_FILE" ]; then
  SKILL_VER=$(grep -oP 'version: "\K[0-9.]+' "$SKILL_FILE" | head -1)
fi

if [ -n "$TEMPLATE_VER" ] && [ -n "$SKILL_VER" ]; then
  if [ "$TEMPLATE_VER" = "$SKILL_VER" ]; then
    result_pass "A9: Template version ($TEMPLATE_VER) matches skill version ($SKILL_VER)"
  else
    result_warn "A9: Template version ($TEMPLATE_VER) != skill version ($SKILL_VER) — run sync"
  fi
elif [ -z "$TEMPLATE_VER" ]; then
  result_warn "A9: No template version tag found in AGENTS.md"
fi

# ── Score & History ───────────────────────────────────────────────────
TOTAL=$((PASS + FAIL + WARN))
if [ "$TOTAL" -gt 0 ]; then
  # Score: pass=100%, warn=50%, fail=0%
  SCORE=$(( (PASS * 100 + WARN * 50) / TOTAL ))
else
  SCORE=0
fi

echo ""
echo "Score: ${SCORE}/100  ($PASS pass, $FAIL fail, $WARN warn)"

# Show template-level score history if available
HISTORY_FILE="$HOME/.agents/skills/agentfs-eval/references/template-scores.md"
if [ -f "$HISTORY_FILE" ]; then
  echo "  → Template score history: $HISTORY_FILE"
fi

exit "$FAIL"
