#!/usr/bin/env bash
# restore.sh — Restore/update the LiteLLM Vertex AI provider in Hermes config
# Usage: bash restore.sh [--default-model MODEL]
# Exit codes: 0 = success, 1 = failure, 2 = usage error
#
# This script surgically updates only the model: and providers.litellm-vertex-ai:
# sections in ~/.hermes/config.yaml. All other settings are preserved.
set -euo pipefail

DEFAULT_MODEL="claude-opus-4-6"
LITELLM_URL="http://127.0.0.1:4000"
PROVIDER_NAME="litellm-vertex-ai"
HERMES_CONFIG="$HOME/.hermes/config.yaml"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --default-model) DEFAULT_MODEL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash restore.sh [--default-model MODEL]"
      echo "  --default-model MODEL  Default model for conversation (default: claude-opus-4-6)"
      echo ""
      echo "Discovers models from LiteLLM proxy at $LITELLM_URL"
      echo "Updates only model: and providers.$PROVIDER_NAME: sections in config.yaml"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

# Pre-flight: check proxy is reachable
if ! curl -sf "$LITELLM_URL/health" &>/dev/null; then
  echo "❌ LiteLLM proxy not reachable at $LITELLM_URL"
  echo "   Start it with: systemctl --user start litellm-proxy"
  exit 1
fi

# Discover models from live proxy
MODELS=$(curl -sf "$LITELLM_URL/v1/models" | python3 -c "
import sys, json
data = json.load(sys.stdin).get('data', [])
for m in sorted(data, key=lambda x: x['id']):
    print(m['id'])
" 2>/dev/null)

if [[ -z "$MODELS" ]]; then
  echo "❌ No models discovered from $LITELLM_URL/v1/models"
  exit 1
fi

echo "Discovered models:"
echo "$MODELS" | sed 's/^/  - /'
echo ""

# Validate default model is in the discovered list
if ! echo "$MODELS" | grep -qx "$DEFAULT_MODEL"; then
  echo "⚠️  Default model '$DEFAULT_MODEL' not found in proxy models."
  echo "   Available: $(echo $MODELS | tr '\n' ', ')"
  echo "   Using first available model instead."
  DEFAULT_MODEL=$(echo "$MODELS" | head -1)
fi

# Build the models hash (YAML format)
MODELS_YAML=$(echo "$MODELS" | while read -r m; do echo "      $m: {}"; done)

# Key env name (Hermes convention)
KEY_ENV="HERMES_CUSTOM_$(echo "$PROVIDER_NAME" | tr '[:lower:]-' '[:upper:]_')_API_KEY"

if [[ ! -f "$HERMES_CONFIG" ]]; then
  echo "❌ $HERMES_CONFIG not found. Run 'hermes model' first to create initial config."
  exit 1
fi

# Backup
BACKUP="${HERMES_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
cp "$HERMES_CONFIG" "$BACKUP"
echo "📋 Backup: $BACKUP"

# Use Python to surgically update only the relevant sections
python3 << PYEOF
import yaml, sys

config_path = "$HERMES_CONFIG"
default_model = "$DEFAULT_MODEL"
provider_name = "$PROVIDER_NAME"
litellm_url = "$LITELLM_URL"
key_env = "$KEY_ENV"
models = """$MODELS""".strip().split('\n')

with open(config_path) as f:
    config = yaml.safe_load(f)

# Update model: section
config['model'] = {
    'base_url': f'{litellm_url}/v1',
    'default': default_model,
    'provider': provider_name,
    'key_env': key_env,
}

# Update providers.<name>: section (preserve other providers)
if 'providers' not in config:
    config['providers'] = {}

config['providers'][provider_name] = {
    'api': f'{litellm_url}/v1',
    'name': 'LiteLLM Vertex AI',
    'discover_models': True,
    'default_model': default_model,
    'base_url': f'{litellm_url}/v1',
    'model': default_model,
    'models': {m: {} for m in models},
    'key_env': key_env,
}

with open(config_path, 'w') as f:
    yaml.dump(config, f, default_flow_style=False, sort_keys=False)

print(f'✅ Updated model: and providers.{provider_name}: in {config_path}')
print(f'   default_model: {default_model}')
print(f'   models: {", ".join(models)}')
PYEOF
