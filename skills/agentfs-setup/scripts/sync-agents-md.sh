#!/usr/bin/env bash
# sync-agents-md.sh — Sync an existing AGENTS.md to the latest template.
#
# Usage:
#   bash sync-agents-md.sh [PROJECT_DIR]
#
# Arguments:
#   PROJECT_DIR  Path to the project root containing AGENTS.md
#                Defaults to current working directory.
#
# Behaviour:
#   1. Reads existing AGENTS.md and detects scope (project or lite)
#   2. Extracts project-owned sections (PROJECT scope only):
#      - Agent Profiles table rows (excluding 'default' — owned by template)
#      - SPECKIT block content
#   3. Checks current template version vs installed version
#   4. If versions match, reports 'already up to date' and exits
#      (the compliance staleness check still runs on this path)
#   5. Regenerates AGENTS.md from current template via seed-agents-md.sh
#      with the detected scope (preserves scope across sync)
#   6. Re-injects preserved project-owned rows using awk (idempotent)
#   7. Reports what changed
#   8. Checks SOUL.md — emits SOUL_ACTION_REQUIRED signal if missing or stub
#
# Scope detection:
#   Reads `agentfs-scope:` metadata from AGENTS.md line 1. Defaults to
#   'project' when absent (backward-compatible with pre-4.19.0 files).
#   Sync NEVER switches scope — it preserves whatever scope the project
#   was created with. To change scope, re-seed explicitly.
#
# Agent signal:
#   When output contains 'SOUL_ACTION_REQUIRED path=<path>', the agent MUST
#   NOT show a raw bash command. Instead, the agent guides the user through
#   a conversational choice: apply default Agentic SRE / customise / skip.
#
# Idempotency:
#   Running twice produces identical output. The default row is never
#   duplicated because it is excluded from preserved rows (template owns it).
#   Profile row re-injection uses awk deduplication by agent name.
#
# Exit codes:
#   0 = success (synced or already up to date)
#   1 = error

set -euo pipefail

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
else
  trace_step() { echo "[trace] $*" >&2; }
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")"; pwd)"
SEED_SCRIPT="$SCRIPT_DIR/seed-agents-md.sh"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"

# Reject option-like or extra arguments. Previously any $1 was taken as
# PROJECT_DIR, so e.g. '--dry-run' became a path with no AGENTS.md and
# triggered initial setup (seed-agents-md.sh) on it. This script has no
# dry-run mode.
if [[ $# -gt 1 ]]; then
  echo "[sync-agents-md] ERROR: too many arguments (usage: sync-agents-md.sh [PROJECT_DIR])" >&2
  exit 2
fi
case "${1:-}" in
  -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  -*) echo "[sync-agents-md] ERROR: unknown option '$1' (this script has no options; usage: sync-agents-md.sh [PROJECT_DIR])" >&2; exit 2 ;;
esac
PROJECT_DIR="${1:-$(pwd)}"
AGENTS="$PROJECT_DIR/AGENTS.md"

# ── Compliance profile staleness check ────────────────────────────
# Runs on EVERY exit path (initial seed, already-up-to-date, synced):
# before F6 (2026-11-17) it ran only after a real sync, so the warning
# fired once and was never repeated while the profile stayed stale.
compliance_staleness_check() {
  # TEMPLATE_VERSION is unset on the initial-seed path (set -u safe).
  local COMPLIANCE_PROFILE RULES_HASH_SH PROFILE_VERSION PROFILE_HASH CURRENT_HASH
  local TV="${TEMPLATE_VERSION:-$(grep -oP 'version:\s*"\K[^"]+' "$SKILL_FILE" 2>/dev/null | head -1 || echo unknown)}"
  COMPLIANCE_PROFILE="${HOME}/.agents/skills/agentfs-setup/compliance-profile.yaml"
  RULES_HASH_SH="${HOME}/.agents/scripts/rules-hash.sh"
  if [[ -f "$COMPLIANCE_PROFILE" ]]; then
    # '|| true': pre-1.1 profiles have no rules-hash line; grep exits 1
    # on no match and 'set -e' would abort the sync at its last step.
    PROFILE_VERSION=$(grep -m1 '^agents_md_version:' "$COMPLIANCE_PROFILE" | awk '{print $2}' | tr -d '"' || true)
    PROFILE_HASH=$(grep -m1 '^agents_md_rules_hash:' "$COMPLIANCE_PROFILE" | awk '{print $2}' | tr -d '"' || true)
    CURRENT_HASH=""
    [[ -f "$RULES_HASH_SH" ]] && CURRENT_HASH=$(bash "$RULES_HASH_SH" "$AGENTS" 2>/dev/null || echo "")

    # Staleness is a property of the RULES, not the version string. The
    # template version tracks agentfs-setup's frontmatter, so it moves
    # for changes that never touch AGENTS.md. Warn only when the rules
    # the profile was measured against actually differ.
    if [[ -n "$PROFILE_HASH" && -n "$CURRENT_HASH" ]]; then
      if [[ "$PROFILE_HASH" != "$CURRENT_HASH" ]]; then
        echo ""
        echo "[sync-agents-md] ⚠️  Compliance profile is STALE — rules changed"
        echo "[sync-agents-md]    Profile: ${PROFILE_HASH} (v${PROFILE_VERSION})"
        echo "[sync-agents-md]    Current: ${CURRENT_HASH} (v${TV})"
        echo "[sync-agents-md]    Re-record all tiers (from a project repo, ~12-16 min):"
        echo "[sync-agents-md]      bash ~/.agents/scripts/run-parallel.sh real"
        echo "[sync-agents-md]    Status: bash ~/.agents/scripts/update-compliance.sh --check"
      fi
    elif [[ "$PROFILE_VERSION" != "$TV" ]]; then
      # Pre-1.1 profile, or AGENTS.md unreadable — fall back to versions.
      echo ""
      echo "[sync-agents-md] ⚠️  Compliance profile may be STALE (v${PROFILE_VERSION} ≠ v${TV})"
      echo "[sync-agents-md]    No rules hash available — cannot tell if rules changed."
      echo "[sync-agents-md]    Run: bash ~/.agents/scripts/update-compliance.sh --check"
    fi
  fi
}

if [[ ! -f "$SEED_SCRIPT" ]]; then
  echo "[sync-agents-md] ERROR: seed-agents-md.sh not found at $SEED_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$AGENTS" ]]; then
  echo "[sync-agents-md] No AGENTS.md found at $AGENTS — running initial setup instead."
  bash "$SEED_SCRIPT" "$PROJECT_DIR"
  compliance_staleness_check
  exit 0
