#!/bin/bash
# evaluate-readme.sh — SDM-powered README alignment evaluation
#
# Takes gather-state.sh output (piped or file), extracts facts and
# README content, builds SDM predicate questions for each audit
# dimension, and produces a structured alignment report.
#
# This is Pattern 1 SDM integration: semantic judgment delegated to
# SDM via script, replacing inline LLM multi-hop reasoning.
#
# Usage:
#   bash gather-state.sh | bash evaluate-readme.sh
#   bash evaluate-readme.sh <gathered-state-file>
#
# Output (stdout):
#   Markdown alignment report with per-dimension verdicts.
#
# Exit codes:
#   0 — Evaluation complete (aligned or drift detected)
#   1 — SDM evaluation failed
#   2 — SDM endpoint unreachable
#   3 — Usage error (no input)
#
# Trace integration:
#   Sources trace-lib.sh if AGENTFS_TRACE is set.

set -uo pipefail
# Note: -e (errexit) intentionally omitted. This script uses || true
# patterns for optional grep extractions that would trigger SIGPIPE
# with grep|head pipes under set -e + pipefail. Error handling is
# explicit via exit code checks after SDM calls.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDM_CALL="${HOME}/.agents/scripts/sdm-call.sh"
TRACE_LIB="${HOME}/.agents/scripts/trace-lib.sh"

# --- Trace setup (optional) ---
_trace=false
if [[ -n "${AGENTFS_TRACE:-}" ]] && [[ -f "$TRACE_LIB" ]]; then
  source "$TRACE_LIB"
  _trace=true
fi

trace() {
  if [[ "$_trace" == "true" ]]; then
    trace_step "$@"
  fi
}

trace_tok() {
  if [[ "$_trace" == "true" ]]; then
    trace_tokens "$@"
  fi
}

die() { echo "ERROR: $*" >&2; exit 3; }

# --- Dependency check ---
command -v jq >/dev/null 2>&1 || die "jq is required but not found."
[[ -x "$SDM_CALL" ]] || die "sdm-call.sh not found at $SDM_CALL"

