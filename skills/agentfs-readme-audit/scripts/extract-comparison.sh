#!/bin/bash
# extract-comparison.sh — Extract per-dimension evidence for SDM evaluation
#
# Takes gather-state.sh output and produces structured evidence
# for SDM scoring. Combines deterministic facts (Stage 1a) with
# relevant README excerpts so SDM can make bounded semantic judgments.
#
# Design: This script performs ONLY deterministic extraction.
# Semantic decisions (is this a claim? is this drift?) are left to
# SDM. The script's job is to present the right evidence, not to
# judge it.
#
# Usage:
#   bash extract-comparison.sh <gather-state-output-file>
#
# Output (stdout):
#   Per-dimension evidence blocks with filesystem facts and README
#   excerpts. SDM evaluates each dimension against its schema question.
#
# Exit codes:
#   0 — Evidence extracted
#   1 — Input file missing or malformed

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 && -f "$1" ]] || die "Usage: extract-comparison.sh <gather-state-output-file>"

INPUT=$(cat "$1")

# ── Stage 1a: Deterministic fact extraction ────────────────────────

SCOPE=$(echo "$INPUT" | grep '^Scope:' | head -1 | awk '{print $2}')
SCOPE=$(echo "$SCOPE" | tr '[:upper:]' '[:lower:]')

FACTS=$(echo "$INPUT" | sed -n '/^=== FILESYSTEM STATE ===/,/^=== README CONTENT ===/p' \
  | head -n -1 | tail -n +2)

SKILL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Skill count: )\d+' || echo "unknown")
KNOWLEDGE_COUNT=$(echo "$FACTS" | grep -oP '(?<=Knowledge bundle count: )\d+' || echo "unknown")
GUARDRAIL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Guardrail count: )\d+' || echo "unknown")
TEMPLATE_VERSION=$(echo "$FACTS" | grep -oP '(?<=Template version: )[\d.]+' || echo "unknown")
PROJECT_SKILL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Project skill count: )\d+' || echo "N/A")
PROFILE_COUNT=$(echo "$FACTS" | grep -oP '(?<=Profile count: )\d+' || echo "N/A")

DIR_TREE=$(echo "$FACTS" | sed -n '/^.*\/.agents\//,/^\s*$/p' | head -15)

# Skills list from filesystem (gather-state uses "Skill list:" heading)
SKILLS_LIST=$(echo "$FACTS" | sed -n '/^Skill list:/,/^$/p' | tail -n +2 | head -60)

# Knowledge bundles list from filesystem
BUNDLES_LIST=$(echo "$FACTS" | sed -n '/^Knowledge bundle list:/,/^$/p' | tail -n +2 | head -20)

README=$(echo "$INPUT" | sed -n '/^=== README CONTENT ===/,$ p' | tail -n +4)
README_LINES=$(echo "$README" | wc -l)

# ── Stage 1b: Per-dimension evidence excerpts ──────────────────────
# Extract relevant README sections for each dimension.
# NO judgment — just present the relevant excerpt alongside the fact.

# D1/P1: Skill count — any numeric mention of skills
SKILL_COUNT_EXCERPTS=$(echo "$README" | grep -n '\b[0-9]\+\s*skills\?\b' 2>/dev/null | head -5 || true)

# D2: Skill categories — the category table
CATEGORY_TABLE=$(echo "$README" | sed -n '/| Category | Examples/,/^$/p' | head -20)

# D3: Knowledge bundles — the bundle list
BUNDLE_LIST_README=$(echo "$README" | sed -n '/Current bundles:/,/^See/p' | head -25)

# D6: Version references — ALL version-like strings with surrounding context
# Strip fenced code blocks (```...```) before grepping to avoid matching
# version numbers inside YAML/HTML examples (e.g., version: "1.0.0" in a
# SKILL.md template example). awk preserves original line numbers.
VERSION_EXCERPTS=$(echo "$README" | awk '/^```/{skip=!skip; next} !skip{print NR":"$0}' \
  | grep 'v[0-9]\+\.[0-9]\+\.[0-9]\+\|[0-9]\+\.[0-9]\+\.[0-9]\+' 2>/dev/null \
  | grep -v 'http\|Copyright\|semver\|e\.g\.\|example' | head -10 || true)

