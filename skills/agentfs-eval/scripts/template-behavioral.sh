#!/usr/bin/env bash
# template-behavioral.sh — Behavioral assertions for AGENTS.md instruction effectiveness
#
# Usage: bash template-behavioral.sh [--provider PROVIDER] [--model MODEL] [TARGET_DIR]
#
# Replays a fixed set of user inputs through the goose agent and checks
# whether the model's FIRST tool call matches expected behavior.
# Requires a running goose provider. Uses goose CLI in non-interactive mode.
#
# Test cases validate:
#   - Skill discovery (does "skupper status" trigger search_nodes or load_skill?)
#   - Signal routing (does "hey git" trigger load_skill?)
#   - Anti-pattern adherence (does it avoid extensionmanager/shell for skills?)
#
# Exit code: always 0 — failures are informational scores, not errors.
# Non-zero exits cause weaker models to retry in an infinite loop.

set -euo pipefail

PROVIDER="${GOOSE_PROVIDER:-}"
MODEL="${GOOSE_MODEL:-}"
TARGET="."

# ── Parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) PROVIDER="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

TARGET="$(cd "$TARGET" && pwd)"

if [ -z "$PROVIDER" ]; then
  echo "Usage: bash template-behavioral.sh --provider PROVIDER [--model MODEL] [TARGET_DIR]"
  echo "  Or set GOOSE_PROVIDER and GOOSE_MODEL environment variables."
  exit 1
fi

PASS=0
FAIL=0
TOTAL=0
SESSIONS_DB="${HOME}/.local/share/goose/sessions/sessions.db"

# Track all sessions created during this run for cleanup
declare -a CREATED_SESSIONS=()

result_pass() { PASS=$((PASS + 1)); echo "  [✅] $1"; }
result_fail() { FAIL=$((FAIL + 1)); echo "  [❌] $1 — got: $2"; }

# ── Session Cleanup ──────────────────────────────────────────────────
# Delete a single session from the goose SQLite database.
# Silently succeeds if session doesn't exist or DB is unavailable.
cleanup_session() {
  local name="$1"
  python3 -c "
import sqlite3, os, sys
db = os.path.expanduser('$SESSIONS_DB')
if not os.path.exists(db):
    sys.exit(0)
try:
    conn = sqlite3.connect(db, timeout=5)
    cur = conn.cursor()
    cur.execute('SELECT id FROM sessions WHERE name=?', (sys.argv[1],))
    row = cur.fetchone()
    if row:
        sid = row[0]
        cur.execute('DELETE FROM messages WHERE session_id=?', (sid,))
        cur.execute('DELETE FROM usage_ledger WHERE session_id=?', (sid,))
        cur.execute('DELETE FROM sessions WHERE id=?', (sid,))
        conn.commit()
    conn.close()
except Exception:
    pass  # DB locked or schema changed — don't block the script
" "$name" 2>/dev/null || true
}

# Clean up all tracked sessions + sweep for orphans from previous crashed runs.
# Called on any exit: normal, error, SIGTERM, SIGINT.
cleanup_all() {
  # Clean sessions created this run
  for s in "${CREATED_SESSIONS[@]+"${CREATED_SESSIONS[@]}"}"; do
    cleanup_session "$s"
  done

  # Sweep orphaned agentfs-eval-* sessions older than 5 minutes
  python3 -c "
import sqlite3, os, time, sys
db = os.path.expanduser('$SESSIONS_DB')
if not os.path.exists(db):
    sys.exit(0)
try:
    conn = sqlite3.connect(db, timeout=5)
    cur = conn.cursor()
    cutoff = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(time.time() - 300))
    cur.execute(
        \"\"\"SELECT id, name FROM sessions
           WHERE name LIKE 'agentfs-eval-%'
           AND updated_at < ?\"\"\",
        (cutoff,))
    orphans = cur.fetchall()
    for sid, name in orphans:
        cur.execute('DELETE FROM messages WHERE session_id=?', (sid,))
        cur.execute('DELETE FROM usage_ledger WHERE session_id=?', (sid,))
        cur.execute('DELETE FROM sessions WHERE id=?', (sid,))
    if orphans:
        conn.commit()
        print(f'  🧹 Cleaned {len(orphans)} orphaned eval session(s)', file=sys.stderr)
    conn.close()
except Exception:
    pass
" 2>/dev/null || true
}

trap cleanup_all EXIT

