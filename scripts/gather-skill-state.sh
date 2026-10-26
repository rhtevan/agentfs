#!/bin/bash
# gather-skill-state.sh — Compute deterministic Tier 1 facts for a skill
#
# Extracts filesystem-verifiable metrics from a skill directory and
# outputs explicit fact statements that SDM can judge. This solves the
# context window problem: raw SKILL.md is 3,000-10,000 tokens and too
# noisy for SDM. This script produces ~20 lines of explicit facts.
#
# Usage:
#   gather-skill-state.sh <skill-directory>
#
# Output (stdout):
#   Plain text fact statements, one per line. Designed as SDM evidence.
#
# Exit codes:
#   0 — Facts gathered successfully
#   1 — Skill directory invalid
#
# Example output:
#   Skill: agentfs-readme-audit
#   Version: 2.1.0
#   Action steps in SKILL.md: 6
#   Scripts in scripts/ directory: 0
#   Script coverage: 0 of 6 action steps backed by scripts (0%).
#   Concern count: 4 (data gathering, scope resolution, semantic analysis, reporting)
#   ...

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

# --- Arguments ---
[[ $# -ge 1 ]] || die "Usage: gather-skill-state.sh <skill-directory>"

SKILL_DIR="$1"
[[ -d "$SKILL_DIR" ]] || die "Not a directory: $SKILL_DIR"
[[ -f "$SKILL_DIR/SKILL.md" ]] || die "No SKILL.md found in: $SKILL_DIR"

SKILL_NAME=$(basename "$SKILL_DIR")
SKILL_MD="$SKILL_DIR/SKILL.md"

# --- Version ---
VERSION="unknown"
if [[ -f "$SKILL_DIR/CHANGELOG.md" ]]; then
  _ver_lines=$(grep -oP '## \[\K[^\]]+' "$SKILL_DIR/CHANGELOG.md" 2>/dev/null || true)
  if [[ -n "$_ver_lines" ]]; then
    VERSION=$(echo "$_ver_lines" | head -1)
  fi
fi
# Fallback: try SKILL.md front matter
if [[ "$VERSION" == "unknown" ]]; then
  _ver_lines=$(grep -oP 'version:\s*"\K[^"]+' "$SKILL_MD" 2>/dev/null || true)
  if [[ -n "$_ver_lines" ]]; then
    VERSION=$(echo "$_ver_lines" | head -1)
  fi
fi

# --- Action step count ---
# Count lines that look like step headers: ### Step N, ### N., numbered steps
ACTION_STEPS=$(grep -cP '^\s*###\s+(Step\s+\d|[0-9]+\.)' "$SKILL_MD" 2>/dev/null || echo 0)
# Fallback: count major workflow steps
if [[ "$ACTION_STEPS" -eq 0 ]]; then
  ACTION_STEPS=$(grep -cP '^\s*##\s+Step\s' "$SKILL_MD" 2>/dev/null || echo 0)
fi

# --- Script count ---
SCRIPT_COUNT=0
SCRIPT_LIST=""
if [[ -d "$SKILL_DIR/scripts" ]]; then
  SCRIPT_COUNT=$(find "$SKILL_DIR/scripts" -maxdepth 1 -type f -name '*.sh' | wc -l)
  SCRIPT_LIST=$(find "$SKILL_DIR/scripts" -maxdepth 1 -type f -name '*.sh' -exec basename {} \; | sort | tr '\n' ', ' | sed 's/,$//')
fi

# --- Script coverage ---
# Count action steps that reference a script call (bash/sh + scripts/)
SCRIPTED_STEPS=0
if [[ "$SCRIPT_COUNT" -gt 0 ]]; then
  SCRIPTED_STEPS=$(grep -cP '(bash|sh)\s+.*scripts/' "$SKILL_MD" 2>/dev/null || echo 0)
  # Cap at action step count
  if [[ "$SCRIPTED_STEPS" -gt "$ACTION_STEPS" ]]; then
    SCRIPTED_STEPS=$ACTION_STEPS
  fi
fi

if [[ "$ACTION_STEPS" -gt 0 ]]; then
  COVERAGE_PCT=$((SCRIPTED_STEPS * 100 / ACTION_STEPS))
else
  COVERAGE_PCT=0
fi

# --- Concern detection ---
# Heuristic: detect distinct responsibility types in SKILL.md
CONCERNS=""
CONCERN_COUNT=0

# Data gathering
if grep -qiP '(gather|collect|count|list|ls |find |wc |grep )' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="data gathering, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

# Scope resolution
if grep -qiP '(scope|USER|PROJECT|resolve scope|git rev-parse)' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="scope resolution, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

# Semantic analysis
if grep -qiP '(semantic|alignment|compare|assess|judge|evaluate|analys)' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="semantic analysis, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

# User interaction
if grep -qiP '(ask the user|wait for|confirm|approval|WAIT|STOP)' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="user interaction, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

# File mutation
if grep -qiP '(write|create|edit|delete|mkdir|mv |cp |rm )' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="file mutation, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

# Formatting/reporting
if grep -qiP '(report|format|table|markdown|present|output)' "$SKILL_MD" 2>/dev/null; then
  CONCERNS+="formatting/reporting, "
  CONCERN_COUNT=$((CONCERN_COUNT + 1))
fi

CONCERNS=$(echo "$CONCERNS" | sed 's/, $//')

# --- Accidental complexity ---
# Count lines with inline shell commands (HOW) vs total content lines
TOTAL_LINES=$(wc -l < "$SKILL_MD")
# Lines that contain shell-like commands (backtick blocks, $(), pipes, redirects)
SHELL_LINES=$(grep -cP '^\s*(```|.*\$\(|.*\|.*\||.*[<>]{1,2}\s|.*&&\s|^\s*#\s*(bash|sh))' "$SKILL_MD" 2>/dev/null || echo 0)
# Lines inside code fences (rough estimate)
CODE_FENCE_LINES=$(awk '/^```/{if(f){f=0;n+=NR-s}else{f=1;s=NR}}END{print n+0}' "$SKILL_MD")
ACCIDENTAL_LINES=$((SHELL_LINES + CODE_FENCE_LINES))
if [[ "$TOTAL_LINES" -gt 0 ]]; then
  ACCIDENTAL_PCT=$((ACCIDENTAL_LINES * 100 / TOTAL_LINES))
else
  ACCIDENTAL_PCT=0
fi

# --- Model assumptions ---
# Count patterns that assume frontier-class model capability
MODEL_ASSUMPTIONS=0
# Multi-hop reasoning chains (3+ consecutive prose instructions without script)
# Inline code extraction requirements
if grep -qP '(extract the .* from|parse the .* output|interpret the .* result)' "$SKILL_MD" 2>/dev/null; then
  MODEL_ASSUMPTIONS=$((MODEL_ASSUMPTIONS + 1))
fi
# Complex conditional logic in prose
CONDITIONAL_BLOCKS=$(grep -cP '(if.*then|otherwise|depending on|based on whether)' "$SKILL_MD" 2>/dev/null || true)
CONDITIONAL_BLOCKS="${CONDITIONAL_BLOCKS:-0}"
CONDITIONAL_BLOCKS=$(echo "$CONDITIONAL_BLOCKS" | tr -d '[:space:]')
if [[ "$CONDITIONAL_BLOCKS" -gt 3 ]]; then
  MODEL_ASSUMPTIONS=$((MODEL_ASSUMPTIONS + CONDITIONAL_BLOCKS - 3))
fi

# --- CNL compliance ---
# Check for synonym mixing, passive voice, multi-action sentences
PASSIVE_VOICE=$(grep -cP '\b(is|are|was|were|been|being)\s+(checked|run|executed|performed|completed|evaluated|created|generated)' "$SKILL_MD" 2>/dev/null || true)
PASSIVE_VOICE="${PASSIVE_VOICE:-0}"
PASSIVE_VOICE=$(echo "$PASSIVE_VOICE" | tr -d '[:space:]')

# --- Trace instrumentation ---
HAS_TRACE=false
if [[ "$SCRIPT_COUNT" -gt 0 ]]; then
  TRACE_SCRIPTS=$(grep -rl 'trace-lib.sh\|trace_step\|trace_init' "$SKILL_DIR/scripts/" 2>/dev/null || true)
  if [[ -n "$TRACE_SCRIPTS" ]]; then
    TRACE_SCRIPTS=$(echo "$TRACE_SCRIPTS" | wc -l)
  else
    TRACE_SCRIPTS=0
  fi
  if [[ "$TRACE_SCRIPTS" -gt 0 ]]; then
    HAS_TRACE=true
  fi
fi

# --- Has observation.yaml ---
HAS_OBS_SCHEMA=false
if [[ -f "$SKILL_DIR/observation.yaml" ]]; then
  HAS_OBS_SCHEMA=true
fi

# --- Has qoo-profile.yaml ---
HAS_QOO_PROFILE=false
if [[ -f "$SKILL_DIR/qoo-profile.yaml" ]]; then
  HAS_QOO_PROFILE=true
fi

# --- Has scores.yaml ---
HAS_SCORES=false
if [[ -f "$SKILL_DIR/scores.yaml" ]]; then
  HAS_SCORES=true
fi

# --- Output facts ---
cat <<EOF
Skill: $SKILL_NAME
Version: $VERSION
Total lines in SKILL.md: $TOTAL_LINES
Action steps in SKILL.md: $ACTION_STEPS
Scripts in scripts/ directory: $SCRIPT_COUNT
Script list: ${SCRIPT_LIST:-none}
Scripted action steps: $SCRIPTED_STEPS
Script coverage: $SCRIPTED_STEPS of $ACTION_STEPS action steps backed by scripts (${COVERAGE_PCT}%).
Concern count: $CONCERN_COUNT ($CONCERNS)
Accidental complexity lines: $ACCIDENTAL_LINES of $TOTAL_LINES total (${ACCIDENTAL_PCT}%).
Model assumptions detected: $MODEL_ASSUMPTIONS
Conditional logic blocks: $CONDITIONAL_BLOCKS
Passive voice instances: $PASSIVE_VOICE
Trace instrumentation: $HAS_TRACE
Has observation.yaml: $HAS_OBS_SCHEMA
Has qoo-profile.yaml: $HAS_QOO_PROFILE
Has scores.yaml: $HAS_SCORES
EOF
