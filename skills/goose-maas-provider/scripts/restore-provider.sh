#!/usr/bin/env bash
# restore-provider.sh — Restore the MaaS custom provider for Goose
#
# Creates the custom_maas.json provider file and adds the provider
# entry to goose config.yaml. Does NOT store the API key (use
# 'goose configure' for that).
#
# Usage: restore-provider.sh [--url URL] [--model MODEL] [--activate]
#
# Flags:
#   --url URL       Override the MaaS endpoint URL
#   --model MODEL   Override the default model (default: llama-scout-17b)
#   --activate      Set custom_maas as the active provider in config.yaml
#
# Exit codes:
#   0 — Provider restored successfully
#   1 — Error during restoration

set -euo pipefail

MAAS_URL="https://maas-rhdp.apps.maas.redhatworkshops.io"
DEFAULT_MODEL="llama-scout-17b"
ACTIVATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MAAS_URL="$2"; shift 2 ;;
    --model) DEFAULT_MODEL="$2"; shift 2 ;;
    --activate) ACTIVATE=true; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_maas.json"
CONFIG_FILE="$HOME/.config/goose/config.yaml"

echo "MaaS Provider Restore"
echo "═════════════════════"
echo "URL:     $MAAS_URL"
echo "Model:   $DEFAULT_MODEL"
echo ""

# Step 1: Create provider JSON
mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_FILE" << PROVIDER_EOF
{
  "name": "custom_maas",
  "engine": "openai",
  "display_name": "MaaS",
  "description": "Custom MaaS provider",
  "api_key_env": "CUSTOM_MAAS_API_KEY",
  "base_url": "$MAAS_URL",
  "models": [
    {
      "name": "llama-scout-17b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "gpt-oss-120b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "qwen3-14b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "qwen36-35b-a3b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "deepseek-r1-distill-qwen-14b",
      "context_limit": 128000,
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
  "requires_auth": true,
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
PROVIDER_EOF

echo "1. ✅ Provider JSON written to: $PROVIDER_FILE"

# Step 2: Add provider entry to config.yaml if not present
if [[ -f "$CONFIG_FILE" ]]; then
  if ! grep -q 'custom_maas:' "$CONFIG_FILE" 2>/dev/null; then
    if grep -q '^providers:' "$CONFIG_FILE"; then
      sed -i '/^providers:/a\  custom_maas:\n    enabled: true\n    model: '"$DEFAULT_MODEL"'\n    configured: true' "$CONFIG_FILE"
    else
      echo -e "\nproviders:\n  custom_maas:\n    enabled: true\n    model: $DEFAULT_MODEL\n    configured: true" >> "$CONFIG_FILE"
    fi
    echo "2. ✅ Provider entry added to config.yaml"
  else
    echo "2. ✅ Provider entry already exists in config.yaml"
  fi
else
  echo "2. ⚠️  config.yaml not found at $CONFIG_FILE — create it manually"
fi

# Step 3: Ensure GOOSE_TOOLSHIM is set
if [[ -f "$CONFIG_FILE" ]]; then
  if ! grep -q 'GOOSE_TOOLSHIM: true' "$CONFIG_FILE" 2>/dev/null; then
    echo "GOOSE_TOOLSHIM: true" >> "$CONFIG_FILE"
    echo "3. ✅ GOOSE_TOOLSHIM: true added to config.yaml"
  else
    echo "3. ✅ GOOSE_TOOLSHIM already enabled"
  fi
fi

# Step 4: Activate if requested
if [[ "$ACTIVATE" == "true" && -f "$CONFIG_FILE" ]]; then
  if grep -q '^active_provider:' "$CONFIG_FILE"; then
    sed -i 's/^active_provider:.*/active_provider: custom_maas/' "$CONFIG_FILE"
  else
    echo "active_provider: custom_maas" >> "$CONFIG_FILE"
  fi
  echo "4. ✅ Active provider set to custom_maas"
fi

echo ""
echo "═════════════════════"
echo "✅ Provider restored"
echo ""
echo "Next steps:"
echo "  1. Run 'goose configure' → Configure Providers → MaaS to store API key"
echo "  2. Restart Goose Desktop (if using Desktop)"