# ── Test Harness ──────────────────────────────────────────────────────
# Runs a single user message through goose and extracts the first tool call
run_test() {
  local test_id="$1"
  local input="$2"
  local expected_tool="$3"
  local unexpected_tools="$4"  # comma-separated list of tools that indicate failure
  TOTAL=$((TOTAL + 1))

  local provider_args=""
  [ -n "$PROVIDER" ] && provider_args="--provider $PROVIDER"
  [ -n "$MODEL" ] && provider_args="$provider_args --model $MODEL"

  # Generate unique session name and track it
  local session_name="agentfs-eval-${test_id}-$$"
  CREATED_SESSIONS+=("$session_name")

  # Run goose with the test input
  local output
  output=$(cd "$TARGET" && timeout 90 goose run \
    --name "$session_name" \
    $provider_args \
    --text "$input" \
    2>/dev/null || true)

  # Export session to get tool calls
  local session_json
  session_json=$(goose session export --name "$session_name" --format json 2>/dev/null || echo "{}")

  # Extract first tool call name
  # Extract first non-denied tool call.
  # Tool calls blocked by PreToolUse hooks (e.g., signal-dispatch plugin)
  # are followed by an error response containing "denied by policy hook".
  # Skip those and find the first tool call that was actually executed.
  local first_tool
  first_tool=$(echo "$session_json" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    msgs = data.get('conversation', [])
    for i, msg in enumerate(msgs):
        for content in msg.get('content', []):
            if content.get('type') == 'toolRequest':
                tc = content.get('toolCall', {})
                val = tc.get('value', tc)
                name = val.get('name', '')
                if not name:
                    continue
                # Check if the next message contains a denial for this call
                denied = False
                if i + 1 < len(msgs):
                    for rc in msgs[i + 1].get('content', []):
                        if rc.get('type') == 'toolResponse':
                            tr = rc.get('toolResult', rc.get('result', {}))
                            text = str(tr.get('error', '')) + str(tr.get('result', '')) + str(tr)
                            if 'denied by policy hook' in text:
                                denied = True
                                break
                if not denied:
                    print(name)
                    sys.exit(0)
    print('NO_TOOL_CALL')
except:
    print('PARSE_ERROR')
" 2>/dev/null | head -1)

  # Eagerly clean up this session now (trap handles stragglers)
  cleanup_session "$session_name"

  # Evaluate — expected_tool can be comma-separated list of acceptable tools
  IFS=',' read -ra GOOD_TOOLS <<< "$expected_tool"
  for good in "${GOOD_TOOLS[@]}"; do
    if [ "$first_tool" = "$good" ]; then
      result_pass "$test_id: '$input' → $first_tool"
      return
    fi
  done

  # Check if the first tool is in the unexpected list
  IFS=',' read -ra BAD_TOOLS <<< "$unexpected_tools"
  for bad in "${BAD_TOOLS[@]}"; do
    if [ "$first_tool" = "$bad" ]; then
      result_fail "$test_id: '$input' → expected $expected_tool" "$first_tool (anti-pattern)"
      return
    fi
  done

  # Tool call happened but wasn't the expected one
  result_fail "$test_id: '$input' → expected $expected_tool" "$first_tool"
}

# ── Dedup Guard ───────────────────────────────────────────────────────
# Prevent weaker models from re-running the same test in a loop.
# If a score was recorded for this version+model within the last 10 minutes, skip.
SCORES_FILE="$HOME/.agents/skills/agentfs-eval/references/template-scores.md"
MODEL_SHORT_GUARD="${MODEL:-unknown}"

if [ -f "$SCORES_FILE" ]; then
  LAST_RUN=$(grep "$MODEL_SHORT_GUARD" "$SCORES_FILE" | grep "Behavioral:" | head -1 | grep -oP '^\| \K[0-9-]+ [0-9:]+' || true)
  if [ -n "$LAST_RUN" ]; then
    LAST_EPOCH=$(date -d "$LAST_RUN" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE=$(( NOW_EPOCH - LAST_EPOCH ))
    if [ "$AGE" -lt 600 ]; then
      echo "=== AGENTS.md Behavioral Test ==="
      echo "  Provider: ${PROVIDER}${MODEL:+ / $MODEL}"
      echo "  Target: $TARGET"
      echo ""
      echo "  ⏭️  SKIPPED — behavioral test for $MODEL_SHORT_GUARD already ran ${AGE}s ago (< 10 min)."
      echo "     Last result is still valid. Re-running produces identical results."
      echo "     To force re-run, wait 10 minutes or clear the score entry."
      echo ""
      echo "Results: skipped"
      exit 0
    fi
  fi
fi

# ── Test Cases ────────────────────────────────────────────────────────
echo "=== AGENTS.md Behavioral Test ==="
echo "  Provider: ${PROVIDER}${MODEL:+ / $MODEL}"
echo "  Target: $TARGET"
echo ""

# All test inputs use the "hey" prefix to trigger Signal Dispatch (Rule 2).
# The signal-dispatch plugin enforces dispatch via PreToolUse hooks —
# blocked tool calls are skipped when scoring (first non-denied call wins).

# B1: Skill discovery — "hey" + natural language skill request
run_test "B1-skill-discovery" \
  "hey check headroom status" \
  "knowledgegraphmemory__search_nodes" \
  "load_skill,shell,extensionmanager__manage_extensions,extensionmanager__search_available_extensions"

# B2: Signal routing — "hey git" signal dispatch
run_test "B2-signal-git" \
  "hey git" \
  "knowledgegraphmemory__search_nodes" \
  "load_skill,shell,extensionmanager__manage_extensions"

# B3: Skill discovery — different skill to verify dispatch isn't one-off
run_test "B3-skill-dispatch" \
  "hey check crc status" \
  "knowledgegraphmemory__search_nodes" \
  "load_skill,shell,extensionmanager__manage_extensions,extensionmanager__search_available_extensions"

# ── Summary & Score Sheet Update ───────────────────────────────────────
echo ""
echo "Results: $PASS/$TOTAL pass, $FAIL fail"
echo "Provider: ${PROVIDER}${MODEL:+ / $MODEL}"

# Auto-append to score sheet via deterministic script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION_TAG=$(grep -oP 'agentfs-template-version: \K[0-9.]+' "$TARGET/AGENTS.md" 2>/dev/null || echo "unknown")
MODEL_SHORT="${MODEL:-$(grep -oP 'model: \K\S+' "$HOME/.config/goose/config.yaml" 2>/dev/null | head -1)}"
BEHAVIORAL="${PASS}/${TOTAL}"

bash "$SCRIPT_DIR/merge-score-entry.sh" "$VERSION_TAG" "$MODEL_SHORT" \
  --behavioral "$BEHAVIORAL" \
  --notes "Behavioral: ${PROVIDER}/${MODEL_SHORT}"

echo ""
echo "⚠️  Results are final. DO NOT re-run — behavioral scores reflect model capability."

# Exit 0 — failures are informational scores, not errors.
# Non-zero exits cause weaker models to retry in an infinite loop.
exit 0
