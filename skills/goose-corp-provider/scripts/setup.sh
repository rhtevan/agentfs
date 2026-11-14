#!/usr/bin/env bash
# setup.sh — Create Corp custom provider JSON and config.yaml entry
# Usage: bash setup.sh --model MODEL_ID [--force]
set -euo pipefail

source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "setup" 2>/dev/null || true

MODEL=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --force) FORCE=true; shift ;;
    *) echo "Usage: setup.sh --model MODEL_ID [--force]" >&2; exit 2 ;;
  esac
done

[[ -z "$MODEL" ]] && { echo "ERROR: --model is required" >&2; exit 2; }

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="${PROVIDER_DIR}/custom_corp.json"
CONFIG_FILE="$HOME/.config/goose/config.yaml"

trace_step "backup" "Backing up existing files" 2>/dev/null || true

mkdir -p "$PROVIDER_DIR"

if [[ -f "$PROVIDER_FILE" && "$FORCE" != "true" ]]; then
  BACKUP="${PROVIDER_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$PROVIDER_FILE" "$BACKUP"
  echo "⚠️  Backed up existing provider to: $BACKUP"
fi

trace_step "probe" "Fetching available models for provider JSON" 2>/dev/null || true

HOST="https://models.corp.redhat.com"
RESPONSE=$(curl -s --connect-timeout 10 "${HOST}/oai/v1/models" 2>/dev/null || echo '{"data":[]}')

# Filter to chat-capable models
MODELS_JSON=$(echo "$RESPONSE" | jq '[
  .data[]
  | select((.id | test("embed|rerank|guardian|parse|diffusion"; "i")) | not)
  | {
      name: .id,
      context_limit: 128000,
      input_token_cost: null,
      output_token_cost: null,
      currency: null,
      supports_cache_control: null,
      reasoning: false
    }
] | sort_by(.name)')

MODEL_COUNT=$(echo "$MODELS_JSON" | jq 'length')

if [[ "$MODEL_COUNT" -eq 0 ]]; then
  echo "❌ No chat models found on Corp endpoint."
  trace_end 1 2>/dev/null || true
  exit 1
fi

# Verify chosen default model exists
MODEL_EXISTS=$(echo "$MODELS_JSON" | jq --arg m "$MODEL" '[.[] | select(.name == $m)] | length')
if [[ "$MODEL_EXISTS" -eq 0 ]]; then
  echo "❌ Model '$MODEL' not found on Corp endpoint."
  echo "   Available chat models:"
  echo "$MODELS_JSON" | jq -r '.[].name' | sed 's/^/     /'
  trace_end 1 2>/dev/null || true
  exit 1
fi

trace_step "write-json" "Writing custom_corp.json" 2>/dev/null || true

cat > "$PROVIDER_FILE" <<ENDJSON
{
  "name": "custom_corp",
  "engine": "openai",
  "display_name": "Corp",
  "description": "Red Hat Corp model service (models.corp.redhat.com)",
  "api_key_env": "CUSTOM_CORP_API_KEY",
  "base_url": "https://models.corp.redhat.com/oai/v1",
  "models": $(echo "$MODELS_JSON" | jq '.'),
  "headers": null,
  "timeout_seconds": 300,
  "supports_streaming": true,
  "requires_auth": true,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": true
}
ENDJSON

if ! jq empty "$PROVIDER_FILE" 2>/dev/null; then
  echo "❌ Generated JSON is invalid."
  trace_end 1 2>/dev/null || true
  exit 1
fi

echo "✅ Wrote $PROVIDER_FILE ($MODEL_COUNT chat models)"

trace_step "config-yaml" "Patching config.yaml" 2>/dev/null || true

if grep -q "custom_corp:" "$CONFIG_FILE" 2>/dev/null; then
  echo "⚠️  custom_corp already exists in config.yaml — not modified"
else
  python3 -c "
import yaml, sys

config_path = '$CONFIG_FILE'
with open(config_path, 'r') as f:
    config = yaml.safe_load(f)

if 'providers' not in config:
    config['providers'] = {}

config['providers']['custom_corp'] = {
    'enabled': True,
    'model': '$MODEL',
    'configured': True
}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)
"
  echo "✅ Added custom_corp to config.yaml (default model: $MODEL)"
fi

echo ""
echo "✅ Corp provider setup complete."
echo "   Next: run 'goose configure' → Configure Providers → Corp to store your API key."

trace_end 0 2>/dev/null || true
