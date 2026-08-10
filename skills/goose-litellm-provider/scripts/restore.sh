#!/usr/bin/env bash
# restore.sh — Restore the RedHat custom provider for Goose
# Usage: bash restore.sh [--fast-model MODEL] [--default-model MODEL]
# Exit codes: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

FAST_MODEL="claude-haiku-4-5"
DEFAULT_MODEL="claude-opus-4-6"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fast-model)   FAST_MODEL="$2"; shift 2 ;;
    --default-model) DEFAULT_MODEL="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash restore.sh [--fast-model MODEL] [--default-model MODEL]"
      echo "  --fast-model   MODEL  Fast model for auxiliary calls (default: claude-haiku-4-5)"
      echo "  --default-model MODEL Default model for conversation (default: claude-opus-4-6)"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_redhat.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"

mkdir -p "$PROVIDER_DIR"

# Write the custom provider JSON
cat > "$PROVIDER_FILE" << EOF
{
  "name": "custom_redhat",
  "engine": "openai",
  "display_name": "RedHat",
  "description": "Local LiteLLM proxy to Vertex AI (Claude models)",
  "api_key_env": "",
  "base_url": "http://localhost:4000",
  "models": [
    {
      "name": "claude-opus-4-6",
      "context_limit": 1000000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-6",
      "context_limit": 1000000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-haiku-4-5",
      "context_limit": 200000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 600,
  "supports_streaming": true,
  "requires_auth": false,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": "$FAST_MODEL",
  "preserves_thinking": true
}
EOF

echo "✅ Custom provider JSON written to: $PROVIDER_FILE"
echo "   fast_model: $FAST_MODEL"

# Check if config.yaml needs the provider entry
if [[ -f "$CONFIG_YAML" ]]; then
  if grep -q 'custom_redhat:' "$CONFIG_YAML" 2>/dev/null; then
    echo "✅ config.yaml already has custom_redhat entry"
  else
    echo ""
    echo "⚠️  config.yaml does not have a custom_redhat entry."
    echo "   Add the following under 'providers:' in $CONFIG_YAML:"
    echo ""
    echo "  custom_redhat:"
    echo "    enabled: true"
    echo "    model: $DEFAULT_MODEL"
    echo "    configured: true"
    echo ""
    echo "   And set:"
    echo "   active_provider: custom_redhat"
  fi
else
  echo ""
  echo "⚠️  $CONFIG_YAML not found."
  echo "   Run 'goose configure' to create initial configuration."
fi

echo ""
echo "Default model (set in config.yaml): $DEFAULT_MODEL"
echo "Fast model (set in provider JSON):  $FAST_MODEL"
