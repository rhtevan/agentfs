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
TARGET_MODE="skill"
if [[ "${1:-}" == "--target" && "${2:-}" == "agents-md" ]]; then
  TARGET_MODE="agents-md"
  shift 2
fi

[[ $# -ge 1 ]] || die "Usage: gather-skill-state.sh [--target agents-md] <path>"

if [[ "$TARGET_MODE" == "agents-md" ]]; then
  # --- AGENTS.md mode ---
  AGENTS_FILE="$1"
  [[ -f "$AGENTS_FILE" ]] || die "AGENTS.md not found: $AGENTS_FILE"

  TOTAL_LINES=$(wc -l < "$AGENTS_FILE")

  # Version
  VERSION=$(grep -oP 'agentfs-template-version: \K[0-9.]+' "$AGENTS_FILE" 2>/dev/null || echo "unknown")

  # Rule count and per-rule metrics
  RULE_COUNT=$(grep -cP '^\s*### [0-9]+\.' "$AGENTS_FILE" 2>/dev/null || echo 0)

  # Extract per-rule metrics
  RULE_DETAILS=""
  TOTAL_RULE_LINES=0
  TOTAL_RULE_WORDS=0
  TOTAL_CONDITIONALS=0
  TOTAL_SUB_STEPS=0
  TOTAL_PASSIVE=0

  # Get line numbers of each rule header and the next section
  rule_starts=()
  while IFS= read -r line; do
    rule_starts+=("$line")
  done < <(grep -nP '^\s*### [0-9]+\.' "$AGENTS_FILE" | cut -d: -f1)

  # Find end of rules section (next ## heading after rules, or Signal Dispatch)
  rules_section_end=$(grep -nP '^## (Signal Dispatch|Quick Orientation)' "$AGENTS_FILE" | head -1 | cut -d: -f1)
  [[ -z "$rules_section_end" ]] && rules_section_end=$TOTAL_LINES

  for i in "${!rule_starts[@]}"; do
    start=${rule_starts[$i]}
    if [[ $((i + 1)) -lt ${#rule_starts[@]} ]]; then
      end=$((${rule_starts[$((i + 1))]} - 1))
    else
      end=$((rules_section_end - 1))
    fi

    rule_name=$(sed -n "${start}p" "$AGENTS_FILE" | sed 's/^### [0-9]*\. //')
    rule_lines=$((end - start + 1))
    rule_text=$(sed -n "${start},${end}p" "$AGENTS_FILE")
    rule_words=$(echo "$rule_text" | wc -w)
    rule_conditionals=$(echo "$rule_text" | grep -ciP '\bif\b|\bwhen\b|\bunless\b' 2>/dev/null || true)
    [[ -z "$rule_conditionals" ]] && rule_conditionals=0
    rule_sub_steps=$(echo "$rule_text" | grep -cP '^\s*[0-9]+\.' 2>/dev/null || true)
    [[ -z "$rule_sub_steps" ]] && rule_sub_steps=0
    rule_passive=$(echo "$rule_text" | grep -ciP '\b(is|are|was|were|been|being)\s+\w+ed\b' 2>/dev/null || true)
    [[ -z "$rule_passive" ]] && rule_passive=0

    RULE_DETAILS+="Rule $((i + 1)) ($rule_name): $rule_lines lines, $rule_words words, $rule_sub_steps sub-steps, $rule_conditionals conditionals, $rule_passive passive voice
"
    TOTAL_RULE_LINES=$((TOTAL_RULE_LINES + rule_lines))
    TOTAL_RULE_WORDS=$((TOTAL_RULE_WORDS + rule_words))
    TOTAL_CONDITIONALS=$((TOTAL_CONDITIONALS + rule_conditionals))
    TOTAL_SUB_STEPS=$((TOTAL_SUB_STEPS + rule_sub_steps))
    TOTAL_PASSIVE=$((TOTAL_PASSIVE + rule_passive))
  done

  # Signal dispatch entries
  SIGNAL_COUNT=$(grep -cP '^\| `hey ' "$AGENTS_FILE" 2>/dev/null || echo 0)

  # Scope table entries
  SCOPE_COUNT=$(grep -cP '^\| \*\*(USER|PROJECT|LITE)\*\*' "$AGENTS_FILE" 2>/dev/null || echo 0)

  # Token estimate (rough: words * 1.3)
  TOTAL_WORDS=$(wc -w < "$AGENTS_FILE")
  TOKEN_ESTIMATE=$(echo "$TOTAL_WORDS * 13 / 10" | bc 2>/dev/null || echo "unknown")

  cat <<AGENTS_EOF
Target: AGENTS.md
Version: $VERSION
Total lines: $TOTAL_LINES
Total words: $TOTAL_WORDS
Estimated tokens: $TOKEN_ESTIMATE
Rule count: $RULE_COUNT
Total rule lines: $TOTAL_RULE_LINES
Total rule words: $TOTAL_RULE_WORDS
Total sub-steps across rules: $TOTAL_SUB_STEPS
Total conditionals across rules: $TOTAL_CONDITIONALS
Total passive voice across rules: $TOTAL_PASSIVE
Signal dispatch entries: $SIGNAL_COUNT
Scope definitions: $SCOPE_COUNT
AGENTS_EOF
  printf '%s' "$RULE_DETAILS"
  exit 0
fi

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
ACTION_STEPS=$(grep -cP '^\s*###\s+(Step\s+\d|[0-9]+\.)' "$SKILL_MD" 2>/dev/null || true)
  ACTION_STEPS="${ACTION_STEPS:-0}"
# Fallback: count major workflow steps
if [[ "$ACTION_STEPS" -eq 0 ]]; then
  ACTION_STEPS=$(grep -cP '^\s*##\s+Step\s' "$SKILL_MD" 2>/dev/null || true)
  ACTION_STEPS="${ACTION_STEPS:-0}"
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
  SCRIPTED_STEPS=$(grep -cP '(bash|sh)\s+.*scripts/' "$SKILL_MD" 2>/dev/null || true)
  SCRIPTED_STEPS="${SCRIPTED_STEPS:-0}"
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
SHELL_LINES=$(grep -cP '^\s*(```|.*\$\(|.*\|.*\||.*[<>]{1,2}\s|.*&&\s|^\s*#\s*(bash|sh))' "$SKILL_MD" 2>/dev/null || true)
SHELL_LINES="${SHELL_LINES:-0}"
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

# --- Has operable.yaml (runtime execution correctness schema) ---
HAS_OBS_SCHEMA=false
if [[ -f "$SKILL_DIR/operable.yaml" ]]; then
  HAS_OBS_SCHEMA=true
fi

# --- Has scores.yaml (QOO qualification marker) ---
HAS_SCORES=false
QOO_QUALIFIED=false
if [[ -f "$SKILL_DIR/scores.yaml" ]]; then
  HAS_SCORES=true
  grep -q "qoo-qualified: true" "$SKILL_DIR/scores.yaml" && QOO_QUALIFIED=true
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
Has operable.yaml: $HAS_OBS_SCHEMA
Has scores.yaml: $HAS_SCORES
QOO qualified: $QOO_QUALIFIED
EOF
