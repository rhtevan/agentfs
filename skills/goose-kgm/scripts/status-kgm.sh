#!/usr/bin/env bash
# status-kgm.sh — Report KG Memory extension status
#
# Reports:
#   - Global config: whether extension entry exists in config.yaml
#   - Session state: whether KGM tools are available (agent must check separately)
#   - JSONL index: file existence, entity count, size, last reindex time
#   - Index path delivery: config form (env wrapper) + MEMORY_FILE_PATH of
#     every running server-memory process (/proc/<pid>/environ)
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
source "${HOME}/.agents/scripts/agentfs-contract.sh"   # KGM_EXT_KEY / KGM_EXT_NAME / KGM_TOOL_PREFIX
trace_init "goose-kgm" "1.8.3" 2>/dev/null || true

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

# ── Index path delivery (config form) ──────────────────────────────
# Goose 1.60.1 drops inline `envs` on the ACP path (new desktop sessions,
# desktop toggles), so MEMORY_FILE_PATH must travel in cmd/args via `env`.
echo
echo "--- Index Path Delivery ---"
form=$(CONFIG="$CONFIG" JSONL_PATH="$JSONL_PATH" python3 <<'PYEOF' 2>/dev/null
import os, yaml
e = ((yaml.safe_load(open(os.environ['CONFIG'])) or {}).get('extensions') or {}).get(os.environ['KGM_EXT_KEY'])
want = f"MEMORY_FILE_PATH={os.environ['JSONL_PATH']}"
if not e: print("missing")
elif e.get('cmd') == 'env' and want in (e.get('args') or []): print("wrapper")
elif 'MEMORY_FILE_PATH' in (e.get('envs') or {}): print("envs-only")
else: print("none")
PYEOF
)
case "$form" in
  wrapper)   echo "Config form:  ✅ cmd: env MEMORY_FILE_PATH=$JSONL_PATH npx …" ;;
  envs-only) echo "Config form:  ❌ MEMORY_FILE_PATH only in envs (dropped on the desktop ACP path)"
             echo "  Fix: bash ~/.agents/skills/goose-kgm/scripts/setup-kgm.sh (migrates to the env wrapper)" ;;
  missing)   echo "Config form:  ❌ no $KGM_EXT_KEY entry (run setup-kgm.sh)" ;;
  *)         echo "Config form:  ❌ MEMORY_FILE_PATH not configured (run setup-kgm.sh)" ;;
esac

# ── Runtime: env of each running server-memory process ─────────────
# The config check alone gave false ✅ before: each session launches its
# server from its own saved copy, so check what the processes received.
if [[ -d /proc ]]; then
  PIDS=$(pgrep -f 'node .*[m]cp-server-memory' || true)
  if [[ -z "$PIDS" ]]; then
    echo "Runtime:      ⚠️  no server-memory process running (KGM not active in any session)"
  else
    BAD=0
    for p in $PIDS; do
      # only real servers: a shell whose command line merely contains the
      # pattern (pgrep -f self-match) is not a server-memory process
      [[ "$(cat "/proc/$p/comm" 2>/dev/null)" == "node" ]] || continue
      cwd=$(readlink "/proc/$p/cwd" 2>/dev/null || echo "?")
      got=$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | sed -n 's/^MEMORY_FILE_PATH=//p')
      if [[ "$got" == "$JSONL_PATH" ]]; then
        echo "Runtime:      ✅ pid $p ($cwd) reads $JSONL_PATH"
      else
        BAD=$((BAD + 1))
        echo "Runtime:      ❌ pid $p ($cwd) MEMORY_FILE_PATH=${got:-UNSET} — search_nodes returns empty in that session"
      fi
    done
    if [[ "$BAD" -gt 0 ]]; then
      echo "  Fix: that session runs a stale saved config. Restart Goose Desktop, then toggle"
      echo "  KGM off/on in the session (or start a new session)."
    fi
  fi
else
  echo "Runtime:      ⚠️  /proc unavailable — verify in-session with search_nodes"
fi