# D4: Directory structure — tree diagrams in README
# Scope-aware: USER scope → only tree blocks without "AGENTS.md" (USER layout)
#              PROJECT scope → only tree blocks with "AGENTS.md" (PROJECT layout)
# Uses temp files because awk record splitting doesn't handle multi-line blocks
# reliably across shell variable expansion.
_D4_TMPDIR=$(mktemp -d)
echo "$README" | awk -v dir="$_D4_TMPDIR" '
  /^```/ { inside=!inside; if(inside){ n++; file=dir"/block_"n }; next }
  inside { print >> file }
'
README_TREES=""
for _f in "$_D4_TMPDIR"/block_*; do
  [[ -f "$_f" ]] || continue
  # Only directory-listing blocks (├── followed by a path-like entry)
  if grep -qP '[├└]── \S+[/.]' "$_f"; then
    # Only top-level directory trees — keep paths starting with ~, ., / or <name>/
    # Skip nested example trees like "skills/my-skill/" that show internal structure
    _first_line=$(head -1 "$_f" | sed 's/^[[:space:]]*//')
    if echo "$_first_line" | grep -qP '^[a-z].*/.+/' ; then
      # Starts with lowercase word and has nested path (e.g., skills/my-skill/) — skip
      continue
    fi
    if [[ "$SCOPE" == "user" ]]; then
      grep -q 'AGENTS\.md' "$_f" || README_TREES="${README_TREES}$(cat "$_f")"$'\n'
    else
      grep -q 'AGENTS\.md' "$_f" && README_TREES="${README_TREES}$(cat "$_f")"$'\n'
    fi
  fi
done
rm -rf "$_D4_TMPDIR"
README_TREES=$(echo "$README_TREES" | head -20)

# D5: Guardrail summary — rule table
RULE_TABLE=$(echo "$README" | sed -n '/| # | Name | When | Do/,/^$/p' | head -15)

# D7: Feature descriptions — skill names in parenthesized backticks
SKILL_REFS=$(echo "$README" | grep -oP '\(`[a-z][\w-]+`\)' | tr -d '()`' | sort -u || true)
# Validate each against filesystem
SKILL_DIR="${HOME}/.agents/skills"
VALID_REFS=""
MISSING_REFS=""
for ref in $SKILL_REFS; do
  [[ "$ref" == *.sh ]] || [[ "$ref" == *.yaml ]] || [[ "$ref" == *.md ]] && continue
  if [[ -d "$SKILL_DIR/$ref" ]]; then
    VALID_REFS="$VALID_REFS $ref"
  else
    MISSING_REFS="$MISSING_REFS $ref"
  fi
done

# D8: Setup instructions — paths and commands
SETUP_SECTION=$(echo "$README" | sed -n '/## Getting Started/,/## Directory Structure/p' | head -40)

# D8 filesystem validation: check key paths and URLs referenced in setup
# This gives the SDM factual context to distinguish "instruction to create"
# from "claim about current state"
AGENTS_ROOT=$(echo "$INPUT" | grep '^Agents root:' | head -1 | awk '{print $3}')
AGENTS_ROOT="${AGENTS_ROOT:-${HOME}/.agents}"
D8_VALIDATIONS=""
if [[ -d "$AGENTS_ROOT" ]]; then
  D8_VALIDATIONS="~/.agents/ directory: EXISTS"
else
  D8_VALIDATIONS="~/.agents/ directory: MISSING"
fi
if [[ -d "$AGENTS_ROOT/.git" ]]; then
  ACTUAL_REMOTE=$(git -C "$AGENTS_ROOT" remote get-url origin 2>/dev/null || echo "unknown")
  D8_VALIDATIONS="${D8_VALIDATIONS}
Git remote origin: $ACTUAL_REMOTE"
fi

# ── Output structured evidence ─────────────────────────────────────

echo "=== README ALIGNMENT EVIDENCE ==="
echo "Scope: $SCOPE"
echo "README length: $README_LINES lines"
echo ""

echo "--- D1: SKILL COUNT ---"
echo "Filesystem: $SKILL_COUNT skills"
if [[ -n "$SKILL_COUNT_EXCERPTS" ]]; then
  echo "README excerpts mentioning skill count:"
  echo "$SKILL_COUNT_EXCERPTS"