# --- Read input ---
INPUT=""
if [[ $# -ge 1 ]] && [[ -f "$1" ]]; then
  INPUT=$(cat "$1")
elif [[ ! -t 0 ]]; then
  INPUT=$(cat)
else
  die "Usage: bash gather-state.sh | bash evaluate-readme.sh, or: bash evaluate-readme.sh <file>"
fi

[[ -n "$INPUT" ]] || die "Empty input — nothing to evaluate"

# --- Parse scope from input ---
SCOPE=$(echo "$INPUT" | grep '^Scope:' | head -1 | awk '{print $2}')
SCOPE=$(echo "$SCOPE" | tr '[:upper:]' '[:lower:]')

[[ "$SCOPE" == "user" || "$SCOPE" == "project" ]] || die "Cannot determine scope from input (got: $SCOPE)"

trace 0 "parse_scope" 0 "scope=$SCOPE"

# --- Extract sections ---
# Facts = everything between === FILESYSTEM STATE === and === README CONTENT ===
FACTS=$(echo "$INPUT" | sed -n '/^=== FILESYSTEM STATE ===/,/^=== README CONTENT ===/p' \
  | head -n -1 | tail -n +2)

# README = everything after === README CONTENT ===, skipping the header lines
README=$(echo "$INPUT" | sed -n '/^=== README CONTENT ===/,$ p' | tail -n +4)

[[ -n "$FACTS" ]] || die "No filesystem state found in input"
[[ -n "$README" ]] || die "No README content found in input"

# --- Truncate README for SDM context window ---
# SDM has limited context. Send first 100 lines of README (covers
# structure, counts, scope definitions — the parts that matter for
# alignment). The full README is 800+ lines; most alignment-relevant
# claims are in the first 100 lines.
README_TRUNCATED=$(echo "$README" | head -100)
README_LINES=$(echo "$README" | wc -l)

trace 1 "extract_evidence" 0 "facts_lines=$(echo "$FACTS" | wc -l),readme_lines=$README_LINES"

# --- Compact facts for SDM context window ---
# Extract only summary metrics, not full lists. SDM needs explicit
# facts, not raw data. Full lists are available for LLM consumption
# in the original gather-state output.
FACTS_COMPACT=$(echo "$FACTS" | grep -E '^(Skill count|Knowledge bundle count|Guardrail count|Template version|Project skill count|Profile count)' || true)
if [[ -z "$FACTS_COMPACT" ]]; then
  FACTS_COMPACT="$FACTS"
fi

# --- Extract README summary for SDM ---
# Instead of raw README (special chars break shell), produce explicit
# comparison statements. SDM judges meaning, not computes.
README_HAS_SKILL_COUNT="no"
README_SKILL_COUNT_VALUE=""
_sc=$(echo "$README" | grep -oP '\b(\d+)\s+skills?\b' | head -1 || true)
if [[ -n "$_sc" ]]; then
  README_HAS_SKILL_COUNT="yes"
  README_SKILL_COUNT_VALUE=$(echo "$_sc" | grep -oP '\d+')
fi

README_HAS_KNOWLEDGE="no"
README_KNOWLEDGE_COUNT_VALUE=""
if echo "$README" | grep -qi 'knowledge bundle' 2>/dev/null; then
  README_HAS_KNOWLEDGE="yes"
  _kc=$(echo "$README" | grep -oP '\b(\d+)\s+knowledge\s+bundle' | head -1 || true)
  if [[ -n "$_kc" ]]; then
    README_KNOWLEDGE_COUNT_VALUE=$(echo "$_kc" | grep -oP '\d+')
  fi
fi

README_HAS_VERSION="no"
README_VERSION_VALUE=""
_rv=$(echo "$README" | grep -oP 'v[0-9]+\.[0-9]+\.?[0-9]*|version\s*[0-9]+\.[0-9]+' | head -1 || true)
if [[ -n "$_rv" ]]; then
  README_HAS_VERSION="yes"
  README_VERSION_VALUE="$_rv"
fi

README_HAS_GUARDRAILS="no"
README_GUARDRAIL_COUNT_VALUE=""
_gc=$(echo "$README" | grep -oP '\b(\d+)\s+(operational\s+)?rules?\b' | head -1 || true)
if [[ -n "$_gc" ]]; then
  README_HAS_GUARDRAILS="yes"
  README_GUARDRAIL_COUNT_VALUE=$(echo "$_gc" | grep -oP '\d+')
fi

README_HAS_TREE="no"
if echo "$README" | grep -q 'skills/' 2>/dev/null && echo "$README" | grep -q 'knowledge/' 2>/dev/null; then
  README_HAS_TREE="yes"
fi

README_HAS_SETUP="no"
if echo "$README" | grep -qi 'getting started\|setup\|install' 2>/dev/null; then
  README_HAS_SETUP="yes"
fi

README_LINKS_INDEX="no"
if echo "$README" | grep -q 'skills/index.md\|knowledge/index.md' 2>/dev/null; then
  README_LINKS_INDEX="yes"
fi

README_BUNDLE_LIST_COUNT=0
_blc=$(echo "$README" | grep -c '^\- \*\*' 2>/dev/null || true)
README_BUNDLE_LIST_COUNT="${_blc:-0}"

# --- Build evidence string ---
EVIDENCE="Filesystem: Skill count=${FACTS_COMPACT%%$'\n'*}. ${FACTS_COMPACT}
README: total lines=${README_LINES}. Has skill count=${README_HAS_SKILL_COUNT} (value=${README_SKILL_COUNT_VALUE:-none}). Has knowledge bundles=${README_HAS_KNOWLEDGE} (value=${README_KNOWLEDGE_COUNT_VALUE:-none}). Listed bundles=${README_BUNDLE_LIST_COUNT}. Has version=${README_HAS_VERSION} (value=${README_VERSION_VALUE:-none}). Has guardrails=${README_HAS_GUARDRAILS} (value=${README_GUARDRAIL_COUNT_VALUE:-none}). Has directory tree=${README_HAS_TREE}. Has setup instructions=${README_HAS_SETUP}. Links to index files=${README_LINKS_INDEX}."

# --- Build dimension questions based on scope ---

build_user_questions() {
  jq -n '[
    {
      "name": "D1_skill_count",
      "type": "predicate",
      "instructions": "Does the README mention a skill count, and if so, does it match the actual skill count from the filesystem facts? If the README does not mention a specific count, answer yes (absence is not drift)."
    },
    {
      "name": "D2_skill_categories",
      "type": "predicate",
      "instructions": "Does the README describe skill categories or a skill catalog that reflects the actual skills listed in the filesystem facts? If the README links to an index file rather than listing skills inline, answer yes."
    },
    {
      "name": "D3_knowledge_bundles",
      "type": "predicate",
      "instructions": "If the README mentions knowledge bundles, does the count or list match the actual knowledge bundle count and list from the filesystem facts? If the README does not mention knowledge bundles at all, answer yes."
    },
    {
      "name": "D4_directory_structure",
      "type": "predicate",
      "instructions": "If the README shows a directory tree or file listing, does it match the actual top-level directory structure from the filesystem facts? If the README does not show a tree, answer yes."
    },
    {
      "name": "D5_guardrail_summary",
      "type": "predicate",
      "instructions": "If the README lists guardrails or operational rules, do the names and count match the actual guardrails from the filesystem facts? If the README does not list guardrails, answer yes."
    },
    {
      "name": "D6_version_references",
      "type": "predicate",
      "instructions": "If the README mentions version numbers (e.g., template version, AgentFS version), do they match the actual template version from the filesystem facts? If no versions are mentioned, answer yes."
    },
    {
      "name": "D7_feature_descriptions",
      "type": "predicate",
      "instructions": "Do the capability and feature descriptions in the README reflect skills that actually exist in the filesystem? Are there features described in the README that have no backing skill, or major skills with no README mention?"
    },
    {
      "name": "D8_setup_instructions",
      "type": "predicate",
      "instructions": "If the README has setup or installation instructions, do the paths and commands still work given the actual directory structure? If no setup instructions exist, answer yes."
    },
    {
      "name": "D9_coverage_gaps",
      "type": "predicate",
      "instructions": "Are there major content categories on the filesystem (large numbers of skills, knowledge bundles, or other resources) that the README does not mention at all? Answer NO if significant content exists but is completely unacknowledged. Answer YES if the README adequately covers or links to the major content."
    }
  ]'
}

build_project_questions() {
  jq -n '[
    {
      "name": "P1_project_skill_count",
      "type": "predicate",
      "instructions": "If the README mentions project-scoped skills, does the count match the actual project skill count from the filesystem facts? If the README does not mention project skills, answer yes."
    },
    {
      "name": "P2_agent_profiles",
      "type": "predicate",
      "instructions": "If the README lists agent profiles, do they match the actual profiles from the filesystem facts? If the README does not mention profiles, answer yes."
    },
    {
      "name": "P3_agent_identity",
      "type": "predicate",
      "instructions": "If the README describes the agent identity or persona, does it match the SOUL.md content from the filesystem facts? If the README does not describe agent identity, answer yes."
    },
    {
      "name": "P4_directory_structure",
      "type": "predicate",
      "instructions": "If the README shows a directory tree or file listing for the project .agents/ directory, does it match the actual directory structure from the filesystem facts? If no tree is shown, answer yes."
    },
    {
      "name": "P5_agentsmd_references",
      "type": "predicate",
      "instructions": "If the README references guardrails, rules, or AGENTS.md content, are those references accurate based on the AGENTS.md summary in the filesystem facts? If no references exist, answer yes."
    },
    {
      "name": "P6_feature_descriptions",
      "type": "predicate",
      "instructions": "Do the capability descriptions in the README reflect what actually exists in the project .agents/ directory? Are there described features with no backing file?"
    },
    {
      "name": "P7_setup_onboarding",
      "type": "predicate",
      "instructions": "If the README has setup or onboarding instructions, do the paths and commands work given the actual directory structure? If no setup instructions exist, answer yes."
    },
    {
      "name": "P8_coverage_gaps",
      "type": "predicate",
      "instructions": "Are there major content categories in the project .agents/ (skills, profiles, agent identity) that the README does not mention at all? Answer NO if significant content exists but is unacknowledged. Answer YES if coverage is adequate."
    }
  ]'
}

