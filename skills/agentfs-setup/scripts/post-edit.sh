#!/usr/bin/env bash
# post-edit.sh — Mechanical post-edit checks for AgentFS files.
#
# Run after editing any file under .agents/ (either scope).
# Handles the fragile/deterministic steps; agent handles contextual
# steps (log entries, CHANGELOG entries) separately.
#
# Usage: bash post-edit.sh [--user] [--project] [--all]
#   --user     Check USER scope (~/.agents/) only
#   --project  Check PROJECT scope (./.agents/) only
#   --all      Check both scopes (default)
#
# What it does:
#   1. Regenerate skills/index.md (if skills exist in scope)
#   2. Validate log.md comment-line anchors
#   3. Report results
#
# Exit codes:
#   0 = all checks passed
#   1 = issues found (reported on stdout)

set -euo pipefail

# ── Parse args ─────────────────────────────────────────────────────
CHECK_USER=false
CHECK_PROJECT=false

case "${1:-}" in
  --user)    CHECK_USER=true ;;
  --project) CHECK_PROJECT=true ;;
  --all|'')  CHECK_USER=true; CHECK_PROJECT=true ;;
  *) echo "Usage: bash post-edit.sh [--user] [--project] [--all]"; exit 1 ;;
esac

ISSUES=0
ACTIONS=0

info()  { echo "  ✅ $*"; }
warn()  { echo "  ⚠️  $*"; ISSUES=$((ISSUES + 1)); }
action() { echo "  🔧 $*"; ACTIONS=$((ACTIONS + 1)); }

# ── Skills index regeneration ──────────────────────────────────────
# Implements skill-index logic: scan for SKILL.md, extract metadata,
# generate index.md sorted by reverse chronological order.
regen_skills_index() {
  local skills_root="$1"
  local scope_label="$2"

  if [[ ! -d "$skills_root" ]]; then
    return
  fi

  # Count skills
  local skill_count=0
  for d in "$skills_root"/*/; do
    [[ -f "${d}SKILL.md" ]] && skill_count=$((skill_count + 1))
  done

  if [[ $skill_count -eq 0 ]]; then
    return
  fi

  echo "[$scope_label] Regenerating skills/index.md ($skill_count skills)..."

  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  python3 "${SCRIPT_DIR}/regen-skill-index.py" "$skills_root"

  local rc=$?
  if [[ $rc -ne 0 ]]; then
    ISSUES=$((ISSUES + 1))
  fi
}

# ── Knowledge index audit ──────────────────────────────────────────
audit_knowledge_index() {
  local knowledge_root="$1"
  local scope_label="$2"

  if [[ ! -d "$knowledge_root" ]]; then
    return
  fi

  # Count bundles (directories with index.md)
  local bundle_count=0
  for d in "$knowledge_root"/*/; do
    [[ -f "${d}index.md" ]] && bundle_count=$((bundle_count + 1))
  done

  if [[ $bundle_count -eq 0 ]]; then
    return
  fi

  # Check if audit-index.sh exists
  local audit_script
  audit_script="${HOME}/.agents/skills/okf-bundle-index/scripts/audit-index.sh"
  if [[ ! -f "$audit_script" ]]; then
    info "[$scope_label/knowledge] Skipping audit (okf-bundle-index skill not installed)"
    return
  fi

  echo "[$scope_label] Auditing knowledge index ($bundle_count bundles)..."

  local audit_output
  audit_output="$(bash "$audit_script" "$knowledge_root" 2>&1)"

  local broken missing
  broken="$(echo "$audit_output" | grep -c '^[^(]' | grep -A999 'BROKEN LINKS' | grep -v 'BROKEN LINKS\|(none)' || true)"
  missing="$(echo "$audit_output" | grep '^CONCEPT\|^SUB-BUNDLE' || true)"

  if [[ -n "$missing" ]]; then
    warn "[$scope_label/knowledge] Missing index entries found — run: load_skill(name: \"okf-bundle-index\")"
    echo "$missing" | head -5 | sed 's/^/    /'
  else
    info "[$scope_label/knowledge] All bundles indexed ($bundle_count bundles)"
  fi
}

# ── Log.md comment-line validation ─────────────────────────────────
check_log_anchor() {
  local log_file="$1"
  local scope_label="$2"

  if [[ ! -f "$log_file" ]]; then
    return
  fi

  # Check for comment line
  if ! head -3 "$log_file" | grep -q '<!-- Append-only'; then
    warn "[$scope_label] $log_file missing comment-line anchor"
  else
    info "[$scope_label] $log_file has comment-line anchor"
  fi
}

# ── Main ───────────────────────────────────────────────────────────
echo "=== AgentFS Post-Edit Check ==="
echo

if $CHECK_USER; then
  USER_ROOT="${HOME}/.agents"
  if [[ -d "$USER_ROOT" ]]; then
    echo "[USER] Checking ~/.agents/"
    regen_skills_index "$USER_ROOT/skills" "USER"
    audit_knowledge_index "$USER_ROOT/knowledge" "USER"
    # Conditional KGM reindex (only when KGM extension is enabled)
    KGM_REINDEX="$USER_ROOT/skills/goose-kgm/scripts/reindex-kgm.sh"
    if [[ -f "$KGM_REINDEX" ]]; then
      bash "$KGM_REINDEX" --check-enabled 2>/dev/null || true
    fi
    check_log_anchor "$USER_ROOT/log.md" "USER"
    check_log_anchor "$USER_ROOT/knowledge/log.md" "USER/knowledge"
    echo
  fi
fi

if $CHECK_PROJECT; then
  PROJECT_ROOT="./.agents"
  if [[ -d "$PROJECT_ROOT" ]]; then
    echo "[PROJECT] Checking ./.agents/"
    regen_skills_index "$PROJECT_ROOT/skills" "PROJECT"
    check_log_anchor "./.agents/log.md" "PROJECT"
    echo
  fi
fi

# ── Summary ────────────────────────────────────────────────────────
echo "=== Summary ==="
if [[ $ISSUES -eq 0 ]]; then
  echo "  ✅ All checks passed."
else
  echo "  ⚠️  $ISSUES issue(s) found."
fi
echo
echo "Reminder: If you modified a skill, run:"
echo "  bash ~/.agents/skills/agentfs-setup/scripts/merge-changelog-entry.sh <skill-path>/CHANGELOG.md <version> \"<description>\""
echo "  bash ~/.agents/skills/agentfs-setup/scripts/merge-log-entry.sh <scope-log.md> \"- <entry>\""

exit $( [[ $ISSUES -eq 0 ]] && echo 0 || echo 1 )
