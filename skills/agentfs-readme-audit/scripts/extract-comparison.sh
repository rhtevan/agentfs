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
VERSION_EXCERPTS=$(echo "$README" | grep -n 'v[0-9]\+\.[0-9]\+\.[0-9]\+\|[0-9]\+\.[0-9]\+\.[0-9]\+' 2>/dev/null \
  | grep -v 'http\|Copyright\|semver\|e\.g\.\|example' | head -10 || true)

# D4: Directory structure — tree diagrams in README
README_TREES=$(echo "$README" | sed -n '/^```/,/^```/p' | grep -A20 '├──\|└──' | head -25)

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
