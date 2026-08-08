#!/usr/bin/env bash
# setup.sh — Configure Goose custom provider for Skupper VAN model
# Usage: bash setup.sh [MODEL_ALIAS]
#   Default: g350m (port 10000)

set -euo pipefail

SCRIPT_DIR="$(dirname "$0")"
PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_JSON="$PROVIDER_DIR/custom_skupper.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"

MODEL_ALIAS="${1:-g350m}"

# ── Model → Port/ID mapping ───────────────────────────────────
case "$MODEL_ALIAS" in
  g350m)    PORT=10000; MODEL_ID="ibm-granite/granite-4.0-350m"; CTX=2048 ;;
  g1b)      PORT=10000; MODEL_ID="ibm-granite/granite-4.0-1b"; CTX=2048 ;;
  g8b)      PORT=10000; MODEL_ID="ibm-granite/granite-4.1-8b"; CTX=16384 ;;
  g30b-96k|g30b) PORT=9000; MODEL_ID="ibm-granite/granite-4.1-30b"; CTX=98304 ;;
  g8b-128k) PORT=9000; MODEL_ID="ibm-granite/granite-4.1-8b"; CTX=131072 ;;
  *)
    echo "❌ Unknown model alias: $MODEL_ALIAS" >&2
    echo "Available: g350m g1b g8b g30b-96k g8b-128k" >&2
    exit 1
    ;;
esac

echo "=== Goose Skupper Provider — Setup ==="
echo "  Model alias:  $MODEL_ALIAS"
echo "  Model ID:     $MODEL_ID"
echo "  Port:         $PORT"
echo "  Context:      $CTX"
echo

# ── Step 1: Verify endpoint ───────────────────────────────────
echo "Step 1: Verify endpoint"
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  ACTUAL_MODEL=$(curl -s "http://localhost:${PORT}/v1/models" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "unknown")
  echo "  ✅ localhost:$PORT → $ACTUAL_MODEL"
else
  echo "  ⚠️  localhost:$PORT not responding (HTTP $HTTP_CODE)"
  echo "  Provider will be configured but may not work until model is started."
  ACTUAL_MODEL="$MODEL_ID"
fi
echo

# ── Step 2: Backup existing JSON ──────────────────────────────
echo "Step 2: Backup existing config"
if [[ -f "$PROVIDER_JSON" ]]; then
  BACKUP="${PROVIDER_JSON}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$PROVIDER_JSON" "$BACKUP"
  echo "  ✅ Backed up to $(basename $BACKUP)"
else
  echo "  (no existing file to backup)"
fi

if [[ -f "$CONFIG_YAML" ]]; then
  BACKUP="${CONFIG_YAML}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_YAML" "$BACKUP"
  echo "  ✅ Backed up config.yaml"
fi
echo

# ── Step 3: Write custom provider JSON ────────────────────────
echo "Step 3: Write custom provider JSON"
mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_JSON" << JSONEOF
{
  "name": "custom_skupper",
  "engine": "openai",
  "display_name": "Skupper",
  "description": "Skupper VAN to remote GPU model (IBM Granite via vLLM)",
  "api_key_env": "",
  "base_url": "http://localhost:${PORT}",
  "models": [
    {
      "name": "${MODEL_ID}",
      "context_limit": ${CTX},
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 300,
  "supports_streaming": true,
  "requires_auth": false,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": false
}
JSONEOF

echo "  ✅ Written $PROVIDER_JSON"
echo

# ── Step 4: Update config.yaml ────────────────────────────────
echo "Step 4: Update config.yaml"
if grep -q 'custom_skupper:' "$CONFIG_YAML" 2>/dev/null; then
  # Update existing entry
  sed -i "/custom_skupper:/,/configured:/{s/model: .*/model: ${MODEL_ID//\//\\/}/}" "$CONFIG_YAML"
  echo "  ✅ Updated model in config.yaml"
else
  # Add new entry under providers:
  sed -i "/^providers:/a\\  custom_skupper:\n    enabled: true\n    model: ${MODEL_ID}\n    configured: true" "$CONFIG_YAML"
  echo "  ✅ Added custom_skupper to config.yaml"
fi
echo

# ── Step 5: Verify ────────────────────────────────────────────
echo "Step 5: Verify"
echo "  JSON:"
python3 -c "
import json
with open('$PROVIDER_JSON') as f:
    d = json.load(f)
print(f'    base_url: {d[\"base_url\"]}')
print(f'    model:    {d[\"models\"][0][\"name\"]}')
print(f'    context:  {d[\"models\"][0][\"context_limit\"]}')
"

echo "  config.yaml:"
grep -A3 'custom_skupper:' "$CONFIG_YAML" | sed 's/^/    /'
echo

# ── Step 6: Test ──────────────────────────────────────────────
echo "Step 6: Test"
if [[ "$HTTP_CODE" == "200" ]]; then
  RESPONSE=$(curl -s "http://localhost:${PORT}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\": \"${MODEL_ID}\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello\"}], \"max_tokens\": 20}" 2>/dev/null)
  CHAT=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['choices'][0]['message']['content'])" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$CHAT" != "PARSE_ERROR" ]]; then
    echo "  ✅ Chat test: $CHAT"
  else
    echo "  ⚠️  Chat test failed"
  fi
else
  echo "  ⚠️  Skipped (endpoint not responding)"
fi
echo

echo "✅ Goose Skupper Provider configured: $MODEL_ALIAS → localhost:$PORT"
