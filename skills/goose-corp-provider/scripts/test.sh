#!/usr/bin/env bash
# test.sh — Validate Corp provider end-to-end (key + chat completion)
# Usage: bash test.sh [--model MODEL_ID]
set -euo pipefail

source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "test" 2>/dev/null || true

HOST="https://models.corp.redhat.com"
BASE_URL="${HOST}/oai/v1"
MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    *) echo "Usage: test.sh [--model MODEL_ID]" >&2; exit 2 ;;
  esac
done

# Read API key from GNOME Keyring
trace_step "key-read" "Reading API key from keyring" 2>/dev/null || true

KEYRING_DATA=$(secret-tool lookup service goose 2>/dev/null || echo '{}')
API_KEY=$(echo "$KEYRING_DATA" | jq -r '.CUSTOM_CORP_API_KEY // empty' 2>/dev/null)

if [[ -z "$API_KEY" ]]; then
  echo "❌ CUSTOM_CORP_API_KEY not found in GNOME Keyring."
  echo "   Run: goose configure → Configure Providers → Corp"
  trace_end 1 2>/dev/null || true
  exit 1
fi

# If no model specified, read default from config
if [[ -z "$MODEL" ]]; then
  CONFIG="$HOME/.config/goose/config.yaml"
  if [[ -f "$CONFIG" ]]; then
    MODEL=$(python3 -c "
import yaml
with open('$CONFIG') as f:
    c = yaml.safe_load(f)
p = c.get('providers', {}).get('custom_corp', {})
print(p.get('model', ''))
" 2>/dev/null || echo "")
  fi
fi

if [[ -z "$MODEL" ]]; then
  # Fall back to first available chat model
  MODEL=$(curl -s --connect-timeout 10 "${BASE_URL}/models" 2>/dev/null \
    | jq -r '.data[] | select((.id | test("embed|rerank|guardian|parse|diffusion"; "i")) | not) | .id' \
    | head -1 || echo "")
fi

if [[ -z "$MODEL" ]]; then
  echo "❌ No model specified and could not auto-detect."
  trace_end 1 2>/dev/null || true
  exit 1
fi

echo "Testing model: $MODEL"

trace_step "chat-test" "Sending chat completion request" 2>/dev/null || true

RESPONSE=$(curl -s --connect-timeout 15 --max-time 60 \
  "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"${MODEL}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in one word.\"}], \"max_tokens\": 500}" \
  -w "\n%{http_code}" 2>/dev/null)

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

case "$HTTP_CODE" in
  200)
    CONTENT=$(echo "$BODY" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    REASONING=$(echo "$BODY" | jq -r '.choices[0].message.reasoning // empty' 2>/dev/null)
    if [[ -n "$CONTENT" && "$CONTENT" != "null" ]]; then
      SHORT=$(echo "$CONTENT" | head -c 80)
      echo "✅ Chat completion succeeded (HTTP 200)"
      echo "   Model: $MODEL"
      echo "   Response: \"$SHORT\""
      if [[ -n "$REASONING" && "$REASONING" != "null" ]]; then
        echo "   Thinking: enabled ($(echo "$REASONING" | wc -c) chars)"
      fi
    elif [[ -n "$REASONING" && "$REASONING" != "null" ]]; then
      echo "✅ Chat completion succeeded (HTTP 200, thinking mode)"
      echo "   Model: $MODEL"
      echo "   Reasoning: $(echo "$REASONING" | head -c 80)"
      echo "   ⚠️  Content was empty — model may need higher max_tokens"
    else
      echo "⚠️  HTTP 200 but empty content and reasoning."
      echo "   Model may be loading or unavailable."
    fi
    ;;
  401)
    echo "❌ Authentication failed (HTTP 401)"
    echo "   API key is invalid or expired."
    echo "   Run: bash ~/.agents/skills/goose-corp-provider/scripts/store-key.sh"
    trace_end 1 2>/dev/null || true
    exit 1
    ;;
  403)
    echo "❌ Forbidden (HTTP 403)"
    echo "   API key lacks required permissions."
    trace_end 1 2>/dev/null || true
    exit 1
    ;;
  *)
    echo "❌ Unexpected response (HTTP $HTTP_CODE)"
    echo "   Body: $(echo "$BODY" | head -c 200)"
    trace_end 1 2>/dev/null || true
    exit 1
    ;;
esac

trace_end 0 2>/dev/null || true
