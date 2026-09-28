#!/usr/bin/env bash
# seed-soul.sh — Generate or sync the template-owned portion of SOUL.md.
#
# Usage:
#   bash seed-soul.sh <target-soul.md> [--format-only]
#
# Modes:
#   (default)      Full seed: write template with markers if file is new/stub.
#                  If file exists with project content, merge: regenerate
#                  template section, preserve project section.
#   --format-only  Detect old-format (prose, no markers) SOUL.md and print
#                  migration instructions without modifying the file.
#
# Ownership model:
#   SOUL.md uses the same two-zone pattern as AGENTS.md:
#   - Template-owned: # Agent Identity heading + ## Principles section
#   - Project-owned: everything below <!-- PROJECT-OWNED --> marker
#
# Exit codes:
#   0 = file written or already current
#   2 = old format detected (--format-only mode)

set -euo pipefail

TARGET="${1:-}"
FORMAT_ONLY=false
[[ "${2:-}" == "--format-only" ]] && FORMAT_ONLY=true

if [[ -z "$TARGET" ]]; then
  echo "[seed-soul] ERROR: target path required." >&2
  exit 1
fi

# ── Template content (single source of truth) ─────────────────────────
TEMPLATE_PREAMBLE='# Agent Identity

You are an Agentic SRE — a pragmatic systems reliability engineer
operating autonomously within CI/CD and operational contexts.'

TEMPLATE_PRINCIPLES='## Principles

- **Reliability over cleverness.** Prefer simple, proven solutions.
- **Root cause, not symptom.** Ad-hoc fixes are temporary — trace to
  root cause, implement durable fix (script, guardrail, or config change).
- **Direct communication.** No filler, no hedging. Never open with
  validation phrases ("Great question", "Absolutely", "Of course").
  Lead with substance.
- **Intellectual integrity.** Do not reverse a stated position unless
  given new information or a logical argument. Social pressure is not
  a reason to reverse course.
- **No assumed inputs.** When information is missing, ask before
  proceeding. A confident wrong answer is worse than a clarifying
  question. When uncertain, say so.
- **Proactive risk naming.** Name risks and failure modes even when
  not asked. Push back on bad plans.
- **Scope discipline.** Defer on aesthetic and domain-specific choices
  outside your operational scope.
- **Ledger integrity.** Ledger files (log.md, CHANGELOG.md, MEMORY.md,
  score sheets) are always latest-entry-first. Flag ordering violations,
  duplicate headers, or structural anomalies immediately.
- **Signal dispatch.** When a user message starts with "hey" followed
  by keywords, treat it as a skill/knowledge dispatch command — never
  as a greeting. Always follow the dispatch rule in AGENTS.md.'

PROJECT_MARKER='<!-- PROJECT-OWNED: custom identity below is preserved across sync -->'

# ── Detection helpers ─────────────────────────────────────────────────
has_markers() {
  grep -q 'PROJECT-OWNED' "$1" 2>/dev/null
}

has_principles() {
  grep -q '^## Principles' "$1" 2>/dev/null
}

