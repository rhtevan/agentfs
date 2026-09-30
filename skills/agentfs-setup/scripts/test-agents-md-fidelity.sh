#!/usr/bin/env bash
# test-agents-md-fidelity.sh — Validate AGENTS.md structure and content (v7.2.0+).
#
# Usage: bash test-agents-md-fidelity.sh [path-to-agents-md]
#   Defaults to ./AGENTS.md in current directory.
#
# Validates:
#   - v7.2 section structure (numbered prose rules, no severity tags)
#   - All 8 rules present with named headers in When/Do format
#   - Signal Dispatch table completeness
#   - Script existence and references
#   - Behavioral keywords and fidelity
#   - Scope definitions
#   - Project-owned sections (Agent Profiles, SPECKIT)
#   - No stale numbered rule references or severity tags

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

# ── v7.2 Section Structure ────────────────────────────────────────
echo "=== Section Structure (v7.2) ==="
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

# ── v5/v6/v7.0 Sections REMOVED ──────────────────────────────────
echo "=== Legacy Sections Removed ==="
assert_not_contains "No flat rules table" '^\| # \| Type \| Stimulus'
assert_not_contains "No Guardrail Quick Reference" '^## Guardrail Quick Reference'
assert_not_contains "No Structural Guardrails heading" '^## AgentFS Structural Guardrails'
assert_not_contains "No severity tags in rule headings" '### [0-9]+\. .* \[(CRITICAL|HIGH|NORMAL|LOW)\]'
assert_not_contains "No unnumbered rule headings under Rules" '^### [A-Z][a-z].* \[(CRITICAL|HIGH|NORMAL|LOW)\]'

# ── Named Rules (numbered, When/Do prose, no severity) ────────────
echo "=== Named Rules (numbered, When/Do prose) ==="
assert_contains "Rule 1: Signal Dispatch" '^### 1\. Signal Dispatch$'
assert_contains "Rule 2: Pre-Flight" '^### 2\. Pre-Flight$'
assert_contains "Rule 3: Post-Write" '^### 3\. Post-Write$'
assert_contains "Rule 4: Session Canary" '^### 4\. Session Canary$'
assert_contains "Rule 5: Conflict Resolution" '^### 5\. Conflict Resolution$'
assert_contains "Rule 6: Checkpoint" '^### 6\. Checkpoint$'
assert_contains "Rule 7: Scope Rules" '^### 7\. Scope Rules$'
assert_contains "Rule 8: Path Hygiene" '^### 8\. Path Hygiene$'

# Removed rules must not be present
assert_not_contains "No Session Start rule" '^### [0-9]+\. Session Start'
assert_not_contains "No Index-First Reading rule" '^### [0-9]+\. Index-First Reading'
assert_not_contains "No Memory Scope rule" '^### [0-9]+\. Memory Scope'
assert_not_contains "No Skill Scope rule" '^### [0-9]+\. Skill Scope'

# Rule count (### N. heading format)
RULE_COUNT=$(grep -cE '^### [0-9]+\.' "$TARGET" || true)
echo ""
if [[ "$RULE_COUNT" -eq 8 ]]; then
  echo "  ✅ Numbered rule count: $RULE_COUNT"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ Numbered rule count: expected 8, got $RULE_COUNT"
  FAILED=$((FAILED + 1))
fi

# ── No Stale Numbered References ──────────────────────────────────
echo "=== No Stale Numbered References ==="
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
# Session Canary rule (absorbs Session Start)
assert_contains "AGENTS.md wins conflicts" 'authoritative.*other context'
assert_contains "Read USER.md on start" 'USER\.md.*preferences'
assert_contains "Re-read memories on re-verify" 'MEMORY\.md.*USER\.md.*re-verification'
# Scope Rules
assert_contains "Graduation to OKF" '[Gg]raduat'
assert_contains "PROJECT scope for memories" 'PROJECT scope only'
assert_contains "Graduation via harvest" 'hey harvest'
assert_contains "Default skills to USER" '[Dd]efault.* USER'
assert_contains "Project skill signal words" 'project skill.*for this project.*local skill'
# Conflict Resolution rule
assert_contains "Quote conflicting rule" '[Qq]uote.*rule'
# Checkpoint rule
assert_contains "checkpoint create" 'checkpoint\.sh create'
# Pre-Flight git push gate
assert_contains "Git push gate in Pre-Flight" 'git push.*confirmation'
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
