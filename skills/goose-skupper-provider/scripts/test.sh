#!/usr/bin/env bash
# test.sh — Verify Goose Skupper provider configuration
# Usage: bash test.sh

set -euo pipefail

PROVIDER_JSON="$HOME/.config/goose/custom_providers/custom_skupper.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"

PASSED=0
FAILED=0

pass() { echo "  ✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ❌ $1"; FAILED=$((FAILED + 1)); }

echo "=== Goose Skupper Provider — Test ==="
echo

# T1: JSON file exists
echo "T1: Provider JSON exists"
if [[ -f "$PROVIDER_JSON" ]]; then
  pass "$PROVIDER_JSON"
else
  fail "$PROVIDER_JSON not found"
  echo "     Run setup.sh first."
  echo
  echo "=== Results: $PASSED passed, $FAILED failed ==="
  exit 1
fi

# T2: JSON is valid and has correct schema
echo "T2: JSON schema"
VALID=$(python3 -c "
import json, sys
try:
    d = json.load(open('$PROVIDER_JSON'))
    required = ['name', 'engine', 'display_name', 'base_url', 'models',
                'requires_auth', 'timeout_seconds', 'supports_streaming']
    missing = [f for f in required if f not in d]
    if missing:
        print(f'MISSING:{\"|\".join(missing)}')
    elif d['name'] != 'custom_skupper':
        print(f'WRONG_NAME:{d[\"name\"]}')
    elif d['engine'] != 'openai':
        print(f'WRONG_ENGINE:{d[\"engine\"]}')
    else:
        print('OK')
except Exception as e:
    print(f'ERROR:{e}')
" 2>/dev/null)

if [[ "$VALID" == "OK" ]]; then
  pass "Valid JSON with correct schema"
else
  fail "$VALID"
fi

# T3: Extract model and port
echo "T3: Model and port"
MODEL=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d['models'][0]['name'])" 2>/dev/null || echo "ERROR")
PORT=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d['base_url'].split(':')[-1])" 2>/dev/null || echo "ERROR")
CTX=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d['models'][0]['context_limit'])" 2>/dev/null || echo "ERROR")

if [[ "$MODEL" != "ERROR" && "$PORT" != "ERROR" ]]; then
  pass "Model: $MODEL, Port: $PORT, Context: $CTX"
else
  fail "Could not extract model/port from JSON"
fi

# T4: config.yaml has matching entry
echo "T4: config.yaml entry"
if grep -q 'custom_skupper:' "$CONFIG_YAML" 2>/dev/null; then
  CONFIG_MODEL=$(grep -A3 'custom_skupper:' "$CONFIG_YAML" | grep 'model:' | awk '{print $2}')
  if [[ "$CONFIG_MODEL" == "$MODEL" ]]; then
    pass "config.yaml model matches JSON ($CONFIG_MODEL)"
  else
    fail "config.yaml model ($CONFIG_MODEL) != JSON model ($MODEL)"
  fi
else
  fail "custom_skupper not found in config.yaml"
fi

# T5: Endpoint reachable
echo "T5: Endpoint health"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  pass "HTTP 200 on localhost:$PORT"
else
  fail "HTTP $HTTP_CODE on localhost:$PORT (model may not be running)"
fi

# T6: Chat completion
echo "T6: Chat completion"
if [[ "$HTTP_CODE" == "200" ]]; then
  # Use max_tokens=200 to allow room for reasoning models (e.g., Granite 4.2+)
  RESPONSE=$(curl -s --max-time 120 "http://localhost:${PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}], \"max_tokens\": 200}" 2>/dev/null)
  CHAT=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "PARSE_ERROR")
  REASONING=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message'].get('reasoning_content',''))" 2>/dev/null || echo "")
  if [[ "$CHAT" != "PARSE_ERROR" && -n "$CHAT" ]]; then
    pass "Chat: $(echo "$CHAT" | head -c 60)"
  elif [[ -n "$REASONING" && "$REASONING" != "" ]]; then
    pass "Chat (reasoning model): $(echo "$REASONING" | head -c 60)"
  else
    fail "Chat completion failed"
  fi
else
  fail "Skipped (endpoint not responding)"
fi

# Summary
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[[ $FAILED -eq 0 ]] && exit 0 || exit 1
