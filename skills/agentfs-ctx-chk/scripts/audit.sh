#!/usr/bin/env bash
# audit.sh — Inventory agent context sources and check for issues
# Usage: audit.sh [--dry-run] [PROJECT_ROOT]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "agentfs-ctx-chk" "1.0.0" 2>/dev/null || true

DRY_RUN=false
PROJECT_ROOT="${1:-.}"

for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
  if [[ "$arg" == "--check" ]]; then echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true; fi
done

# Remove --check from positional if present
[[ "$PROJECT_ROOT" == "--check" ]] && PROJECT_ROOT="."

echo "=== AgentFS Context Audit ==="
echo "Project root: $(cd "$PROJECT_ROOT" && pwd)"
echo ""

TOTAL_LINES=0
TOTAL_FILES=0
ISSUES=0

# ── Step 1: Auto-loaded context sources ─────────────────────────────────
trace_step 1 "autoloaded_sources" 0 "" 2>/dev/null || true

echo "── Auto-loaded Context Sources ──"
echo ""
printf "  %-50s %8s  %s\n" "Source" "Lines" "Status"
printf "  %-50s %8s  %s\n" "------" "-----" "------"

check_file() {
  local label="$1" path="$2"
  local expanded=$(eval echo "$path")
  if [[ -f "$expanded" ]]; then
    local lines=$(wc -l < "$expanded")
    TOTAL_LINES=$((TOTAL_LINES + lines))
    TOTAL_FILES=$((TOTAL_FILES + 1))
    printf "  %-50s %8d  ✓\n" "$label" "$lines"
  else
    printf "  %-50s %8s  ─\n" "$label" "n/a"
  fi
}

check_file "AGENTS.md" "${PROJECT_ROOT}/AGENTS.md"
check_file ".goosehints (project)" "${PROJECT_ROOT}/.goosehints"
check_file ".goosehints (global)" "~/.config/goose/.goosehints"
check_file "instructions.md" "~/.config/goose/instructions.md"
check_file "SOUL.md" "${PROJECT_ROOT}/.agents/SOUL.md"

echo ""

# ── Step 2: Skills inventory ────────────────────────────────────────────
trace_step 2 "skills_inventory" 0 "" 2>/dev/null || true

echo "── Skills Inventory ──"

USER_SKILLS=0
PROJECT_SKILLS=0

if [[ -d "${HOME}/.agents/skills" ]]; then
  USER_SKILLS=$(find "${HOME}/.agents/skills" -maxdepth 1 -type d | tail -n +2 | wc -l)
  echo "  User skills (~/.agents/skills):      $USER_SKILLS"
fi

if [[ -d "${PROJECT_ROOT}/.agents/skills" ]]; then
  PROJECT_SKILLS=$(find "${PROJECT_ROOT}/.agents/skills" -maxdepth 1 -type d | tail -n +2 | wc -l)
  echo "  Project skills (.agents/skills):     $PROJECT_SKILLS"
fi

# Check skill index freshness
if [[ -f "${HOME}/.agents/skills/index.md" ]]; then
  idx_skills=$(grep -c '^\|' "${HOME}/.agents/skills/index.md" 2>/dev/null || echo 0)
  idx_skills=$((idx_skills - 2))  # subtract header rows
  if [[ $idx_skills -ne $USER_SKILLS ]]; then
    echo "  ⚠ Index lists $idx_skills but $USER_SKILLS dirs exist"
    ISSUES=$((ISSUES + 1))
  else
    echo "  ✓ Index matches ($idx_skills skills)"
  fi
fi

echo ""

# ── Step 3: Knowledge inventory ─────────────────────────────────────────
trace_step 3 "knowledge_inventory" 0 "" 2>/dev/null || true

echo "── Knowledge Inventory ──"

if [[ -d "${HOME}/.agents/knowledge" ]]; then
  BUNDLES=$(find "${HOME}/.agents/knowledge" -maxdepth 1 -type d | tail -n +2 | grep -v '^\.' | wc -l)
  echo "  Knowledge bundles: $BUNDLES"
  
  total_concepts=0
  for bd in "${HOME}/.agents/knowledge"/*/; do
    [[ -d "$bd" ]] || continue
    [[ "$(basename "$bd")" == .* ]] && continue
    concepts=$(find "$bd" -name "*.md" -not -name "index.md" -not -name "log.md" | wc -l)
    total_concepts=$((total_concepts + concepts))
  done
  echo "  Total concept files: $total_concepts"
fi

echo ""

# ── Step 4: Memory files ────────────────────────────────────────────────
trace_step 4 "memory_files" 0 "" 2>/dev/null || true

echo "── Memory Files ──"

if [[ -d "${PROJECT_ROOT}/.agents/memories" ]]; then
  for mf in "${PROJECT_ROOT}/.agents/memories"/*.md; do
    [[ -f "$mf" ]] || continue
    lines=$(wc -l < "$mf")
    entries=$(grep -c '^- ' "$mf" 2>/dev/null || echo 0)
    echo "  $(basename "$mf"): ${lines} lines, ~${entries} entries"
    if [[ $entries -gt 20 ]]; then
      echo "    ⚠ Consider graduating to knowledge bundle (>20 entries)"
      ISSUES=$((ISSUES + 1))
    fi
  done
else
  echo "  No project memories directory"
fi

echo ""

# ── Step 5: Extension context ───────────────────────────────────────────
trace_step 5 "extensions" 0 "" 2>/dev/null || true

echo "── Extensions (from config) ──"

CONFIG_YAML="${HOME}/.config/goose/config.yaml"
if [[ -f "$CONFIG_YAML" ]]; then
  # Count enabled extensions
  ext_count=$(grep -c 'enabled: true' "$CONFIG_YAML" 2>/dev/null || echo 0)
  echo "  Enabled extensions: $ext_count"
else
  echo "  Config not found"
fi

echo ""

# ── Step 6: Size summary ────────────────────────────────────────────────
trace_step 6 "size_summary" 0 "" 2>/dev/null || true

echo "── Context Size Summary ──"
echo "  Auto-loaded files: $TOTAL_FILES"
echo "  Auto-loaded lines: $TOTAL_LINES"
echo "  User skills:       $USER_SKILLS"
echo "  Knowledge bundles: ${BUNDLES:-0}"

# Estimate total context tokens (rough: ~4 chars per token, ~40 chars per line)
est_tokens=$((TOTAL_LINES * 10))
echo "  Est. auto-load tokens: ~${est_tokens}"

if [[ $est_tokens -gt 10000 ]]; then
  echo "  ⚠ Auto-loaded context is large (>10k tokens estimated)"
  ISSUES=$((ISSUES + 1))
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────
# Note: audit.sh is a Query (read-only). --dry-run is a no-op but
# supported for consistency. Output signals match the contract.
if $DRY_RUN; then
  echo "DRY_RUN_RESULT=CONVERGED"
  echo "Audit is read-only. No changes to apply."
  exit 0
fi

if [[ $ISSUES -eq 0 ]]; then
  echo "✅ Context audit complete. No issues found."
else
  echo "⚠ Context audit complete. $ISSUES issue(s) found."
fi

trace_end 2>/dev/null || true
exit $ISSUES
