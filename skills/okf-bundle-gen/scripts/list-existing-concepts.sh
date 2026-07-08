#!/usr/bin/env bash
# list-existing-concepts.sh — Inventory existing OKF concepts in a bundle.
#
# Usage: bash list-existing-concepts.sh <BUNDLE_ROOT>
#
# For each concept .md file (non-reserved), prints:
#   <relative-path> | <type> | <title> | <description>
#
# Used by the agent to plan merge operations — identify which concepts
# already exist so new session knowledge can be merged or de-duplicated.

set -euo pipefail

BUNDLE_ROOT="${1:?Usage: list-existing-concepts.sh <BUNDLE_ROOT>}"
BUNDLE_ROOT="$(cd "$BUNDLE_ROOT" && pwd)"

echo "═══════════════════════════════════════════════════════════════"
echo "  Existing OKF Concepts"
echo "  Root: $BUNDLE_ROOT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TOTAL=0

# Header
printf "%-40s | %-20s | %-30s | %s\n" "PATH" "TYPE" "TITLE" "DESCRIPTION"
printf "%-40s-+-%-20s-+-%-30s-+-%s\n" "----------------------------------------" "--------------------" "------------------------------" "-------------------------------------------"

while IFS= read -r -d '' file; do
  relpath="${file#$BUNDLE_ROOT/}"
  basename_file="$(basename "$file")"

  # Skip reserved files
  [[ "$basename_file" == "index.md" || "$basename_file" == "log.md" ]] && continue

  # Check for YAML frontmatter
  first_line="$(head -1 "$file" 2>/dev/null | tr -d '[:space:]')"
  [[ "$first_line" != "---" ]] && continue

  # Extract frontmatter fields
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$file" || true)"
  [[ -z "$frontmatter" ]] && continue

  type_val="$(echo "$frontmatter" | grep -E '^type:' | head -1 | sed 's/^type:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)"
  title_val="$(echo "$frontmatter" | grep -E '^title:' | head -1 | sed 's/^title:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)"
  desc_val="$(echo "$frontmatter" | grep -E '^description:' | head -1 | sed 's/^description:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)"

  # Trim quotes if present
  type_val="${type_val#\"}" ; type_val="${type_val%\"}"
  type_val="${type_val#\'}" ; type_val="${type_val%\'}"
  title_val="${title_val#\"}" ; title_val="${title_val%\"}"
  title_val="${title_val#\'}" ; title_val="${title_val%\'}"
  desc_val="${desc_val#\"}" ; desc_val="${desc_val%\"}"
  desc_val="${desc_val#\'}" ; desc_val="${desc_val%\'}"

  # Truncate long values for display
  [[ ${#title_val} -gt 30 ]] && title_val="${title_val:0:27}..."
  [[ ${#desc_val} -gt 50 ]] && desc_val="${desc_val:0:47}..."

  printf "%-40s | %-20s | %-30s | %s\n" "$relpath" "${type_val:-(none)}" "${title_val:-(none)}" "${desc_val:-(none)}"
  TOTAL=$((TOTAL + 1))
done < <(find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -name "*.md" -print0 2>/dev/null | sort -z)

echo ""
echo "Total concepts: $TOTAL"
echo ""

# Also list subdirectories (sub-bundles)
echo "── Sub-bundles ──"
RESERVED_RE="^(assets|samples|references|scripts|templates|archive)$"
SUB_COUNT=0
while IFS= read -r -d '' dir; do
  dname="$(basename "$dir")"
  [[ "$dname" =~ $RESERVED_RE ]] && continue
  reldir="${dir#$BUNDLE_ROOT/}"
  sub_concepts="$(find "$dir" -maxdepth 1 -type f -name "*.md" ! -name "index.md" ! -name "log.md" 2>/dev/null | wc -l || true)"
  sub_concepts="$(echo "$sub_concepts" | tr -d '[:space:]')"
  has_index="no"
  [[ -f "$dir/index.md" ]] && has_index="yes"
  echo "  $reldir/  (concepts: $sub_concepts, index: $has_index)"
  SUB_COUNT=$((SUB_COUNT + 1))
done < <(find "$BUNDLE_ROOT" -mindepth 1 -name '.*' -prune -o -type d -print0 2>/dev/null | sort -z)

if [[ "$SUB_COUNT" -eq 0 ]]; then
  echo "  (none)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
