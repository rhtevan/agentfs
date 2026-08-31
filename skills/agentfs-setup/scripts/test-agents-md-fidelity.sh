#!/usr/bin/env bash
# test-agents-md-fidelity.sh — Validate AGENTS.md structure and content (v5.0.0+).
#
# Usage: bash test-agents-md-fidelity.sh [path-to-agents-md]
#   Defaults to ./AGENTS.md in current directory.
#
# Validates:
#   - v5 section structure (flat Rules table, no guardrail sections)
#   - All 12 rules present in flat table
#   - Signal routing completeness (6 rows)
#   - Script existence and references
#   - Behavioral keywords and fidelity
#   - Scope definitions
#   - Project-owned sections (Agent Profiles, SPECKIT)

set -euo pipefail

TARGET="${1:-./AGENTS.md}"

if [[ ! -f "$TARGET" ]]; then
  echo "ERROR: File not found: $TARGET" >&2
  exit 2
fi

PASSED=0
FAILED=0

assert_contains() {
  local label="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$TARGET"; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — pattern not found: $pattern"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local label="$1"
  local pattern="$2"
  if grep -qE "$pattern" "$TARGET"; then
    echo "  ❌ $label — pattern should NOT be present: $pattern"
    FAILED=$((FAILED + 1))
  else
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  fi
}

assert_script_exists() {
  local label="$1"
  local script="$2"
  local expanded="${script/#\~/$HOME}"
  if [[ -f "$expanded" ]]; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — script not found: $expanded"
    FAILED=$((FAILED + 1))
  fi
}

assert_rule_present() {
  local rule_num="$1"
  local keyword="$2"
  if grep -qE "^\| ${rule_num} \|.*${keyword}" "$TARGET"; then
    echo "  ✅ Rule #${rule_num} (${keyword})"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ Rule #${rule_num} — expected keyword: $keyword"
    FAILED=$((FAILED + 1))
  fi
}

SCRIPTS_DIR="$HOME/.agents/skills/agentfs-setup/scripts"

# ── v5 Section Structure ──────────────────────────────────────────
echo "=== Section Structure (v5) ==="
assert_contains "Template version marker" 'agentfs-template-version:.*5\.'
assert_contains "Quick Orientation heading" '^## Quick Orientation'
assert_contains "Signal Routing heading" '^## Signal Routing'
assert_contains "Scope Definitions heading" '^## Scope Definitions'
assert_contains "What Lives Where heading" '^### What Lives Where'
assert_contains "Rules heading" '^## Rules'
assert_contains "Agent Profiles heading" '^## Agent Profiles'
assert_contains "SPECKIT START marker" '<!-- SPECKIT START -->'
assert_contains "SPECKIT END marker" '<!-- SPECKIT END -->'
assert_contains "PROJECT-OWNED marker" 'PROJECT-OWNED'

# ── v4 Sections REMOVED ───────────────────────────────────────────
echo "=== v4 Sections Removed ==="
assert_not_contains "No Routing Rules subsection" '^### Routing Rules'
assert_not_contains "No Guardrail Quick Reference" '^## Guardrail Quick Reference'
assert_not_contains "No Structural Guardrails heading" '^## AgentFS Structural Guardrails'
assert_not_contains "No numbered guardrail sections" '^### [0-9]+\.'

# ── All 12 Rules in Flat Table ─────────────────────────────────────
echo "=== Rules Table (12 rules) ==="
assert_rule_present "1" "User message received"
assert_rule_present "2" "\.agents/"
assert_rule_present "3" "Session start"
assert_rule_present "4" "Creating a skill"
assert_rule_present "5" "write/edit"
assert_rule_present "6" "hey git"
assert_rule_present "7" "destructive op"
assert_rule_present "8" "policy|domain|unfamiliar"
assert_rule_present "9" "memories"
assert_rule_present "10" "validation phrases"
assert_rule_present "11" "reverse|new information"
assert_rule_present "12" "canary"

# Rule count validation
RULE_COUNT=$(grep -cE '^\| [0-9]+ \|' "$TARGET")
echo ""
if [[ "$RULE_COUNT" -eq 12 ]]; then
  echo "  ✅ Rule count: $RULE_COUNT"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ Rule count: expected 12, got $RULE_COUNT"
  FAILED=$((FAILED + 1))
fi

# ── Signal Routing (6 rows) ───────────────────────────────────────
echo "=== Signal Routing Table ==="
assert_contains "Signal: remember this" 'remember this'
assert_contains "Signal: always do X" 'always do X'
assert_contains "Signal: I prefer" 'I prefer'
assert_contains "Signal: forget this" 'forget this'
assert_contains "Signal: what do you remember" 'what do you remember'
assert_contains "Signal: hey git" 'hey git'

# v4 signals removed (covered by skill signal routing)
assert_not_contains "No 'learn this document' signal" 'learn this document'
assert_not_contains "No 'harvest' signal row" 'harvest.*reflect.*scan memories'

