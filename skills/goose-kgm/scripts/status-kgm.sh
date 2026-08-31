#!/usr/bin/env bash
# status-kgm.sh — Report KG Memory extension status
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_PATH="$HOME/.agents/knowledge/.kgm-index.jsonl"

echo "=== KG Memory (KGM) Status ==="
echo

# ── Configured? ────────────────────────────────────────────────────
if grep -q 'knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "Configured: ✅ yes"

  # ── Enabled? ───────────────────────────────────────────────────
  ENABLED=$(python3 -c "
import yaml, os
config = yaml.safe_load(open(os.path.expanduser('~/.config/goose/config.yaml')))
ext = config.get('extensions', {}).get('knowledgegraphmemory', {})
print('yes' if ext.get('enabled') else 'no')
")
  if [[ "$ENABLED" == "yes" ]]; then
    echo "Enabled:    ✅ yes"
  else
    echo "Enabled:    ❌ no"
  fi
else
  echo "Configured: ❌ no (run setup-kgm.sh)"
  echo "Enabled:    — (not configured)"
fi

# ── JSONL file ─────────────────────────────────────────────────────
echo
if [[ -f "$JSONL_PATH" ]]; then
  ENTITIES=$(wc -l < "$JSONL_PATH")
  SIZE=$(du -h "$JSONL_PATH" | cut -f1)
  MTIME=$(stat -c '%Y' "$JSONL_PATH" 2>/dev/null || stat -f '%m' "$JSONL_PATH" 2>/dev/null)
  MTIME_HUMAN=$(date -d "@$MTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$MTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  echo "JSONL file: ✅ $JSONL_PATH"
  echo "  Lines:    $ENTITIES"
  echo "  Size:     $SIZE"
  echo "  Modified: $MTIME_HUMAN"
else
  echo "JSONL file: ❌ not found ($JSONL_PATH)"
  echo "  Run reindex-kgm.sh to populate."
fi
