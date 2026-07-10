#!/usr/bin/env bash
# scan-procedural.sh — Scan MEMORY.md files and classify entries as
#                      procedural vs declarative vs keep-as-memory.
#
# Usage: bash scan-procedural.sh <PROJECT_ROOT> [<PROJECT_ROOT>...]
#
# Scans all MEMORY.md files in each project's .agents/ directory,
# extracts entries, and classifies them by type using keyword heuristics.
# Outputs a report the agent can use for Phase 2 graduation decisions.
#
# This script provides initial classification — the agent makes final
# graduation decisions based on context and judgment.

set -euo pipefail

SCAN_SCRIPT="$HOME/.agents/skills/okf-bundle-gen/scripts/scan-memories.sh"

if [[ ! -f "$SCAN_SCRIPT" ]]; then
  echo "ERROR: scan-memories.sh not found at $SCAN_SCRIPT" >&2
  echo "Ensure the okf-bundle-gen skill is installed." >&2
  exit 1
fi

if [[ $# -eq 0 ]]; then
  echo "Usage: scan-procedural.sh <PROJECT_ROOT> [<PROJECT_ROOT>...]" >&2
  echo "  Use '.' for current directory" >&2
  exit 1
fi

# Procedural signal words (actions, commands, sequences)
PROCEDURAL_SIGNALS='run|execute|install|deploy|start|stop|restart|apply|delete|create|configure|enable|disable|login|logout|build|test|commit|push|pull|after|before|then|first|next|step|sequence|workflow|script|command|bash|shell|oc |kubectl |docker |podman |make |npm |pip |cargo |go mod|git '

# Declarative signal words (facts, states, observations)
DECLARATIVE_SIGNALS='requires|depends|needs|uses|breaks|fails|prefers|behaves|version|compatible|incompatible|because|discovered|found that|noted that|observed|pattern|architecture|design|principle'

echo "═══════════════════════════════════════════════════════════════"
echo "  Procedural vs Declarative Classification"
echo "  Date: $(date '+%Y-%m-%d %H:%M')"
echo "  Projects: $#"
echo "═══════════════════════════════════════════════════════════════"
echo ""

for project_root in "$@"; do
  # Expand ~ if present
  project_root="${project_root/#\~/$HOME}"

  # Resolve to absolute path
  if [[ -d "$project_root" ]]; then
    project_root="$(cd "$project_root" && pwd)"
  else
    echo "── SKIP: $project_root — directory not found ──"
    echo ""
    continue
  fi

  if [[ ! -d "$project_root/.agents" ]]; then
    echo "── SKIP: $project_root — no .agents/ directory ──"
    echo ""
    continue
  fi

  display_path="${project_root/#$HOME/~}"
  echo "══════════════════════════════════════════════════════"
  echo "  Project: $display_path"
  echo "══════════════════════════════════════════════════════"
  echo ""

  # Find all MEMORY.md files
  while IFS= read -r -d '' memfile; do
    rel_path="${memfile#$project_root/}"
    echo "  ── $rel_path ──"

    # Read entries (support both § delimited and ## timestamp sections)
    python3 - "$memfile" "$PROCEDURAL_SIGNALS" "$DECLARATIVE_SIGNALS" <<'PYEOF'
import sys
import re

memfile = sys.argv[1]
proc_signals = sys.argv[2].split('|')
decl_signals = sys.argv[3].split('|')

with open(memfile) as f:
    content = f.read()

# Extract entries — try § delimiters first, then timestamp sections, then lines
entries = []

if '§' in content:
    # §-delimited entries
    parts = content.split('§')
    for part in parts[1:]:  # Skip preamble
        entry = part.strip()
        if entry:
            entries.append(entry)
else:
    # Try timestamp-headed sections (## YYYY-MM-DD)
    # Extract bullet entries under timestamp headings
    lines = content.split('\n')
    in_content = False
    for line in lines:
        stripped = line.strip()
        # Skip header, comments, empty lines
        if stripped.startswith('#') and not stripped.startswith('## 20'):
            continue
        if stripped.startswith('<!--') or stripped.startswith('-->'):
            continue
        if stripped.startswith('## 20'):
            in_content = True
            continue
        if in_content and stripped.startswith('- '):
            entries.append(stripped[2:].strip())

if not entries:
    print("    (no entries found)")
    print()
    sys.exit(0)

for entry in entries:
    entry_lower = entry.lower()

    # Count signal matches
    proc_score = sum(1 for s in proc_signals if s.strip() and s.strip().lower() in entry_lower)
    decl_score = sum(1 for s in decl_signals if s.strip() and s.strip().lower() in entry_lower)

    # Classify
    if proc_score > decl_score:
        classification = "PROCEDURAL"
        icon = "🔧"
    elif decl_score > proc_score:
        classification = "DECLARATIVE"
        icon = "📘"
    else:
        classification = "AMBIGUOUS"
        icon = "❓"

    # Check for system-specific signals
    sys_signals = ['this machine', 'this system', 'this host', 'on this']
    is_sys_specific = any(s in entry_lower for s in sys_signals)
    if is_sys_specific:
        classification += " (system-specific)"
        icon = "🖥️"

    # Check for single-command (too atomic)
    is_atomic = len(entry.split()) < 8 and not any(w in entry_lower for w in ['then', 'after', 'before', 'first', 'next', 'step'])

    # Truncate for display
    display = entry[:100] + ('...' if len(entry) > 100 else '')
    print(f"    {icon} [{classification}] {display}")
    if is_atomic and classification.startswith('PROCEDURAL'):
        print(f"       ⚠️  Possibly too atomic for a skill")

print()
PYEOF

  done < <(find "$project_root/.agents" -name 'MEMORY.md' -print0 2>/dev/null)

  echo ""
done

echo "═══════════════════════════════════════════════════════════════"
echo "  Classification Legend:"
echo "    🔧 PROCEDURAL  — Candidate for skill-harvest"
echo "    📘 DECLARATIVE — Route to okf-bundle-harvest"
echo "    ❓ AMBIGUOUS   — Agent decides based on context"
echo "    🖥️  SYSTEM-SPECIFIC — Usually keep as memory"
echo "    ⚠️  Too atomic  — Probably too simple for a skill"
echo "═══════════════════════════════════════════════════════════════"
