#!/usr/bin/env bash
# harvest-summary.sh — Generate a summary report of harvest candidates
#                      from one or more project MEMORY.md files.
#
# Usage: bash harvest-summary.sh <PROJECT_ROOT> [<PROJECT_ROOT>...]
#
# Scans all MEMORY.md and USER.md files in each project's .agents/
# directory, aggregates entries, identifies cross-project duplicates,
# and produces a report suitable for the agent to review.
#
# This script does NOT make graduation decisions — it provides the
# raw data for the agent to analyze in Phase 2 of the harvest procedure.

set -euo pipefail

SCAN_SCRIPT="$HOME/.agents/skills/okf-bundle-gen/scripts/scan-memories.sh"

if [[ ! -f "$SCAN_SCRIPT" ]]; then
  echo "ERROR: scan-memories.sh not found at $SCAN_SCRIPT" >&2
  echo "Ensure the okf-bundle-gen skill is installed." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: harvest-summary.sh <PROJECT_ROOT> [<PROJECT_ROOT>...]" >&2
  echo "  Use '.' for current directory" >&2
  exit 1
fi

echo "═══════════════════════════════════════════════════════════════"
echo "  Harvest Candidate Summary"
echo "  Date: $(date '+%Y-%m-%d %H:%M')"
echo "  Projects: $#"
echo "═══════════════════════════════════════════════════════════════"
echo ""

TOTAL_PROJECTS=0
TOTAL_SCANNED=0
SKIPPED_PROJECTS=0
ALL_ENTRIES_FILE=$(mktemp)

for project_root in "$@"; do
  # Expand ~ if present
  project_root="${project_root/#\~/$HOME}"

  # Resolve to absolute path
  if [[ -d "$project_root" ]]; then
    project_root="$(cd "$project_root" && pwd)"
  else
    echo "── SKIP: $project_root — directory not found ──"
    echo ""
    SKIPPED_PROJECTS=$((SKIPPED_PROJECTS + 1))
    continue
  fi

  if [[ ! -d "$project_root/.agents" ]]; then
    echo "── SKIP: $project_root — no .agents/ directory ──"
    echo ""
    SKIPPED_PROJECTS=$((SKIPPED_PROJECTS + 1))
    continue
  fi

  TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))

  # Display-friendly path
  display_path="${project_root/#$HOME/~}"
  echo "══════════════════════════════════════════════════════"
  echo "  Project: $display_path"
  echo "══════════════════════════════════════════════════════"
  echo ""

  # Run the scanner and capture output
  scan_output=$(bash "$SCAN_SCRIPT" "$project_root/.agents" 2>/dev/null || true)
  echo "$scan_output"
  echo ""

  # Extract entries for cross-project analysis
  # Format: PROJECT_PATH|SOURCE|ENTRY
  echo "$scan_output" | while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]*\[([0-9]+)\][[:space:]]+(.*) ]]; then
      entry="${BASH_REMATCH[2]}"
      echo "$display_path|$entry" >> "$ALL_ENTRIES_FILE"
      TOTAL_SCANNED=$((TOTAL_SCANNED + 1))
    fi
  done
done

# Cross-project duplicate analysis
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Cross-Project Analysis"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [[ $TOTAL_PROJECTS -lt 2 ]]; then
  echo "  (Cross-project analysis requires ≥2 projects)"
  echo "  Single-project entries can still be graduated if generalizable."
else
  # Look for similar entries across projects
  # Simple approach: find entries with common significant words
  echo "  Potential cross-project patterns (entries appearing in multiple projects):"
  echo ""

  if [[ -s "$ALL_ENTRIES_FILE" ]]; then
    # Extract unique entries per project, look for content overlap
    # Group by normalized content (lowercase, trimmed)
    python3 - "$ALL_ENTRIES_FILE" <<'PYEOF' 2>/dev/null || echo "  (python3 analysis unavailable — review entries manually)"
import sys
from collections import defaultdict

entries_file = sys.argv[1]

# Read all entries
entries = []  # (project, content)
with open(entries_file) as f:
    for line in f:
        line = line.strip()
        if '|' in line:
            parts = line.split('|', 1)
            if len(parts) == 2:
                entries.append((parts[0].strip(), parts[1].strip()))

if not entries:
    print("  No entries found for cross-project analysis.")
    sys.exit(0)

# Simple word-overlap similarity
def normalize(s):
    """Extract significant words (≥4 chars, lowercase)."""
    import re
    words = re.findall(r'[a-zA-Z]{4,}', s.lower())
    # Remove very common words
    stop = {'this', 'that', 'with', 'from', 'have', 'been', 'will',
            'when', 'they', 'them', 'their', 'there', 'what', 'which',
            'about', 'would', 'could', 'should', 'some', 'other',
            'into', 'also', 'than', 'then', 'more', 'most', 'only',
            'very', 'just', 'like', 'make', 'made', 'does', 'done',
            'each', 'much', 'many', 'well', 'back', 'even', 'over'}
    return set(w for w in words if w not in stop)

# Compare entries across different projects
cross_matches = []
for i, (proj_a, content_a) in enumerate(entries):
    words_a = normalize(content_a)
    if len(words_a) < 2:
        continue
    for j, (proj_b, content_b) in enumerate(entries):
        if j <= i:
            continue
        if proj_a == proj_b:
            continue
        words_b = normalize(content_b)
        if len(words_b) < 2:
            continue
        overlap = words_a & words_b
        similarity = len(overlap) / min(len(words_a), len(words_b))
        if similarity >= 0.4:  # 40% word overlap threshold
            cross_matches.append({
                'proj_a': proj_a,
                'content_a': content_a,
                'proj_b': proj_b,
                'content_b': content_b,
                'overlap': overlap,
                'similarity': similarity
            })

if cross_matches:
    for idx, m in enumerate(cross_matches, 1):
        print(f"  [{idx}] Similarity: {m['similarity']:.0%}")
        print(f"      {m['proj_a']}: {m['content_a'][:80]}")
        print(f"      {m['proj_b']}: {m['content_b'][:80]}")
        print(f"      Common terms: {', '.join(sorted(m['overlap'])[:8])}")
        print()
else:
    print("  No cross-project duplicates detected (by word overlap).")
    print("  Individual entries may still qualify for graduation if generalizable.")
PYEOF
  else
    echo "  No entries collected for analysis."
  fi
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Summary"
echo "  Projects scanned: $TOTAL_PROJECTS"
echo "  Projects skipped: $SKIPPED_PROJECTS"
echo "  (Use the agent's Phase 2 analysis for graduation decisions)"
echo "═══════════════════════════════════════════════════════════════"

# Cleanup
rm -f "$ALL_ENTRIES_FILE"