# Signal row count (data rows only, exclude header + separator)
SIGNAL_ROWS=$(awk '/## Signal Routing/,/## Scope/' "$TARGET" \
  | grep -E '^\|' | grep -vE 'Signal|---' | wc -l)
echo ""
if [[ "$SIGNAL_ROWS" -eq 6 ]]; then
  echo "  ✅ Signal routing rows: $SIGNAL_ROWS"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ Signal routing rows: expected 6, got $SIGNAL_ROWS"
  FAILED=$((FAILED + 1))
fi

# ── Script Existence ──────────────────────────────────────────────
echo "=== Script Existence ==="
assert_script_exists "post-edit.sh" "$SCRIPTS_DIR/post-edit.sh"
assert_script_exists "pre-push-scan.sh" "$SCRIPTS_DIR/pre-push-scan.sh"
assert_script_exists "checkpoint.sh" "$SCRIPTS_DIR/checkpoint.sh"
assert_script_exists "merge-log-entry.sh" "$SCRIPTS_DIR/merge-log-entry.sh"
assert_script_exists "merge-changelog-entry.sh" "$SCRIPTS_DIR/merge-changelog-entry.sh"
assert_script_exists "sync-agents-md.sh" "$SCRIPTS_DIR/sync-agents-md.sh"
assert_script_exists "seed-agents-md.sh" "$SCRIPTS_DIR/seed-agents-md.sh"
assert_script_exists "regen-skill-index.py" "$SCRIPTS_DIR/regen-skill-index.py"

# ── Script References in AGENTS.md ────────────────────────────────
echo "=== Script References ==="
assert_contains "References merge-log-entry.sh" 'merge-log-entry\.sh'
assert_contains "References merge-changelog-entry.sh" 'merge-changelog-entry\.sh'
assert_contains "References post-edit.sh" 'post-edit\.sh'
assert_contains "References checkpoint.sh" 'checkpoint\.sh'

# ── Key Behavioral Keywords ───────────────────────────────────────
echo "=== Behavioral Keywords ==="
assert_contains "Keyword: load_skill" 'load_skill'
assert_contains "Keyword: canary" '[Cc]anary'
assert_contains "Keyword: OVERRIDE" 'OVERRIDE'
assert_contains "Keyword: agentfs-git-push" 'agentfs-git-push'
assert_contains "Keyword: knowledge index" 'knowledge.*index'
assert_contains "Keyword: filesystem-integrity" 'filesystem-integrity'

# ── Behavioral Fidelity ───────────────────────────────────────────
echo "=== Behavioral Fidelity ==="
# Memory scope (Rule #9)
assert_contains "Graduation to OKF" '[Gg]raduat'
assert_contains "PROJECT scope for memories" 'PROJECT scope only'
assert_contains "Preferences to USER.md" 'Preferences.*USER\.md'
# Cross-agent discovery (Rule #3)
assert_contains "CLAUDE.md reference" 'CLAUDE\.md'
assert_contains "cursorrules reference" 'cursorrules'
assert_contains "AGENTS.md wins conflicts" 'wins.*conflict'
# Skill placement (Rule #4)
assert_contains "Default to USER" 'Default to USER'
assert_contains "Project signal words" 'project skill.*for this project.*local skill'
# Anti-sycophancy split (Rules #10 + #11)
assert_contains "No validation phrases" 'validation phrases'
assert_contains "Lead with substance" 'Lead with substance'
assert_contains "Name risks" '[Nn]ame.*risk'
assert_contains "Quote conflicting rule" '[Qq]uote.*(it|rule)'
# Anti-daydreaming (Rule #12)
assert_contains "1-in-5 cadence" '1-in-5'
assert_contains "Never persist canary" 'Never persist'
assert_contains "Ephemeral canary" 'ephemeral'
# Filesystem integrity (Rule #5)
assert_contains "checkpoint create" 'checkpoint\.sh create'
assert_contains "checkpoint clear" 'checkpoint\.sh clear'
# Git push delegation (Rule #6)
assert_contains "Git push delegates to skill" 'load_skill.*agentfs-git-push'

# ── Scope Definitions ─────────────────────────────────────────────
echo "=== Scope Definitions ==="
assert_contains "USER scope path" '~/.agents/'
assert_contains "PROJECT scope path" '\./\.agents/'
assert_contains "skills in both scopes" 'skills.*shared.*project-specific'
assert_contains "knowledge USER only" 'knowledge.*shared.*never'
assert_contains "memories PROJECT only" 'memories.*never.*per-agent'

# ── Agent Profiles ─────────────────────────────────────────────────
echo "=== Agent Profiles ==="
assert_contains "Default agent row" 'default.*SOUL.*memories'

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "  ✅ All fidelity checks passed." || echo "  ❌ $FAILED check(s) failed."
exit $(( FAILED > 0 ? 1 : 0 ))
