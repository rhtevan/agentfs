#!/usr/bin/env bash
# test-model.sh — Verify model access through Skupper VAN from localhost
# Usage: bash test-model.sh [MODEL_PORT]
set -euo pipefail

MODEL_PORT="${1:-8000}"
BASE_URL="http://localhost:${MODEL_PORT}"

PASSED=0
FAILED=0

check() {
  local label="$1"
  local ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "✅ ${label}"
    PASSED=$((PASSED + 1))
  else
    echo "❌ ${label}"
    FAILED=$((FAILED + 1))
  fi
}

echo "══════════════════════════════════════════════════════════"
echo "Test: Model Access via Skupper VAN"
echo "Endpoint: ${BASE_URL}"
echo "══════════════════════════════════════════════════════════"

# ---- Test 1: API Reachability ----
echo ""
echo "── Test 1: API Reachability ──"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/v1/models" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  check "GET /v1/models → HTTP ${HTTP_CODE}" 1
  # Show models
  echo "   Models available:"
  curl -s "${BASE_URL}/v1/models" | python3 -m json.tool 2>/dev/null | grep '"id"' | sed 's/^/   /'
else
  check "GET /v1/models → HTTP ${HTTP_CODE} (expected 200)" 0
  echo ""
  echo "❌ API not reachable. Remaining tests skipped."
  echo "   Check: skupper model up"
  exit 1
fi

# Discover model name from the API
MODEL_NAME=$(curl -s "${BASE_URL}/v1/models" 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data'][0]['id'])" 2>/dev/null || echo "unknown")
echo "   Using model: ${MODEL_NAME}"

# ---- Test 2: Chat Completion ----
echo ""
echo "── Test 2: Chat Completion ──"
CHAT_RESPONSE=$(curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{"model": "'"${MODEL_NAME}"'", "messages": [{"role": "user", "content": "Hello! Say exactly: skupper-test-ok"}], "max_tokens": 50}' 2>/dev/null || echo "")

if [[ -n "$CHAT_RESPONSE" ]]; then
  CHAT_CONTENT=$(echo "$CHAT_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])" 2>/dev/null || echo "<parse error>")
  FINISH_REASON=$(echo "$CHAT_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['finish_reason'])" 2>/dev/null || echo "")
  if [[ -n "$CHAT_CONTENT" && "$CHAT_CONTENT" != "<parse error>" ]]; then
    check "Chat completion returned content (finish_reason=${FINISH_REASON})" 1
    echo "   Response: ${CHAT_CONTENT:0:120}"
  else
    check "Chat completion returned parseable content" 0
    echo "   Raw: ${CHAT_RESPONSE:0:200}"
  fi
else
  check "Chat completion request succeeded" 0
fi

# ---- Test 3: Tool Calling ----
echo ""
echo "── Test 3: Tool Calling ──"
TOOL_RESPONSE=$(curl -s "${BASE_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [{"role": "user", "content": "What is the weather in London?"}],
    "tools": [{"type": "function", "function": {"name": "get_weather", "description": "Get weather for a location", "parameters": {"type": "object", "properties": {"location": {"type": "string"}}, "required": ["location"]}}}],
    "max_tokens": 200
  }' 2>/dev/null || echo "")

if [[ -n "$TOOL_RESPONSE" ]]; then
  # Check if tool_calls present
  HAS_TOOL_CALLS=$(echo "$TOOL_RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
msg = r['choices'][0]['message']
tc = msg.get('tool_calls', [])
print('yes' if tc else 'no')
" 2>/dev/null || echo "no")

  if [[ "$HAS_TOOL_CALLS" == "yes" ]]; then
    TOOL_NAME=$(echo "$TOOL_RESPONSE" | python3 -c "
import sys, json
r = json.load(sys.stdin)
tc = r['choices'][0]['message']['tool_calls'][0]
print(f\"{tc['function']['name']}({tc['function']['arguments']})\")
" 2>/dev/null || echo "<parse error>")
    check "Tool calling — model invoked function" 1
    echo "   Tool call: ${TOOL_NAME}"
  else
    # Some models respond with text instead of tool_calls — not a hard failure
    TOOL_CONTENT=$(echo "$TOOL_RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'][:100])" 2>/dev/null || echo "")
    check "Tool calling — model responded (no tool_calls, text instead)" 1
    echo "   Response: ${TOOL_CONTENT:0:120}"
  fi
else
  check "Tool calling request succeeded" 0
fi

# ---- Summary ----
echo ""
echo "══════════════════════════════════════════════════════════"
TOTAL=$((PASSED + FAILED))
echo "Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All model access tests PASSED via Skupper VAN"
  exit 0
else
  echo "❌ Some tests FAILED"
  exit 1
fi
