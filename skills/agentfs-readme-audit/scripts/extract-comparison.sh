#!/bin/bash
# extract-comparison.sh — Extract compact README-vs-filesystem comparison
#
# Takes gather-state.sh output and produces a concise comparison
# suitable for SDM evidence input. Deterministic, no LLM.
#
# Usage:
#   bash extract-comparison.sh <gather-state-output-file>
#
# Output (stdout):
#   Compact text with FILESYSTEM FACTS and README CLAIMS side by side.
#   Designed to fit within ~500 tokens for SDM single-token evaluation.
#
# Exit codes:
#   0 — Comparison extracted
#   1 — Input file missing or malformed

set -euo pipefail

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -ge 1 && -f "$1" ]] || die "Usage: extract-comparison.sh <gather-state-output-file>"

INPUT=$(cat "$1")

# --- Extract scope ---
SCOPE=$(echo "$INPUT" | grep '^Scope:' | head -1 | awk '{print $2}')
SCOPE=$(echo "$SCOPE" | tr '[:upper:]' '[:lower:]')

# --- Extract filesystem facts ---
FACTS=$(echo "$INPUT" | sed -n '/^=== FILESYSTEM STATE ===/,/^=== README CONTENT ===/p' \
  | head -n -1 | tail -n +2)

SKILL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Skill count: )\d+' || echo "unknown")
KNOWLEDGE_COUNT=$(echo "$FACTS" | grep -oP '(?<=Knowledge bundle count: )\d+' || echo "unknown")
GUARDRAIL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Guardrail count: )\d+' || echo "unknown")
TEMPLATE_VERSION=$(echo "$FACTS" | grep -oP '(?<=Template version: )[\d.]+' || echo "unknown")

# Project-scope facts
PROJECT_SKILL_COUNT=$(echo "$FACTS" | grep -oP '(?<=Project skill count: )\d+' || echo "N/A")
PROFILE_COUNT=$(echo "$FACTS" | grep -oP '(?<=Profile count: )\d+' || echo "N/A")

# Top-level dirs
DIR_TREE=$(echo "$FACTS" | sed -n '/^.*\/.agents\//,/^\s*$/p' | head -15)

# --- Extract README content ---
README=$(echo "$INPUT" | sed -n '/^=== README CONTENT ===/,$ p' | tail -n +4)
README_LINES=$(echo "$README" | wc -l)

# --- Extract README claims ---

# Skill count: all numeric mentions of "N skill(s)"
SKILL_CLAIMS=$(echo "$README" | grep -oP '\b\d+\s+skills?\b' 2>/dev/null | sort -u || true)
[[ -z "$SKILL_CLAIMS" ]] && SKILL_CLAIMS="not mentioned"

# Knowledge bundle count
KB_CLAIMS=$(echo "$README" | grep -oP '\b\d+\s+knowledge\s+bundles?\b' 2>/dev/null | sort -u || true)
[[ -z "$KB_CLAIMS" ]] && KB_CLAIMS="not mentioned"

# Guardrail/rule count
RULE_CLAIMS=$(echo "$README" | grep -oP '\b\d+\s+(operational\s+)?rules?\b' 2>/dev/null | sort -u || true)
GUARDRAIL_CLAIMS=$(echo "$README" | grep -oP '\b\d+\s+guardrails?\b' 2>/dev/null | sort -u || true)
COMBINED_RULE_CLAIMS="${RULE_CLAIMS}${GUARDRAIL_CLAIMS:+ $GUARDRAIL_CLAIMS}"
[[ -z "$COMBINED_RULE_CLAIMS" ]] && COMBINED_RULE_CLAIMS="not mentioned"

# Version references
VERSION_CLAIMS=$(echo "$README" | grep -oP 'v[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null | sort -u || true)
[[ -z "$VERSION_CLAIMS" ]] && VERSION_CLAIMS="not mentioned"

# Directory tree presence
# Note: use here-strings (<<<) not pipes. With pipefail, echo|grep -q
# triggers SIGPIPE on large input because grep exits early on match.
HAS_TREE="no"
if grep -qE '├──|└──' <<< "$README" 2>/dev/null; then HAS_TREE="yes"; fi

# Setup/install instructions
HAS_SETUP="no"
if grep -qiE '## getting started|## setup|## install|## quick start' <<< "$README" 2>/dev/null; then HAS_SETUP="yes"; fi

# Links to index files
LINKS_INDEX="no"
if grep -qE 'skills/index\.md|knowledge/index\.md' <<< "$README" 2>/dev/null; then LINKS_INDEX="yes"; fi

# Skill categories/catalog
HAS_CATEGORIES="no"
if grep -qiE '## skill|categories|catalog|### .* skills' <<< "$README" 2>/dev/null; then HAS_CATEGORIES="yes"; fi

# --- Output comparison ---
echo "=== README ALIGNMENT COMPARISON ==="
echo "Scope: $SCOPE"
echo "README length: $README_LINES lines"
echo ""
echo "FILESYSTEM FACTS:"
echo "  Skill count: $SKILL_COUNT"
echo "  Knowledge bundle count: $KNOWLEDGE_COUNT"
echo "  Guardrail count: $GUARDRAIL_COUNT"
echo "  Template version: $TEMPLATE_VERSION"
if [[ "$SCOPE" == "project" ]]; then
  echo "  Project skill count: $PROJECT_SKILL_COUNT"
  echo "  Profile count: $PROFILE_COUNT"
fi
echo ""
echo "README CLAIMS:"
echo "  Skill count: $SKILL_CLAIMS"
echo "  Knowledge bundle count: $KB_CLAIMS"
echo "  Guardrail/rule count: $COMBINED_RULE_CLAIMS"
echo "  Version references: $VERSION_CLAIMS"
echo "  Shows directory tree: $HAS_TREE"
echo "  Has setup instructions: $HAS_SETUP"
echo "  Links to index files: $LINKS_INDEX"
echo "  Describes skill categories: $HAS_CATEGORIES"
echo ""
echo "DIRECTORY STRUCTURE (filesystem):"
echo "$DIR_TREE"
