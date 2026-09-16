#!/usr/bin/env bash
# status-kgm.sh — Report KG Memory extension status
#
# Reports:
#   - Global config: whether extension entry exists in config.yaml
#   - Session state: whether KGM tools are available (agent must check separately)
#   - JSONL index: file existence, entity count, size, last reindex time
set -euo pipefail

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_PATH="$HOME/.agents/knowledge/.kgm-index.jsonl"

echo "=== KG Memory (KGM) Status ==="
echo

# ── Global Config ──────────────────────────────────────────────────
if grep -q 'knowledgegraphmemory' "$CONFIG" 2>/dev/null; then
  echo "Config entry: ✅ present in $CONFIG"
else
  echo "Config entry: ❌ missing (run setup-kgm.sh)"
fi

# ── Session State ──────────────────────────────────────────────────
# The shell script cannot detect session-level extension state.
# The agent must check this by inspecting available tools or calling:
#   extensionmanager__manage_extensions / search_nodes
echo
echo "Session:      ⚠️  check via agent (see note below)"
echo "  The agent should verify KGM session state by checking if"
echo "  knowledgegraphmemory tools (search_nodes, read_graph) are"
echo "  available. Shell scripts cannot detect session-level state."

# ── JSONL file ─────────────────────────────────────────────────────
echo
if [[ -f "$JSONL_PATH" ]]; then
  LINES=$(wc -l < "$JSONL_PATH")
  BUNDLES=$(grep -c '"KnowledgeBundle"' "$JSONL_PATH" 2>/dev/null || echo 0)
  CONCEPTS=$(grep -c '"KnowledgeConcept"' "$JSONL_PATH" 2>/dev/null || echo 0)
  RELATIONS=$(grep -c '"type": "relation"' "$JSONL_PATH" 2>/dev/null || echo 0)
  SIZE=$(du -h "$JSONL_PATH" | cut -f1)
  MTIME=$(stat -c '%Y' "$JSONL_PATH" 2>/dev/null || stat -f '%m' "$JSONL_PATH" 2>/dev/null)
  MTIME_HUMAN=$(date -d "@$MTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$MTIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  echo "JSONL file:   ✅ $JSONL_PATH"
  echo "  Bundles:    $BUNDLES"
  echo "  Concepts:   $CONCEPTS"
  echo "  Relations:  $RELATIONS"
  echo "  Total lines: $LINES"
  echo "  Size:       $SIZE"
  echo "  Last reindex: $MTIME_HUMAN"
else
  echo "JSONL file:   ❌ not found ($JSONL_PATH)"
  echo "  Run: bash ~/.agents/skills/goose-kgm/scripts/reindex-kgm.sh"
fi