# --- Build questions for the detected scope ---
if [[ "$SCOPE" == "user" ]]; then
  QUESTIONS=$(build_user_questions)
  DIMENSION_LABELS=("D1 Skill Count" "D2 Skill Categories" "D3 Knowledge Bundles" "D4 Directory Structure" "D5 Guardrail Summary" "D6 Version References" "D7 Feature Descriptions" "D8 Setup Instructions" "D9 Coverage Gaps")
else
  QUESTIONS=$(build_project_questions)
  DIMENSION_LABELS=("P1 Project Skill Count" "P2 Agent Profiles" "P3 Agent Identity" "P4 Directory Structure" "P5 AGENTS.md References" "P6 Feature Descriptions" "P7 Setup / Onboarding" "P8 Coverage Gaps")
fi

DIM_COUNT=$(echo "$QUESTIONS" | jq 'length')

trace 2 "build_questions" 0 "scope=$SCOPE,dimensions=$DIM_COUNT"

# --- Call SDM ---
# Write questions to temp file (JSON can be large).
# Evidence is compact (~10 lines of facts + claims).
QUESTIONS_FILE=$(mktemp /tmp/readme-eval-questions.XXXXXX)
trap 'rm -f "$QUESTIONS_FILE"' EXIT
echo "$QUESTIONS" > "$QUESTIONS_FILE"

