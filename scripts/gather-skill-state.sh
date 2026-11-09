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
#   Step excerpts:
#   --- Step 1: Gather State [SCRIPTED: yes] ---
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

  # --- BMBT Evidence (Build-time Readiness) ---

  # has_bones: count rule actions referencing scripts vs total actions
  SCRIPT_REFS=$(grep -cP '\.(sh|bash)\b' "$AGENTS_FILE" 2>/dev/null || echo 0)
  # Count total action lines (numbered steps inside Do blocks)
  TOTAL_ACTIONS=$TOTAL_SUB_STEPS
  if [[ "$TOTAL_ACTIONS" -gt 0 ]]; then
    BONES_RATIO=$(echo "scale=2; $SCRIPT_REFS / $TOTAL_ACTIONS" | bc 2>/dev/null || echo "0")
  else
    BONES_RATIO="0"
  fi

  # has_muscle: CNL compliance — passive voice ratio, multi-action sentences
  # Multi-action: sentences with "and" or ";" joining actions in Do blocks
  MULTI_ACTION=$(grep -cP '(Do:|^\d+\.).*\band\b.*\b(run|write|read|check|ask|report|call|load)\b' "$AGENTS_FILE" 2>/dev/null || echo 0)
  if [[ "$TOTAL_RULE_WORDS" -gt 0 ]]; then
    PASSIVE_RATIO=$(echo "scale=3; $TOTAL_PASSIVE / ($TOTAL_RULE_WORDS / 10)" | bc 2>/dev/null || echo "0")
  else
    PASSIVE_RATIO="0"
  fi
  # CNL compliance: 1.0 minus deductions for passive and multi-action
  CNL_DEDUCTIONS=$((TOTAL_PASSIVE + MULTI_ACTION))
  CNL_VIOLATIONS=$CNL_DEDUCTIONS

  # has_brain: count rules with unbounded semantic judgment
  # Look for judgment words without bounded criteria (open-ended assess/evaluate)
  UNBOUNDED_JUDGMENT=0
  for i in "${!rule_starts[@]}"; do
    start=${rule_starts[$i]}
    if [[ $((i + 1)) -lt ${#rule_starts[@]} ]]; then
      end=$((${rule_starts[$((i + 1))]} - 1))
    else
      end=$((rules_section_end - 1))
    fi
    rule_text=$(sed -n "${start},${end}p" "$AGENTS_FILE")
    # Has semantic judgment words?
    has_judgment=$(echo "$rule_text" | grep -ciP '\b(assess|evaluate|judge|classify|determine complexity)\b' 2>/dev/null || true)
    [[ -z "$has_judgment" ]] && has_judgment=0
    # Has bounding criteria (explicit tiers, enum, table)?
    has_bounds=$(echo "$rule_text" | grep -ciP '\b(tier|standard|specification|criteria|table|enum)\b' 2>/dev/null || true)
    [[ -z "$has_bounds" ]] && has_bounds=0
    if [[ "$has_judgment" -gt 0 && "$has_bounds" -eq 0 ]]; then
      UNBOUNDED_JUDGMENT=$((UNBOUNDED_JUDGMENT + 1))
    fi
  done

  # has_harness: benchmark test coverage
  BENCHMARK_SCRIPT="$HOME/.agents/scripts/benchmark.sh"
  BENCHMARK_TEST_COUNT=0
  if [[ -f "$BENCHMARK_SCRIPT" ]]; then
    # Count unique test definitions (TEST_PROMPT entries)
    BENCHMARK_TEST_COUNT=$(grep -cP 'TEST_PROMPT\[' "$BENCHMARK_SCRIPT" 2>/dev/null || echo 0)
    # Subtract the auto-generated line (template assignment)
    AUTO_GEN=$(grep -cP 'TEST_PROMPT\[\$test_id\]' "$BENCHMARK_SCRIPT" 2>/dev/null || echo 0)
    BENCHMARK_TEST_COUNT=$((BENCHMARK_TEST_COUNT - AUTO_GEN))
  fi
  if [[ "$RULE_COUNT" -gt 0 ]]; then
    HARNESS_RATIO=$(echo "scale=2; $BENCHMARK_TEST_COUNT / $RULE_COUNT" | bc 2>/dev/null || echo "0")
  else
    HARNESS_RATIO="0"
  fi

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
BMBT bones — script references: $SCRIPT_REFS, total actions: $TOTAL_ACTIONS, delegation ratio: $BONES_RATIO
BMBT muscle — CNL violations: $CNL_VIOLATIONS (passive: $TOTAL_PASSIVE, multi-action: $MULTI_ACTION)
BMBT brain — unbounded judgment rules: $UNBOUNDED_JUDGMENT
BMBT harness — benchmark tests: $BENCHMARK_TEST_COUNT for $RULE_COUNT rules, coverage ratio: $HARNESS_RATIO
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

# --- Model tier ---
MODEL_TIER="unknown"
_tier_line=$(grep -oP 'model-tier:\s*\K\S+' "$SKILL_MD" 2>/dev/null || true)
if [[ -n "$_tier_line" ]]; then
  MODEL_TIER="$_tier_line"
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
# Count action steps where the step's text block contains at least one
# script reference. This is step-level coverage, not line-level counting.
# A wrapper script that consolidates two commands into one still counts
# as one scripted step — which is correct (the step is script-backed).
SCRIPTED_STEPS=0
if [[ "$SCRIPT_COUNT" -gt 0 && "$ACTION_STEPS" -gt 0 ]]; then
  # Get line numbers of step headers
  step_lines=()
  while IFS= read -r ln; do
    step_lines+=("$ln")
  done < <(grep -nP '^\s*###\s+(Step\s+\d|[0-9]+\.)' "$SKILL_MD" | cut -d: -f1)
  # Fallback to ## Step headers if ### pattern was the fallback
  if [[ ${#step_lines[@]} -eq 0 ]]; then
    while IFS= read -r ln; do
      step_lines+=("$ln")
    done < <(grep -nP '^\s*##\s+Step\s' "$SKILL_MD" | cut -d: -f1)
  fi

  total_lines_file=$(wc -l < "$SKILL_MD")
  for idx in "${!step_lines[@]}"; do
    start=${step_lines[$idx]}
    if [[ $((idx + 1)) -lt ${#step_lines[@]} ]]; then
      end=$((${step_lines[$((idx + 1))]} - 1))
    else
      # Last step: extend to next ## heading or EOF
      next_section=$(awk -v s="$((start + 1))" 'NR > s && /^##[^#]/ {print NR; exit}' "$SKILL_MD")
      end=${next_section:-$total_lines_file}
    fi
    # Extract step block and check for script reference
    block=$(sed -n "${start},${end}p" "$SKILL_MD")
    if echo "$block" | grep -qP '(bash|sh)\s+.*scripts/'; then
      SCRIPTED_STEPS=$((SCRIPTED_STEPS + 1))
    fi
  done
fi

if [[ "$ACTION_STEPS" -gt 0 ]]; then
  COVERAGE_PCT=$((SCRIPTED_STEPS * 100 / ACTION_STEPS))
else
  COVERAGE_PCT=0
fi

# --- Step excerpts ---
# Extract each step's text with [SCRIPTED: yes/no] marker for SDM evidence.
# Replaces concern_count and accidental_complexity heuristics (v2.0).
# step_lines array may not exist if SCRIPT_COUNT was 0 — initialize if needed.
if [[ -z "${step_lines+x}" ]]; then
  step_lines=()
  if [[ "$ACTION_STEPS" -gt 0 ]]; then
    while IFS= read -r ln; do
      step_lines+=("$ln")
    done < <(grep -nP '^\s*###\s+(Step\s+\d|[0-9]+\.)' "$SKILL_MD" | cut -d: -f1)
    if [[ ${#step_lines[@]} -eq 0 ]]; then
      while IFS= read -r ln; do
        step_lines+=("$ln")
      done < <(grep -nP '^\s*##\s+Step\s' "$SKILL_MD" | cut -d: -f1)
    fi
  fi
fi
STEP_EXCERPTS=""
if [[ "$ACTION_STEPS" -gt 0 && ${#step_lines[@]} -gt 0 ]]; then
  total_lines_file=${total_lines_file:-$(wc -l < "$SKILL_MD")}
  for idx in "${!step_lines[@]}"; do
    start=${step_lines[$idx]}
    if [[ $((idx + 1)) -lt ${#step_lines[@]} ]]; then
      end=$((${step_lines[$((idx + 1))]} - 1))
    else
      next_section=$(awk -v s="$((start + 1))" 'NR > s && /^##[^#]/ {print NR; exit}' "$SKILL_MD")
      end=${next_section:-$total_lines_file}
    fi
    # Get step header
    header=$(sed -n "${start}p" "$SKILL_MD" | sed 's/^### //')
    # Extract block
    block=$(sed -n "${start},${end}p" "$SKILL_MD")
    # Check for script reference
    if echo "$block" | grep -qP '(bash|sh)\s+.*scripts/'; then
      scripted="yes"
    else
      scripted="no"
    fi
    # Strip code fence markers, cap at 20 lines for SDM context
    clean_block=$(echo "$block" | grep -v '^```' | head -20)
    STEP_EXCERPTS+="--- ${header} [SCRIPTED: ${scripted}] ---
${clean_block}
"
  done
fi

TOTAL_LINES=$(wc -l < "$SKILL_MD")

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

# --- Anti-fabrication rules ---
HAS_ANTI_FABRICATION=false
ANTI_FAB_RULES=0
if grep -qiP '(do not|do NOT|never|must not).*(generat|fabricat|invent|make up|hallucin)' "$SKILL_MD" 2>/dev/null; then
  HAS_ANTI_FABRICATION=true
  ANTI_FAB_RULES=$(grep -ciP '(do not|do NOT|never|must not).*(generat|fabricat|invent|make up|hallucin)' "$SKILL_MD" 2>/dev/null || true)
fi

# --- CNL compliance analysis ---
# Count action sentences (imperative lines in workflow/step sections)
BODY=$(sed '/^---$/,/^---$/d' "$SKILL_MD")
ACTION_SENTENCES=$(echo "$BODY" | grep -cP '^\s*(Run |Execute |Read |Write |Set |Check |Report |Present |If |Stop |Do NOT|Do not)' 2>/dev/null || true)
ACTION_SENTENCES="${ACTION_SENTENCES:-0}"
# Multi-action sentences (two verbs joined by 'and' or ';')
MULTI_ACTION=$(echo "$BODY" | grep -cP '(Run|Execute|Read|Write|Check|Report).*(and|;)\s*(run|execute|read|write|check|report)' 2>/dev/null || true)
MULTI_ACTION="${MULTI_ACTION:-0}"
# CNL compliance ratio: 1.0 minus deductions
if [[ "$ACTION_SENTENCES" -gt 0 ]]; then
  CNL_VIOLATIONS=$((PASSIVE_VOICE + MULTI_ACTION))
  CNL_COMPLIANT=$((ACTION_SENTENCES - CNL_VIOLATIONS))
  if [[ "$CNL_COMPLIANT" -lt 0 ]]; then CNL_COMPLIANT=0; fi
  CNL_RATIO=$(awk "BEGIN {printf \"%.2f\", $CNL_COMPLIANT / $ACTION_SENTENCES}")
else
  CNL_VIOLATIONS=0
  CNL_RATIO="1.00"
fi

# --- SDM delegation ---
HAS_SDM_DELEGATION=false
SDM_SCRIPT_COUNT=0
if [[ "$SCRIPT_COUNT" -gt 0 ]]; then
  SDM_SCRIPT_COUNT=$(grep -rl 'sdm-call\|sdm-evaluate\|/v1/decisions\|/v1/systemone' "$SKILL_DIR/scripts/" 2>/dev/null | wc -l || true)
  SDM_SCRIPT_COUNT="${SDM_SCRIPT_COUNT:-0}"
  if [[ "$SDM_SCRIPT_COUNT" -gt 0 ]]; then
    HAS_SDM_DELEGATION=true
  fi
fi
# Also check SKILL.md for SDM references (skill may call sdm-evaluate.sh via orchestration)
SDM_SKILL_REFS=$(grep -cP 'sdm-(call|evaluate)\.sh|/v1/decisions|/v1/systemone' "$SKILL_MD" 2>/dev/null || true)
SDM_SKILL_REFS="${SDM_SKILL_REFS:-0}"
if [[ "$SDM_SKILL_REFS" -gt 0 ]]; then
  HAS_SDM_DELEGATION=true
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
Model tier: $MODEL_TIER
Total lines in SKILL.md: $TOTAL_LINES
Action steps in SKILL.md: $ACTION_STEPS
Scripts in scripts/ directory: $SCRIPT_COUNT
Script list: ${SCRIPT_LIST:-none}
Scripted action steps: $SCRIPTED_STEPS
Script coverage: $SCRIPTED_STEPS of $ACTION_STEPS action steps backed by scripts (${COVERAGE_PCT}%).
Model assumptions detected: $MODEL_ASSUMPTIONS
Conditional logic blocks: $CONDITIONAL_BLOCKS
Passive voice instances: $PASSIVE_VOICE
Trace instrumentation: $HAS_TRACE
Anti-fabrication rules: $HAS_ANTI_FABRICATION (${ANTI_FAB_RULES} rules found)
CNL compliance: ${CNL_RATIO} (${ACTION_SENTENCES} action sentences, ${CNL_VIOLATIONS} violations: ${PASSIVE_VOICE} passive, ${MULTI_ACTION} multi-action)
sdm_delegation: $(if [[ "$HAS_SDM_DELEGATION" == "true" ]]; then echo "YES — judgment delegated to SDM via ${SDM_SCRIPT_COUNT} scripts (${SDM_SKILL_REFS} SKILL.md references)"; elif [[ "$CONDITIONAL_BLOCKS" -le 2 && "$MODEL_ASSUMPTIONS" -eq 0 ]]; then echo "YES — this skill does not require semantic judgment (exempt)"; else echo "NO — semantic judgment is handled inline by agent, not delegated to SDM (${SDM_SCRIPT_COUNT} scripts, ${SDM_SKILL_REFS} SKILL.md references)"; fi)
Has operable.yaml: $HAS_OBS_SCHEMA
Has scores.yaml: $HAS_SCORES
QOO qualified: $QOO_QUALIFIED
EOF

# Append step excerpts after the structured facts
if [[ -n "$STEP_EXCERPTS" ]]; then
  echo ""
  echo "Step excerpts:"
  printf '%s' "$STEP_EXCERPTS"
fi