else
  echo "README: no numeric skill count found anywhere in the document"
fi
echo ""

echo "--- D2: SKILL CATEGORIES ---"
echo "Filesystem skill count: $SKILL_COUNT"
if [[ -n "$CATEGORY_TABLE" ]]; then
  echo "README category table:"
  echo "$CATEGORY_TABLE"
else
  echo "README: no skill category table found"
fi
echo ""

echo "--- D3: KNOWLEDGE BUNDLES ---"
echo "Filesystem: $KNOWLEDGE_COUNT bundles"
if [[ -n "$BUNDLE_LIST_README" ]]; then
  LISTED_COUNT=$(echo "$BUNDLE_LIST_README" | grep -c '^- \*\*' || true)
  echo "README lists $LISTED_COUNT bundles:"
  echo "$BUNDLE_LIST_README"
else
  echo "README: no knowledge bundle list found"
fi
echo ""

echo "--- D4: DIRECTORY STRUCTURE ---"
echo "NOTE: The README tree may omit some files (e.g., LICENSE, README.md, _config.yml)."
echo "Omission is NOT a contradiction. Only flag if the README shows directories or files"
echo "that do NOT exist in the filesystem, or claims a structure that is structurally wrong."
echo "Filesystem:"
echo "$DIR_TREE"
if [[ -n "$README_TREES" ]]; then
  echo "README tree diagrams (first):"
  echo "$README_TREES" | head -15
else
  echo "README: no directory tree found"
fi
echo ""

echo "--- D5: GUARDRAIL SUMMARY ---"
echo "Filesystem: $GUARDRAIL_COUNT guardrails"
if [[ -n "$RULE_TABLE" ]]; then
  echo "README rule table:"
  echo "$RULE_TABLE"
else
  echo "README: no guardrail/rule table found"
fi
echo ""

echo "--- D6: VERSION REFERENCES ---"
echo "Filesystem template version: $TEMPLATE_VERSION"
if [[ -n "$VERSION_EXCERPTS" ]]; then
  echo "README lines containing version numbers (with line numbers):"
  echo "$VERSION_EXCERPTS"
else
  echo "README: no version references found"
fi
echo ""

echo "--- D7: FEATURE DESCRIPTIONS ---"
echo "Filesystem skill count: $SKILL_COUNT"
if [[ -n "$VALID_REFS" ]]; then
  echo "Skill names referenced in README that exist: $VALID_REFS"
fi
if [[ -n "$MISSING_REFS" ]]; then
  echo "Skill names referenced in README that DO NOT exist: $MISSING_REFS"
else
  echo "All explicitly referenced skill names exist on filesystem"
fi
echo ""

echo "--- D8: SETUP INSTRUCTIONS ---"
echo "NOTE: Setup instructions describe actions for NEW users to take."
echo "Paths like ~/repos/agentfs are SUGGESTIONS, not claims about current state."
echo "Only flag paths/commands that are structurally wrong (broken syntax, impossible paths)."
if [[ -n "$D8_VALIDATIONS" ]]; then
  echo "Filesystem validation of key setup paths:"
  echo "$D8_VALIDATIONS"
fi
echo ""
if [[ -n "$SETUP_SECTION" ]]; then
  echo "README setup section (first 40 lines):"
  echo "$SETUP_SECTION"
else
  echo "README: no setup/getting-started section found"
fi
echo ""

echo "--- D9: COVERAGE GAPS ---"
echo "Filesystem skills not referenced by name in README:"
if [[ -n "$SKILLS_LIST" ]]; then
  while IFS= read -r skill; do
    [[ -z "$skill" ]] && continue
    if ! grep -q "$skill" <<< "$README" 2>/dev/null; then
      echo "  $skill"
    fi
  done <<< "$SKILLS_LIST"
else
  echo "  (skill list not available from gather-state)"
fi

if [[ "$SCOPE" == "project" ]]; then
  echo ""
  echo "--- P1: PROJECT SKILL COUNT ---"
  echo "Filesystem: $PROJECT_SKILL_COUNT project skills"
  echo ""
  echo "--- P2: AGENT PROFILES ---"
  echo "Filesystem: $PROFILE_COUNT profiles"
fi