SDM_RESPONSE=""
sdm_exit=0
SDM_RESPONSE=$("$SDM_CALL" --input "$EVIDENCE" --questions-file "$QUESTIONS_FILE" 2>/dev/null) || sdm_exit=$?

if [[ $sdm_exit -eq 2 ]]; then
  echo "ERROR: SDM endpoint unreachable." >&2
  exit 2
fi

if [[ $sdm_exit -ne 0 ]] || [[ -z "$SDM_RESPONSE" ]]; then
  echo "ERROR: SDM call failed (exit $sdm_exit)." >&2
  exit 1
fi

trace 3 "sdm_evaluate" 0 "dimensions=$DIM_COUNT"

# Extract token usage for tracing
INPUT_TOKENS=$(echo "$SDM_RESPONSE" | jq -r '.usage.input_tokens // 0')
OUTPUT_TOKENS=$(echo "$SDM_RESPONSE" | jq -r '.usage.output_tokens // 0')
trace_tok 3 "sdm" "$INPUT_TOKENS" "$OUTPUT_TOKENS"

# --- Parse results and build report ---
ANSWERS=$(echo "$SDM_RESPONSE" | jq '.answers')

ALIGNED=0
DRIFT=0
GAPS=0
REPORT_ROWS=""

for i in $(seq 0 $((DIM_COUNT - 1))); do
  label="${DIMENSION_LABELS[$i]}"
  prob=$(echo "$ANSWERS" | jq -r ".[$i].probability // 0")
  name=$(echo "$ANSWERS" | jq -r ".[$i].name // \"unknown\"")

  # Determine status
  status=""
  if (( $(echo "$prob >= 0.7" | bc -l) )); then
    status="✅"
    ALIGNED=$((ALIGNED + 1))
  elif (( $(echo "$prob >= 0.3" | bc -l) )); then
    status="⚠️ uncertain"
    DRIFT=$((DRIFT + 1))
  else
    # D9/P8 coverage gaps are informational, not drift
    if [[ "$name" == "D9_coverage_gaps" ]] || [[ "$name" == "P8_coverage_gaps" ]]; then
      status="ℹ️ Gap"
      GAPS=$((GAPS + 1))
    else
      status="⚠️ DRIFT"
      DRIFT=$((DRIFT + 1))
    fi
  fi

  # Format probability as percentage for detail
  prob_pct=$(echo "$prob" | awk '{printf "%.0f%%", $1 * 100}')

  REPORT_ROWS+="| ${label} | ${status} | confidence: ${prob_pct} |
"
done

trace 4 "build_report" 0 "aligned=$ALIGNED,drift=$DRIFT,gaps=$GAPS"

# --- Determine verdict ---
VERDICT=""
if [[ $DRIFT -eq 0 ]] && [[ $GAPS -eq 0 ]]; then
  VERDICT="✅ **ALIGNED** — README accurately reflects current AgentFS state."
elif [[ $DRIFT -eq 0 ]] && [[ $GAPS -gt 0 ]]; then
  VERDICT="ℹ️ **COVERAGE GAPS** — ${GAPS} content area(s) exist but are not mentioned in README. Non-blocking."
else
  VERDICT="⚠️ **DRIFT DETECTED** — ${DRIFT} dimension(s) misaligned. Recommend updating README before push."
fi

# --- Output report ---
SCOPE_UPPER=$(echo "$SCOPE" | tr '[:lower:]' '[:upper:]')

cat <<REPORT
## README Alignment Report (${SCOPE_UPPER} scope)

| Dimension | Status | Detail |
|-----------|--------|--------|
${REPORT_ROWS}
### Verdict

${VERDICT}

### Summary

- Aligned: ${ALIGNED}/${DIM_COUNT}
- Drift: ${DRIFT}/${DIM_COUNT}
- Coverage gaps: ${GAPS}/${DIM_COUNT}
- SDM tokens: ${INPUT_TOKENS} input, ${OUTPUT_TOKENS} output
REPORT

trace 5 "report_complete" 0 "verdict=$(echo "$VERDICT" | head -c 20)"
