#!/usr/bin/env bash
# test-agents-md-fidelity.sh — Validate AGENTS.md structure and content (v7.0.0+).
#
# Usage: bash test-agents-md-fidelity.sh [path-to-agents-md]
#   Defaults to ./AGENTS.md in current directory.
#
# Validates:
#   - v7 section structure (prose rules with priority tags)
#   - All rules present with named headers
#   - Signal Dispatch table completeness
#   - Script existence and references
#   - Behavioral keywords and fidelity
#   - Scope definitions
#   - Project-owned sections (Agent Profiles, SPECKIT)
#   - No stale numbered rule references

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

SCRIPTS_DIR="$HOME/.agents/skills/agentfs-setup/scripts"

# ── v7 Section Structure ──────────────────────────────────────────
echo "=== Section Structure (v7) ==="
assert_contains "Template version marker" 'agentfs-template-version:.*7\.'
assert_contains "Quick Orientation heading" '^## Quick Orientation'
assert_contains "Signal Dispatch heading" '^## Signal Dispatch'
assert_contains "Scope Definitions heading" '^## Scope Definitions'
assert_contains "What Lives Where heading" '^### What Lives Where'
assert_contains "Rules heading" '^## Rules'
assert_contains "Agent Profiles heading" '^## Agent Profiles'
assert_contains "SPECKIT START marker" '<!-- SPECKIT START -->'
assert_contains "SPECKIT END marker" '<!-- SPECKIT END -->'
assert_contains "PROJECT-OWNED marker" 'PROJECT-OWNED'

# ── v5/v6 Sections REMOVED ────────────────────────────────────────
echo "=== Legacy Sections Removed ==="
assert_not_contains "No flat rules table" '^\| # \| Type \| Stimulus'
assert_not_contains "No Guardrail Quick Reference" '^## Guardrail Quick Reference'
assert_not_contains "No Structural Guardrails heading" '^## AgentFS Structural Guardrails'

# ── Named Rules in Prose Format ────────────────────────────────────
echo "=== Named Rules (prose format with priority tags) ==="
assert_contains "Signal Dispatch rule [CRITICAL]" '### 1\. Signal Dispatch \[CRITICAL\]'
assert_contains "Pre-Flight rule [HIGH]" '### 2\. Pre-Flight \[HIGH\]'
assert_contains "Post-Write rule [HIGH]" '### 3\. Post-Write \[HIGH\]'
assert_contains "Session Start rule [NORMAL]" '### 4\. Session Start \[NORMAL\]'
assert_contains "Session Canary rule [NORMAL]" '### 5\. Session Canary \[NORMAL\]'
assert_contains "Conflict Resolution rule [NORMAL]" '### 6\. Conflict Resolution \[NORMAL\]'
assert_contains "Checkpoint rule [NORMAL]" '### 7\. Checkpoint \[NORMAL\]'
assert_contains "Index-First Reading rule [LOW]" '### 8\. Index-First Reading \[LOW\]'
assert_contains "Memory Scope rule [LOW]" '### 9\. Memory Scope \[LOW\]'
assert_contains "Skill Scope rule [LOW]" '### 10\. Skill Scope \[LOW\]'
assert_contains "Path Hygiene rule [LOW]" '### Path Hygiene \[LOW\]'

# Rule count (### N. heading format)
RULE_COUNT=$(grep -cE '^### [0-9]+\.' "$TARGET" || true)
echo ""
if [[ "$RULE_COUNT" -ge 10 ]]; then
  echo "  ✅ Numbered rule count: $RULE_COUNT"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ Numbered rule count: expected ≥10, got $RULE_COUNT"
  FAILED=$((FAILED + 1))
fi

