#!/usr/bin/env bash
# post-edit.sh — Post-edit checks and audit trail verification for AgentFS.
#
# Run after editing any file under .agents/ (either scope).
# Handles structural integrity (indexes, anchors) AND detects
# unlogged modifications (log drift) to catch missed Rule 13
# obligations.
#
# Usage: bash post-edit.sh [--user] [--project] [--all]
#   --user     Check USER scope (~/.agents/) only
#   --project  Check PROJECT scope (./.agents/) only
#   --all      Check both scopes (default)
#
# What it does:
#   1. Regenerate skills/index.md (if skills exist in scope)
#   2. Validate log.md comment-line anchors
#   3. Detect unlogged skill modifications (log drift)
#   4. Report results
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

# ── Knowledge index regen + audit ──────────────────────────────────
# Parallel to regen_skills_index: regenerate the top-level knowledge
# index.md using rebuild-index.sh (reverse-chronological by mtime),
# then audit for missing/broken entries.
regen_knowledge_index() {
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

  # Regenerate index.md if rebuild-index.sh exists
  local rebuild_script
  rebuild_script="${HOME}/.agents/skills/okf-bundle-index/scripts/rebuild-index.sh"
  if [[ -f "$rebuild_script" ]]; then
    echo "[$scope_label] Regenerating knowledge/index.md ($bundle_count bundles)..."
    local new_index
    new_index="$(bash "$rebuild_script" "$knowledge_root" "Knowledge" 2>/dev/null)"
    if [[ -n "$new_index" ]]; then
      echo "$new_index" > "$knowledge_root/index.md"
    fi
  fi

  # Audit for missing/broken entries
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

# ── Log drift detection ────────────────────────────────────────────
# Compares latest file modification time in each skill directory
# against the latest log entry timestamp. Warns if a skill has files
# newer than the last log entry, indicating a missed post-write.sh call.
check_log_drift() {
  local skills_root="$1"
  local log_file="$2"
  local scope_label="$3"

  if [[ ! -d "$skills_root" ]] || [[ ! -f "$log_file" ]]; then
    return
  fi

  # Extract the latest log timestamp as epoch seconds
  # Log format: ## YYYY-MM-DD HH:MM
  local latest_log_ts=0
  local latest_log_line
  latest_log_line="$(grep -m1 '^## [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}' "$log_file" || true)"
  if [[ -n "$latest_log_line" ]]; then
    local log_datetime
    log_datetime="$(echo "$latest_log_line" | sed 's/^## //')"
    latest_log_ts="$(date -d "$log_datetime" '+%s' 2>/dev/null || echo 0)"
  fi

  if [[ "$latest_log_ts" -eq 0 ]]; then
    return  # Can't parse log timestamps — skip drift check
  fi

  # Check each skill directory
  for skill_dir in "$skills_root"/*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue

    local skill_name
    skill_name="$(basename "$skill_dir")"

    # Find the latest modification time across all files in the skill
    local latest_file_ts=0
    local latest_file=""
    while IFS= read -r line; do
      local file_ts file_path
      # %T@ gives fractional epoch — truncate to integer
      file_ts="$(echo "$line" | cut -d'.' -f1)"
      file_path="$(echo "$line" | sed 's/^[^ ]* //')"
      if [[ "$file_ts" -gt "$latest_file_ts" ]]; then
        latest_file_ts="$file_ts"
        latest_file="$file_path"
      fi
    done < <(find "$skill_dir" -type f ! -name 'index.md' -printf '%T@ %p\n' 2>/dev/null)

    if [[ "$latest_file_ts" -eq 0 ]]; then
      continue
    fi

    # Allow 120-second grace period (log entry may be written slightly
    # before the last file touch during the same post-write cycle)
    local drift_threshold=$((latest_log_ts + 120))

    if [[ "$latest_file_ts" -gt "$drift_threshold" ]]; then
      local file_time log_time
      file_time="$(date -d "@$latest_file_ts" '+%Y-%m-%d %H:%M:%S')"
      log_time="$(date -d "@$latest_log_ts" '+%Y-%m-%d %H:%M')"
      warn "[$scope_label] Log drift: $skill_name/ has file modified at $file_time but latest log entry is $log_time"
      echo "    File: $(basename "$latest_file")"
    fi
  done
}

# ── Main ───────────────────────────────────────────────────────────
echo "=== AgentFS Post-Edit Check ==="
echo

if $CHECK_USER; then
  USER_ROOT="${HOME}/.agents"
  if [[ -d "$USER_ROOT" ]]; then
    echo "[USER] Checking ~/.agents/"
    regen_skills_index "$USER_ROOT/skills" "USER"
    regen_knowledge_index "$USER_ROOT/knowledge" "USER"
    # Conditional KGM reindex (only when KGM extension is enabled)
    KGM_REINDEX="$USER_ROOT/skills/goose-kgm/scripts/reindex-kgm.sh"
    if [[ -f "$KGM_REINDEX" ]]; then
      bash "$KGM_REINDEX" --check-enabled 2>/dev/null || true
    fi
    check_log_anchor "$USER_ROOT/log.md" "USER"
    check_log_anchor "$USER_ROOT/knowledge/log.md" "USER/knowledge"
    check_log_drift "$USER_ROOT/skills" "$USER_ROOT/log.md" "USER"
    echo
  fi
fi

if $CHECK_PROJECT; then
  PROJECT_ROOT="./.agents"
  if [[ -d "$PROJECT_ROOT" ]]; then
    echo "[PROJECT] Checking ./.agents/"
    regen_skills_index "$PROJECT_ROOT/skills" "PROJECT"
    check_log_anchor "./.agents/log.md" "PROJECT"
    check_log_drift "$PROJECT_ROOT/skills" "./.agents/log.md" "PROJECT"
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
