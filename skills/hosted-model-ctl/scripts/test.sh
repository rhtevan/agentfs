#!/usr/bin/env bash
# test.sh — Test a running deployment profile
# Usage: bash test.sh PROFILE
# Runs 4 tests: container running, API health, model ID, chat completion.

source "$(dirname "$0")/common.sh"

PROFILE="${1:-}"

if [[ -z "$PROFILE" ]]; then
  echo "Usage: test.sh PROFILE" >&2
  echo "" >&2
  list_profiles >&2
  exit 1
fi

parse_profile "$PROFILE"

echo "=== Test: $PROFILE ==="
echo "  $PROFILE_DESC"
echo "  Host: $PROFILE_HOST  Port: $PORT"
echo

PASSED=0
FAILED=0

run_test() {
  local name="$1"
  local result="$2"
  if [[ "$result" == "PASS" ]]; then
    echo "  ✅ $name"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $name: $result"
    FAILED=$((FAILED + 1))
  fi
}

# Test 1: Container running
status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
if [[ "$status" == *"Up"* ]]; then
  run_test "Container running" "PASS"
else
  run_test "Container running" "FAIL: $status"
  echo ""
  echo "$PASSED/$((PASSED + FAILED)) tests passed (container not running, skipping remaining tests)"
  exit 1
fi

# Test 2: API health
code=$(run_on_host "$PROFILE_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/v1/models 2>/dev/null" || echo "000")
if [[ "$code" == "200" ]]; then
  run_test "API health (HTTP $code)" "PASS"
else
  run_test "API health" "FAIL: HTTP $code"
fi

# Test 3: Model ID
model_id=$(run_on_host "$PROFILE_HOST" "curl -s http://localhost:${PORT}/v1/models 2>/dev/null" | jq -r '.data[0].id' 2>/dev/null)
if [[ -n "$model_id" && "$model_id" != "null" ]]; then
  run_test "Model ID ($model_id)" "PASS"
else
  run_test "Model ID" "FAIL: empty or null"
fi

# Test 4: Chat completion
# Use max_tokens=200 to allow room for reasoning models that use
# <think> tokens before producing visible content (e.g., Granite 4.2+)
response=$(run_on_host "$PROFILE_HOST" "curl -s --max-time 120 http://localhost:${PORT}/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{\"model\": \"${model_id}\", \"max_tokens\": 200, \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}]}' 2>/dev/null")
content=$(echo "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
reasoning=$(echo "$response" | jq -r '.choices[0].message.reasoning_content // ""' 2>/dev/null)
if [[ -n "$content" && "$content" != "null" && "$content" != "" ]]; then
  short_content=$(echo "$content" | head -c 80)
  run_test "Chat completion (\"$short_content\")" "PASS"
elif [[ -n "$reasoning" && "$reasoning" != "null" && "$reasoning" != "" ]]; then
  short_reason=$(echo "$reasoning" | head -c 80)
  run_test "Chat completion (reasoning: \"$short_reason\")" "PASS"
else
  run_test "Chat completion" "FAIL: empty response"
fi

echo ""
echo "$PASSED/$((PASSED + FAILED)) tests passed"
[[ "$FAILED" -gt 0 ]] && exit 1 || exit 0
