#!/usr/bin/env bash
# test-model-compat.sh — Test if a MaaS model is compatible with Goose
#
# Checks whether a model produces reasoning_content in its responses,
# which is incompatible with Goose's streaming parser.
#
# Usage: test-model-compat.sh --url URL --key KEY [--model MODEL]
#
# Exit codes:
#   0 — Model is compatible (no reasoning_content)
#   1 — Model is incompatible (produces reasoning_content)
#   2 — Test failed (endpoint error)

set -euo pipefail

MAAS_URL=""
MAAS_KEY=""
MODEL="llama-scout-17b"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MAAS_URL="$2"; shift 2 ;;
    --key) MAAS_KEY="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MAAS_URL" || -z "$MAAS_KEY" ]]; then
  echo "Usage: test-model-compat.sh --url URL --key KEY [--model MODEL]" >&2
  exit 2
fi

echo "Model Compatibility Test"
echo "════════════════════════"
echo "Endpoint: $MAAS_URL"
echo "Model:    $MODEL"
echo ""

RESPONSE=$(curl -s --connect-timeout 10 \
  "$MAAS_URL/v1/chat/completions" \
  -H "Authorization: Bearer $MAAS_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [{\"role\":\"user\",\"content\":\"Say hello in one sentence\"}],
    \"max_tokens\": 100,
    \"stream\": false
  }" 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
  echo "❌ No response from endpoint"
  exit 2
fi

# Check for error
ERROR=$(echo "$RESPONSE" | python3 -c "
import json,sys
try:
    d = json.load(sys.stdin)
    if 'error' in d:
        print(d['error'].get('message', str(d['error'])))
except:
    pass
" 2>/dev/null)

if [[ -n "$ERROR" ]]; then
  echo "❌ API error: $ERROR"
  exit 2
fi

# Check for reasoning_content
echo "$RESPONSE" | python3 -c "
import json,sys
d = json.load(sys.stdin)
c = d['choices'][0]['message']
content = c.get('content', '(none)')
reasoning = c.get('reasoning_content')
print(f'Content:           {content[:80]}')
print(f'Reasoning content: {reasoning is not None}')
print()
if reasoning:
    print('⚠️  This model produces reasoning_content')
    print('   INCOMPATIBLE with Goose — tool calls will be dropped')
    print('   Use llama-scout-17b instead')
    sys.exit(1)
else:
    print('✅ No reasoning_content — compatible with Goose')
    sys.exit(0)
"
exit $?
