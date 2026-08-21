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
#   1. Reads existing AGENTS.md and extracts project-owned sections:
#      - Agent Profiles table rows (excluding 'default' — owned by template)
#      - SPECKIT block content
#   2. Checks current template version vs installed version
#   3. If versions match, reports 'already up to date' and exits
#   4. Regenerates AGENTS.md from current template via seed-agents-md.sh
#   5. Re-injects preserved project-owned rows using awk (idempotent)
#   6. Reports what changed
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

# ── Version check ─────────────────────────────────────────────────
CURRENT_VERSION=$(grep -oP 'agentfs-template-version: \K[^\s]+' "$AGENTS" 2>/dev/null || echo "unknown")
TEMPLATE_VERSION=$(grep -oP 'version:\s*"\K[^"]+' "$SKILL_FILE" 2>/dev/null | head -1 || echo "unknown")

if [[ "$CURRENT_VERSION" == "unknown" ]]; then
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
  echo "[sync-agents-md] No version stamp found — treating as pre-versioning, syncing unconditionally."
elif [[ "$CURRENT_VERSION" == "$TEMPLATE_VERSION" ]]; then
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
  echo "[sync-agents-md] Already up to date (v$TEMPLATE_VERSION). No changes needed."
  exit 0
else
  echo "[sync-agents-md] Current: v$CURRENT_VERSION → Template: v$TEMPLATE_VERSION"
fi

# ── Extract project-owned sections ────────────────────────────────
# Profile rows: exclude header, separator, and 'default' row (template owns it)
PROFILE_ROWS=$(awk '
  /^## Agent Profiles/ { found=1; next }
  found && /^\|/ { print }
  found && /^[^|]/ { exit }
' "$AGENTS" | grep -v '^| Agent ' | grep -v '^|---' | grep -v '^| default |' || true)

# SPECKIT block (content between markers, exclusive)
SPECKIT_CONTENT=$(awk '/<!-- SPECKIT START -->/,/<!-- SPECKIT END -->/{print}' "$AGENTS" || true)

# ── Regenerate from template ───────────────────────────────────────
echo "[sync-agents-md] Regenerating from template v$TEMPLATE_VERSION..."
rm -f "$AGENTS"
bash "$SEED_SCRIPT" "$PROJECT_DIR"

# ── Re-inject profile rows (idempotent, awk-based) ────────────────
if [[ -n "$PROFILE_ROWS" ]]; then
  echo "[sync-agents-md] Re-injecting $(echo "$PROFILE_ROWS" | grep -c '^|') profile row(s)..."

  # Build a map of agent names already in the file (to dedup)
  # Then insert missing rows after the default row using awk
  ROWS_TO_INJECT="$PROFILE_ROWS"

  awk -v rows="$ROWS_TO_INJECT" '
    BEGIN {
      # Parse rows into array keyed by agent name
      n = split(rows, rowarray, "\n")
      for (i = 1; i <= n; i++) {
        if (rowarray[i] ~ /^\|/) {
          # Extract agent name (second field)
          r = rowarray[i]
          gsub(/^\| */, "", r)
          split(r, parts, " *\\| *")
          pending[parts[1]] = rowarray[i]
        }
      }
    }
    # Track agent names already written
    /^\|/ && !/^\| Agent / && !/^\|---/ {
      r = $0
      gsub(/^\| */, "", r)
      split(r, parts, " *\\| *")
      seen[parts[1]] = 1
    }
    # After the default row, inject any pending rows not yet seen
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

# ── Re-inject SPECKIT block content ───────────────────────────────
# The template already creates empty SPECKIT markers.
# Only re-inject if original had non-empty content.
SPECKIT_INNER=$(echo "$SPECKIT_CONTENT" | grep -v '<!-- SPECKIT' || true)
if [[ -n "$(echo "$SPECKIT_INNER" | tr -d '[:space:]')" ]]; then
  echo "[sync-agents-md] Re-injecting SPECKIT content..."
  # Replace empty SPECKIT block with preserved content
  awk -v content="$SPECKIT_CONTENT" '
    /<!-- SPECKIT START -->/ { print content; skip=1; next }
    /<!-- SPECKIT END -->/ { skip=0; next }
    !skip { print }
  ' "$AGENTS" > "$AGENTS.tmp" && mv "$AGENTS.tmp" "$AGENTS"
fi

echo "[sync-agents-md] ✅ Synced $AGENTS (v$CURRENT_VERSION → v$TEMPLATE_VERSION)"
