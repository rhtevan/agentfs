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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")"; pwd)"
SEED_SCRIPT="$SCRIPT_DIR/seed-agents-md.sh"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"

PROJECT_DIR="${1:-$(pwd)}"
AGENTS="$PROJECT_DIR/AGENTS.md"

if [[ ! -f "$SEED_SCRIPT" ]]; then
  echo "[sync-agents-md] ERROR: seed-agents-md.sh not found at $SEED_SCRIPT" >&2
  exit 1
fi

if [[ ! -f "$AGENTS" ]]; then
  echo "[sync-agents-md] No AGENTS.md found at $AGENTS — running initial setup instead."
  bash "$SEED_SCRIPT" "$PROJECT_DIR"
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