fi

# ── Scope detection ───────────────────────────────────────────────
AGENTFS_SCOPE=$(grep -oP 'agentfs-scope: \K\w+' "$AGENTS" 2>/dev/null || echo "project")
echo "[sync-agents-md] Detected scope: $AGENTFS_SCOPE"

# ── Version check ─────────────────────────────────────────────────
CURRENT_VERSION=$(grep -oP 'agentfs-template-version: \K[^\s]+' "$AGENTS" 2>/dev/null || echo "unknown")
TEMPLATE_VERSION=$(grep -oP 'version:\s*"\K[^"]+' "$SKILL_FILE" 2>/dev/null | head -1 || echo "unknown")

if [[ "$CURRENT_VERSION" == "unknown" ]]; then
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
  echo "[sync-agents-md] No version stamp found — treating as pre-versioning, syncing unconditionally."
elif [[ "$CURRENT_VERSION" == "$TEMPLATE_VERSION" ]]; then
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
  echo "[sync-agents-md] Already up to date (v$TEMPLATE_VERSION). No changes needed."
  # Still sync SOUL.md even when AGENTS.md is current
  SOUL_PATH="$PROJECT_DIR/.agents/SOUL.md"
  SEED_SOUL_EARLY="$SCRIPT_DIR/seed-soul.sh"
  if [[ -f "$SEED_SOUL_EARLY" ]]; then
    if [[ ! -f "$SOUL_PATH" ]]; then
      echo ""
      echo "[sync-agents-md] ⚠️  SOUL.md missing — seeding with v6 template."
      bash "$SEED_SOUL_EARLY" "$SOUL_PATH"
      echo "[sync-agents-md] SOUL_ACTION_REQUIRED path=$SOUL_PATH"
      echo ""
    elif bash "$SEED_SOUL_EARLY" "$SOUL_PATH" --format-only >/dev/null 2>&1; then
      bash "$SEED_SOUL_EARLY" "$SOUL_PATH"
    else
      echo ""
      bash "$SEED_SOUL_EARLY" "$SOUL_PATH"
      echo ""
    fi
  fi
  # The USER README drifts on a template bump even when this project's
  # AGENTS.md is already current, so it must run on this early exit too.
  README_SYNC="${HOME}/.agents/scripts/sync-readme-version.sh"
  [[ -f "$README_SYNC" ]] && bash "$README_SYNC" || true
  compliance_staleness_check
  exit 0
else
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
fi

# ── Extract project-owned sections (PROJECT scope only) ───────────
PROFILE_ROWS=""
SPECKIT_CONTENT=""

