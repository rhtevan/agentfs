#!/usr/bin/env bash
# test.sh — Test a running model via its API
# Usage: bash test.sh ALIAS
# Returns: 0 if all tests pass, 1 if any fail

source "$(dirname "$0")/common.sh"

ALIAS="${1:?Usage: test.sh ALIAS}"
parse_model "$ALIAS"

PASSED=0
FAILED=0

pass() { echo "  ✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== Test: $ALIAS ($MODEL_ID) on $HOST:$PORT ==="
echo

# T1: Container is running
echo "T1: Container running"
status=$(check_container_status "$HOST" "$CONTAINER")
if [[ "$status" == *"Up"* ]]; then
  pass "Container $CONTAINER is running"
else
  fail "Container $CONTAINER is not running: $status"
  echo "Aborting — container must be running for further tests."
  echo
  echo "Results: $PASSED passed, $FAILED failed"
  exit 1
fi

# T2: API responds HTTP 200
echo "T2: API health check"
code=$(run_on_host "$HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$code" == "200" ]]; then
  pass "HTTP 200 on ${HOST}:${PORT}/v1/models"
else
  fail "HTTP $code on ${HOST}:${PORT}/v1/models (expected 200)"
fi

# T3: Correct model ID
echo "T3: Model ID"
actual_model=$(run_on_host "$HOST" "curl -s http://localhost:${PORT}/v1/models" 2>/dev/null | \
  python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$actual_model" == "$MODEL_ID" || "$actual_model" == *"$MODEL_ID"* ]]; then
  pass "Model ID: $actual_model"
else
  # llama.cpp uses file path as model ID
  if [[ "$ENGINE" == "llamacpp" && "$actual_model" == *"granite"* ]]; then
    pass "Model ID: $actual_model (llama.cpp path-based)"
  else
    fail "Model ID: $actual_model (expected $MODEL_ID)"
  fi
fi

# T4: Chat completion
echo "T4: Chat completion"
model_param="$MODEL_ID"
[[ "$ENGINE" == "llamacpp" ]] && model_param="/models/granite-4.1-8b-Q4_K_M.gguf"

response=$(run_on_host "$HOST" "curl -s http://localhost:${PORT}/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{\"model\": \"${model_param}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}], \"max_tokens\": 20}'" 2>/dev/null)

chat_content=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "PARSE_ERROR")
if [[ "$chat_content" != "PARSE_ERROR" && -n "$chat_content" ]]; then
  pass "Chat response: $(echo "$chat_content" | head -c 60)"
else
  fail "Chat completion failed or returned empty response"
fi

# Summary
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
