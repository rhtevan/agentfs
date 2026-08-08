#!/usr/bin/env bash
# test-model.sh — Test model connectivity through Skupper VAN
# Usage: bash test-model.sh MODEL_ALIAS
# Tests the local Skupper listener endpoint (not the remote model directly)

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:?Usage: test-model.sh MODEL_ALIAS}"

REMOTE_HOST=$(alias_to_host "$MODEL_ALIAS") || exit 1
LOCAL_PORT=$(alias_to_local_port "$MODEL_ALIAS")
ROUTING_KEY=$(alias_to_routing_key "$MODEL_ALIAS")

PASSED=0
FAILED=0

pass() { echo "  ✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== Skupper Model Test: $MODEL_ALIAS ==="
echo "  Routing key:    $ROUTING_KEY"
echo "  Local endpoint: localhost:$LOCAL_PORT"
echo "  Remote host:    $REMOTE_HOST"
echo

# T1: Local listener port open
echo "T1: Local listener"
LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${LOCAL_PORT}" || echo "0")
if [[ "$LISTENING" -gt 0 ]]; then
  pass "Port $LOCAL_PORT listening"
else
  fail "Port $LOCAL_PORT not listening"
  echo "     Skupper router may not be running or link not established."
  echo "     Run: bash up.sh $MODEL_ALIAS"
fi

# T2: Local API responds
echo "T2: API health"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${LOCAL_PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "HTTP 200 on localhost:$LOCAL_PORT"
else
  fail "HTTP $HTTP_CODE on localhost:$LOCAL_PORT (expected 200)"
fi

# T3: Model ID
echo "T3: Model ID"
if [[ "$HTTP_CODE" == "200" ]]; then
  MODEL_ID=$(curl -s "http://localhost:${LOCAL_PORT}/v1/models" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$MODEL_ID" != "PARSE_ERROR" && -n "$MODEL_ID" ]]; then
    pass "Model: $MODEL_ID"
  else
    fail "Could not parse model ID"
  fi
else
  fail "Skipped (API not responding)"
fi

# T4: Chat completion through VAN
echo "T4: Chat completion (through Skupper VAN)"
if [[ "$HTTP_CODE" == "200" ]]; then
  RESPONSE=$(curl -s "http://localhost:${LOCAL_PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${MODEL_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}], \"max_tokens\": 20}" 2>/dev/null)
  
  CHAT=$(echo "$RESPONSE" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "PARSE_ERROR")
  
  if [[ "$CHAT" != "PARSE_ERROR" && -n "$CHAT" ]]; then
    pass "Chat: $(echo "$CHAT" | head -c 60)"
  else
    fail "Chat completion failed or empty response"
  fi
else
  fail "Skipped (API not responding)"
fi

# T5: Remote host reachable
echo "T5: Remote host"
if host_reachable "$REMOTE_HOST"; then
  pass "$REMOTE_HOST reachable"
else
  fail "$REMOTE_HOST unreachable"
fi

# T6: Remote model container running
echo "T6: Remote model container"
if host_reachable "$REMOTE_HOST"; then
  CONTAINER=$(alias_to_container "$MODEL_ALIAS")
  CONTAINER_STATUS=$(run_on_host "$REMOTE_HOST" "podman ps --filter name=${CONTAINER} --format '{{.Status}}'" || echo "")
  if [[ "$CONTAINER_STATUS" == *"Up"* ]]; then
    pass "$CONTAINER running on $REMOTE_HOST"
  else
    fail "$CONTAINER not running: $CONTAINER_STATUS"
  fi
else
  fail "Skipped (host unreachable)"
fi

# Summary
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