if [[ "$AGENTFS_SCOPE" == "project" ]]; then
  # Profile rows: exclude header, separator, and 'default' row (template owns it)
  PROFILE_ROWS=$(awk '
    /^## Agent Profiles/ { found=1; next }
    found && /^\|/ { print }
    found && /^[^|]/ { exit }
  ' "$AGENTS" | grep -v '^| Agent ' | grep -v '^|---' | grep -v '^| default |' || true)

  # SPECKIT block (content between markers, exclusive)
  SPECKIT_CONTENT=$(awk '/<!-- SPECKIT START -->/,/<!-- SPECKIT END -->/{print}' "$AGENTS" || true)
fi

# ── Regenerate from template ───────────────────────────────────────
echo "[sync-agents-md] Regenerating from template v$TEMPLATE_VERSION (scope: $AGENTFS_SCOPE)..."
rm -f "$AGENTS"
bash "$SEED_SCRIPT" --scope "$AGENTFS_SCOPE" "$PROJECT_DIR"

# ── Re-inject profile rows (PROJECT scope only, idempotent) ───────
if [[ "$AGENTFS_SCOPE" == "project" && -n "$PROFILE_ROWS" ]]; then
  echo "[sync-agents-md] Re-injecting $(echo "$PROFILE_ROWS" | grep -c '^|') profile row(s)..."

  ROWS_TO_INJECT="$PROFILE_ROWS"

  awk -v rows="$ROWS_TO_INJECT" '
    BEGIN {
      n = split(rows, rowarray, "\n")
      for (i = 1; i <= n; i++) {
        if (rowarray[i] ~ /^\|/) {
          r = rowarray[i]
          gsub(/^\| */, "", r)
          split(r, parts, " *\\| *")
          pending[parts[1]] = rowarray[i]
        }
      }
    }
    /^\|/ && !/^\| Agent / && !/^\|---/ {
      r = $0
      gsub(/^\| */, "", r)
      split(r, parts, " *\\| *")
      seen[parts[1]] = 1
    }
    /^\| default \|/ {
      print
      for (agent in pending) {
        if (!(agent in seen)) {
          print pending[agent]
          seen[agent] = 1
        }
      }
      next
    }
    { print }
  ' "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS"
fi

# ── Re-inject SPECKIT block content (PROJECT scope only) ──────────
if [[ "$AGENTFS_SCOPE" == "project" ]]; then
  SPECKIT_INNER=$(echo "$SPECKIT_CONTENT" | grep -v '<!-- SPECKIT' || true)
  if [[ -n "$(echo "$SPECKIT_INNER" | tr -d '[:space:]')" ]]; then
    echo "[sync-agents-md] Re-injecting SPECKIT content..."
    awk -v content="$SPECKIT_CONTENT" '
      /<!-- SPECKIT START -->/ { print content; skip=1; next }
      /<!-- SPECKIT END -->/ { skip=0; next }
      !skip { print }
    ' "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS"
  fi
fi

# ── SOUL.md sync ──────────────────────────────────────────────────
SOUL_PATH="$PROJECT_DIR/.agents/SOUL.md"
SEED_SOUL="$SCRIPT_DIR/seed-soul.sh"

if [[ ! -f "$SEED_SOUL" ]]; then
  echo "[sync-agents-md] ⚠️  seed-soul.sh not found — skipping SOUL.md sync."
elif [[ ! -f "$SOUL_PATH" ]]; then
  echo ""
  echo "[sync-agents-md] ⚠️  SOUL.md missing — seeding with v6 template."
  bash "$SEED_SOUL" "$SOUL_PATH"
  echo "[sync-agents-md] SOUL_ACTION_REQUIRED path=$SOUL_PATH"
  echo ""
else
  # Check format and sync
  if bash "$SEED_SOUL" "$SOUL_PATH" --format-only >/dev/null 2>&1; then
    # Already v6 format — sync template section
    bash "$SEED_SOUL" "$SOUL_PATH"
  else
    # Old format or stub — migrate
    echo ""
    bash "$SEED_SOUL" "$SOUL_PATH"
    echo ""
  fi
fi

echo "[sync-agents-md] ✅ Synced $AGENTS (v$CURRENT_VERSION → v$TEMPLATE_VERSION, scope: $AGENTFS_SCOPE)"

# --- Keep the USER README's version references in step ---
# The template version comes from agentfs-setup frontmatter, so every
# bump leaves the README claiming an older version. This drifted three
# releases running before it was mechanised.
README_SYNC="${HOME}/.agents/scripts/sync-readme-version.sh"
if [[ -f "$README_SYNC" ]]; then
  bash "$README_SYNC" || echo "[sync-agents-md] ⚠️  README version sync failed — check ~/.agents/README.md"
fi

compliance_staleness_check
