#!/usr/bin/env bash
# status-kgm.sh — Report KG Memory extension status
#
# Reports:
#   - Global config: whether extension entry exists in config.yaml
#   - Session state: whether KGM tools are available (agent must check separately)
#   - JSONL index: file existence, entity count, size, last reindex time
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
source "${HOME}/.agents/scripts/agentfs-contract.sh"   # KGM_EXT_KEY / KGM_EXT_NAME / KGM_TOOL_PREFIX
trace_init "goose-kgm" "1.7.0" 2>/dev/null || true

CONFIG="$HOME/.config/goose/config.yaml"
JSONL_PATH="$HOME/.agents/knowledge/.kgm-index.jsonl"

echo "=== KG Memory (KGM) Status ==="
echo

# ── Global Config ──────────────────────────────────────────────────
if grep -qF "$KGM_EXT_KEY" "$CONFIG" 2>/dev/null; then
  echo "Config entry: ✅ present in $CONFIG"
else
  echo "Config entry: ❌ missing (run setup-kgm.sh)"
fi

# ── Tool-name contract (agentfs-contract.sh) ──────────────────────
# goose derives the tool prefix from the extension's `name` field, so a
# renamed display name renames every KGM tool and the AgentFS hooks and
# graders no longer recognise search_nodes.
name_check=$(python3 - "$CONFIG" <<'PYEOF' 2>/dev/null
import os, re, sys, yaml
key, want_name, want = os.environ['KGM_EXT_KEY'], os.environ['KGM_EXT_NAME'], os.environ['KGM_TOOL_PREFIX']
exts = (yaml.safe_load(open(sys.argv[1])) or {}).get('extensions') or {}
def prefix(n): return re.sub(r'[^a-z0-9_-]', '_', re.sub(r'\s', '', n.lower()))
cands = {k: v for k, v in exts.items() if k == key or 'server-memory' in ' '.join(map(str, (v or {}).get('args') or []))}
if not cands: print("none"); sys.exit()
for k, v in cands.items():
    got = prefix(str((v or {}).get('name') or k))
    state = "ok" if got == want else "mismatch"
    print(f"{state}|{k}|{(v or {}).get('name')}|{got}|{'on' if (v or {}).get('enabled') else 'off'}")
PYEOF
)
if [[ -z "$name_check" || "$name_check" == "none" ]]; then
  echo "Tool names:   ⚠️  no KGM entry found to check"
else
  while IFS='|' read -r st k nm got en; do
    if [[ "$st" == "ok" ]]; then
      echo "Tool names:   ✅ extensions.$k name '$nm' -> ${got}__search_nodes ($en)"
    else
      echo "Tool names:   ❌ extensions.$k name '$nm' -> ${got}__search_nodes ($en), expected $KGM_SEARCH_TOOL"
      echo "  Fix: set name: \"$KGM_EXT_NAME\" under extensions.$k in $CONFIG, then restart goose."
    fi
  done <<< "$name_check"
fi
lint=$(bash "${HOME}/.agents/scripts/agentfs-contract-lint.sh" 2>&1 | head -1)
echo "Code lint:    ${lint#\[contract-lint\] }"

# ── Session State ──────────────────────────────────────────────────
# The shell script cannot detect session-level extension state.
# The agent must check this by inspecting available tools or calling:
#   extensionmanager__manage_extensions / search_nodes
echo
echo "Session:      ⚠️  check via agent (see note below)"
echo "  The agent should verify KGM session state by checking if"
echo "  $KGM_TOOL_PREFIX tools (search_nodes, read_graph) are"
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

# ── Symlink Health ─────────────────────────────────────────────────
echo
echo "--- Symlink Health ---"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/ensure-kgm-symlink.sh"
