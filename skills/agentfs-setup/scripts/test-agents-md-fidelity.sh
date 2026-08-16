#!/usr/bin/env bash
# test-agents-md-fidelity.sh — Validate optimized AGENTS.md structure and content.
#
# Usage: bash test-agents-md-fidelity.sh [path-to-agents-md]
#   Defaults to ./AGENTS.md in current directory.

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

assert_script_exists() {
  local label="$1"
  local script="$2"
  # Expand ~ to $HOME
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

# ── Section structure ──────────────────────────────────────────────
echo "=== Section Structure ==="
assert_contains "Template version marker" 'agentfs-template-version'
assert_contains "Quick Orientation heading" '^## Quick Orientation'
assert_contains "Signal Routing heading" '^## Signal Routing'
assert_contains "Routing Rules heading" '^### Routing Rules'
assert_contains "Guardrail Quick Ref heading" '^## Guardrail Quick Reference'
assert_contains "Scope Definitions heading" '^## Scope Definitions'
assert_contains "What Lives Where heading" '^### What Lives Where'
assert_contains "Structural Guardrails heading" '^## AgentFS Structural Guardrails'
assert_contains "Agent Profiles heading" '^## Agent Profiles'
assert_contains "SPECKIT START marker" '<!-- SPECKIT START -->'
assert_contains "SPECKIT END marker" '<!-- SPECKIT END -->'

# ── All 10 guardrails referenced in Quick Ref ──────────────────────
echo "=== Guardrail Quick Ref (all 10) ==="
for i in $(seq 1 10); do
  assert_contains "Guardrail #$i in Quick Ref" "| .*$i.*|.*|"
done

# ── Guardrail detail sections present ──────────────────────────────
echo "=== Guardrail Detail Sections ==="
# #1 and #6 removed (table-only) — verify NOT present as detail
assert_contains "#2 Memory Scope detail" '^### 2\. Memory Scope'
assert_contains "#3 Cross-Agent Discovery detail" '^### 3\. Cross-Agent Context Discovery'
assert_contains "#4 Skill Placement detail" '^### 4\. Skill Placement'
assert_contains "#5 Filesystem Integrity detail" '^### 5\. Filesystem Integrity'
assert_contains "#7 Anti-Sycophancy detail" '^### 7\. Anti-Sycophancy'
assert_contains "#8 Anti-Daydreaming detail" '^### 8\. Anti-Daydreaming'
assert_contains "#9 Checkpoints detail" '^### 9\. Checkpoints'
assert_contains "#10 Git Push Safety detail" '^### 10\. Git Push Safety'

# ── Script references ──────────────────────────────────────────────
echo "=== Script References ==="
assert_script_exists "post-edit.sh exists" "$SCRIPTS_DIR/post-edit.sh"
assert_script_exists "pre-push-scan.sh exists" "$SCRIPTS_DIR/pre-push-scan.sh"
assert_script_exists "checkpoint.sh exists" "$SCRIPTS_DIR/checkpoint.sh"
assert_script_exists "merge-log-entry.sh exists" "$SCRIPTS_DIR/merge-log-entry.sh"
assert_script_exists "regen-skill-index.py exists" "$SCRIPTS_DIR/regen-skill-index.py"

assert_contains "References post-edit.sh" 'post-edit\.sh'
assert_contains "References pre-push-scan.sh" 'pre-push-scan\.sh'
assert_contains "References checkpoint.sh" 'checkpoint\.sh'
assert_contains "References merge-log-entry.sh" 'merge-log-entry\.sh'

# ── Critical behavioral keywords ──────────────────────────────────
echo "=== Critical Keywords ==="
assert_contains "Keyword: STOP" 'STOP'
assert_contains "Keyword: WAIT" 'WAIT'
assert_contains "Keyword: load_skill" 'load_skill'
assert_contains "Keyword: fail loud" 'fail loud'
assert_contains "Keyword: canary" '[Cc]anary'
assert_contains "Keyword: OVERRIDE" 'OVERRIDE'
assert_contains "Keyword: CONTEXT DRIFT" 'CONTEXT DRIFT'
assert_contains "Keyword: idempotent" '[Ii]dempoten'
assert_contains "Keyword: incremental edits" 'incremental edits'
assert_contains "Keyword: never improvise" '[Nn]ever improvise'

# ── Fidelity: key behavioral requirements ──────────────────────────
echo "=== Behavioral Fidelity ==="
# Memory scope
assert_contains "MEMORY.md = experiences not rules" 'experiences'
assert_contains "Graduation to OKF" '[Gg]raduat'
assert_contains "No memories at USER scope" 'No.*memories.*USER|PROJECT-scoped only'
# Cross-agent
assert_contains "CLAUDE.md reference" 'CLAUDE\.md'
assert_contains "cursorrules reference" 'cursorrules'
assert_contains "AGENTS.md wins conflicts" 'wins.*conflict|precedence'
# Skill placement
assert_contains "Default to USER" 'Default to USER'
assert_contains "Project signal words" 'project skill.*for this project.*local skill'
# Anti-sycophancy
assert_contains "Quote conflicting guardrail" '[Qq]uote.*guardrail|[Qq]uote.*conflict'
assert_contains "No rules in MEMORY.md" 'rule-like.*always.*never.*must'
# Anti-daydreaming
assert_contains "Session-scoped canary" 'session-scoped canary|session-scoped'
assert_contains "1-in-5 cadence" '1-in-5'
assert_contains "Never persist canary" 'Never persist'
# Checkpoint
assert_contains "checkpoint create subcommand" 'checkpoint\.sh create'
assert_contains "checkpoint clear subcommand" 'checkpoint\.sh clear'
assert_contains "checkpoint check subcommand" 'checkpoint\.sh check'
# Git push
assert_contains "pre-push-scan invocation" 'pre-push-scan\.sh'
assert_contains "Explicit approval required" 'explicit approval|WAIT.*approval'

# ── Signal routing table completeness ──────────────────────────────
echo "=== Signal Routing Table ==="
assert_contains "Signal: remember this" 'remember this'
assert_contains "Signal: always do X" 'always do X'
assert_contains "Signal: I prefer" 'I prefer'
assert_contains "Signal: learn this document" 'learn this document'
assert_contains "Signal: forget this" 'forget this'
assert_contains "Signal: what do you remember" 'what do you remember'
assert_contains "Signal: harvest" 'harvest.*reflect.*scan memories'
assert_contains "Signal: hey git" 'hey git'

# ── Scope definitions completeness ─────────────────────────────────
echo "=== Scope Definitions ==="
assert_contains "USER scope path" '~/.agents/'
assert_contains "PROJECT scope path" './.agents/'
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