is_stub() {
  local non_comment_lines
  non_comment_lines=$(awk '
    /<!--/ { in_comment=1 }
    /-->/ { in_comment=0; next }
    in_comment { next }
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    { print }
  ' "$1" | wc -l)
  [[ "$non_comment_lines" -eq 0 ]]
}

# ── Write full template with markers ──────────────────────────────────
write_template() {
  local project_section="${1:-}"
  {
    echo "$TEMPLATE_PREAMBLE"
    echo ""
    echo "$TEMPLATE_PRINCIPLES"
    echo ""
    echo "$PROJECT_MARKER"
    if [[ -n "$project_section" ]]; then
      echo ""
      echo "$project_section"
    fi
  } > "$TARGET"
}

# ── Extract project-owned section from existing file ──────────────────
extract_project_section() {
  # Everything after the PROJECT-OWNED marker line
  sed -n '/PROJECT-OWNED/,$ { /PROJECT-OWNED/d; p; }' "$1"
}

# ── Main ──────────────────────────────────────────────────────────────

# Case 1: File doesn't exist or is a stub — write fresh template
if [[ ! -f "$TARGET" ]] || is_stub "$TARGET"; then
  if [[ "$FORMAT_ONLY" == true ]]; then
    echo "[seed-soul] File missing or stub — needs full seed."
    exit 2
  fi
  write_template
  echo "[seed-soul] ✓ SOUL.md written with v6 template format."
  exit 0
fi

# Case 2: File exists with markers — sync template section, preserve project
if has_markers "$TARGET"; then
  if [[ "$FORMAT_ONLY" == true ]]; then
    echo "[seed-soul] Already in v6 format with markers."
    exit 0
  fi
  PROJECT_CONTENT=$(extract_project_section "$TARGET")
  write_template "$PROJECT_CONTENT"
  echo "[seed-soul] ✓ SOUL.md synced — template updated, project content preserved."
  exit 0
fi

# Case 3: File exists, no markers (old format) — needs migration
if [[ "$FORMAT_ONLY" == true ]]; then
  echo "[seed-soul] ⚠️  Old-format SOUL.md detected (no ownership markers)."
  echo "[seed-soul] SOUL_FORMAT_UPGRADE path=$TARGET"
  exit 2
fi

# Migrate: filter out template-covered content, keep only custom lines
# These fingerprint phrases identify lines already covered by v6 Principles.
# Each phrase is a unique substring from the old default prose SOUL.md.
TEMPLATE_FINGERPRINTS=(
  # Old prose format — primary lines
  "# Agent Identity"
  "You are an Agentic SRE"
  "operating autonomously within CI/CD"
  "You value reliability, observability"
  "You prefer simple, proven solutions"
  "the root cause, not the symptom"
  "You communicate directly and concisely"
  "No filler, no hedging"
  "You do not change a stated position"
  "Social pressure is not a reason"
  "You name risks and failure modes"
  "You push back on bad plans"
  "You defer on aesthetic and domain-specific"
  "choices outside your operational scope"
  "Never open a response with validation phrases"
  "Great question"
  "Lead with substance"
  "You never act on assumed inputs"
  "information required to complete"
  "a task is missing, you ask for it"
  "A wrong answer delivered confidently"
  "delivered confidently is worse than"
  "a clarifying question"
  "When uncertain, say so"
  "uncertain, say so"
  "Ad-hoc fixes are temporary"
  "a durable fix (script, guardrail, or config change)"
  "Ledger files (log.md, CHANGELOG.md, MEMORY.md"
  "latest-entry-first"
  "do not silently continue past corrupt data"
  "any ordering violations, duplicate headers"
  "structural anomalies"
  "immediately — do not silently"
  # v6 Principles format — bullet labels
  "## Principles"
  "Reliability over cleverness"
  "Root cause, not symptom"
  "Direct communication"
  "Intellectual integrity"
  "No assumed inputs"
  "Proactive risk naming"
  "Scope discipline"
  "Ledger integrity"
  "Signal dispatch"
  # author-soul.sh generated phrases
  "You push back on:"
  "You defer on:"
  "Constraints:"
)

# Build a grep pattern file for filtering
PATTERN_FILE=$(mktemp)
for fp in "${TEMPLATE_FINGERPRINTS[@]}"; do
  echo "$fp" >> "$PATTERN_FILE"
done

# Filter: remove lines matching any fingerprint, then trim empty lines
CUSTOM_CONTENT=$(grep -vFf "$PATTERN_FILE" "$TARGET" | \
  sed '/^[[:space:]]*$/{ N; /^\n[[:space:]]*$/d; }' | \
  sed -e '/^[[:space:]]*$/{ N; s/^\n$//; }' | \
  sed -e 's/^[[:space:]]*$//' | \
  cat -s | \
  sed -e '/./,$!d' -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }')
rm -f "$PATTERN_FILE"

if [[ -z "$CUSTOM_CONTENT" ]]; then
  write_template
  echo "[seed-soul] ✓ SOUL.md migrated to v6 format."
  echo "  No project-specific content detected — clean migration."
else
  write_template "$CUSTOM_CONTENT"
  echo "[seed-soul] ✓ SOUL.md migrated to v6 format."
  echo "  Template Principles added. Custom content preserved:"
  echo "$CUSTOM_CONTENT" | sed 's/^/    /'
fi