# ── No Stale Numbered References ──────────────────────────────────
echo "=== No Stale Numbered References ==="
# Check that no "Rule N" or "Guardrail #N" appears outside of
# rule headings (### N.) and the override preamble
STALE_REFS=$(grep -nE '(per|follow|see|via) Rule [0-9]|Guardrail #[0-9]' "$TARGET" || true)
if [[ -z "$STALE_REFS" ]]; then
  echo "  ✅ No stale numbered rule references"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ Stale numbered references found:"
  echo "$STALE_REFS" | sed 's/^/    /'
  FAILED=$((FAILED + 1))
fi

# ── Signal Dispatch Table ─────────────────────────────────────────
echo "=== Signal Dispatch Table ==="
assert_contains "Signal: remember" 'remember'
assert_contains "Signal: prefer" 'prefer'
assert_contains "Signal: forget" 'forget'
assert_contains "Signal: harvest" 'harvest'
assert_contains "Signal: what do you remember" 'what do you remember'
assert_contains "Signal: always" 'always'

# ── Dispatch Hierarchy ────────────────────────────────────────────
echo "=== Dispatch Hierarchy ==="
assert_contains "Path A documented" 'Path A'
assert_contains "Path B documented" 'Path B'
assert_contains "Tier 2 documented" 'Tier 2'
assert_contains "Tier 3 documented" 'Tier 3'
assert_contains "search_nodes in Path B" 'search_nodes'
assert_contains "load_skill in Path B" 'load_skill'

# ── Script Existence ──────────────────────────────────────────────
echo "=== Script Existence ==="
assert_script_exists "post-write.sh" "$SCRIPTS_DIR/post-write.sh"
assert_script_exists "checkpoint.sh" "$SCRIPTS_DIR/checkpoint.sh"
assert_script_exists "sync-agents-md.sh" "$SCRIPTS_DIR/sync-agents-md.sh"
assert_script_exists "seed-agents-md.sh" "$SCRIPTS_DIR/seed-agents-md.sh"

# ── Script References in AGENTS.md ────────────────────────────────
echo "=== Script References ==="
assert_contains "References post-write.sh" 'post-write\.sh'
assert_contains "References checkpoint.sh" 'checkpoint\.sh'
assert_contains "References seed-agents-md.sh" 'seed-agents-md\.sh'
assert_contains "References sync-agents-md.sh" 'sync-agents-md\.sh'

# ── Key Behavioral Keywords ───────────────────────────────────────
echo "=== Behavioral Keywords ==="
assert_contains "Keyword: load_skill" 'load_skill'
assert_contains "Keyword: canary" '[Cc]anary'
assert_contains "Keyword: OVERRIDE" 'OVERRIDE'
assert_contains "Keyword: knowledge index" 'knowledge.*index'
assert_contains "Keyword: Conflict Resolution" 'Conflict Resolution'

# ── Behavioral Fidelity ───────────────────────────────────────────
echo "=== Behavioral Fidelity ==="
# Memory Scope rule
assert_contains "Graduation to OKF" '[Gg]raduat'
assert_contains "PROJECT scope for memories" 'PROJECT scope only'
assert_contains "Preferences to USER.md" 'Preferences.*USER\.md'
assert_contains "Graduation via harvest" 'hey harvest'
# Session Start rule
assert_contains "AGENTS.md wins conflicts" 'wins.*conflict'
# Skill Scope rule
assert_contains "Default to USER" 'Default to USER'
assert_contains "Project signal words" 'project skill.*for this project.*local skill'
# Conflict Resolution rule
assert_contains "Quote conflicting rule" '[Qq]uote.*rule'
# Session Canary rule
assert_contains "Re-read memories on re-verify" 'MEMORY\.md.*USER\.md.*re-verification'
# Checkpoint rule
assert_contains "checkpoint create" 'checkpoint\.sh create'
# Path Hygiene rule
assert_contains "No explicit home paths" 'home.*user'

# ── Scope Definitions ─────────────────────────────────────────────
echo "=== Scope Definitions ==="
assert_contains "USER scope path" '~/.agents/'
assert_contains "PROJECT scope path" '\./\.agents/'

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
