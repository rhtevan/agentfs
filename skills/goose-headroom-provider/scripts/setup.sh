#!/usr/bin/env bash
# setup.sh — Install/restore Goose custom provider for Headroom proxy
# Usage: setup.sh [--check] [--model MODEL]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-headroom-provider" "1.0.0" 2>/dev/null || true

CHECK_ONLY=false
MODEL="claude-opus-4-6"

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --model) shift; MODEL="${1:-claude-opus-4-6}" ;;
  esac
done

PROVIDER_DIR="${HOME}/.config/goose/custom_providers"
PROVIDER_FILE="${PROVIDER_DIR}/custom_headroom.json"
CONFIG_YAML="${HOME}/.config/goose/config.yaml"
ENV_FILE="${HOME}/.config/goose/.env"
ERRORS=0

echo "=== Goose Headroom Provider Setup ==="
echo ""

# ── Step 1: Check Headroom proxy ────────────────────────────────────────
trace_step 1 "check_headroom_proxy" 0 "" 2>/dev/null || true

if curl -sf http://127.0.0.1:8787/health >/dev/null 2>&1; then
  echo "✓ Headroom proxy is running on :8787"
elif systemctl --user is-active headroom-proxy >/dev/null 2>&1; then
  echo "⚠ Headroom proxy service active but health check failed"
  ERRORS=$((ERRORS + 1))
else
  echo "⚠ Headroom proxy not running (use headroom-litellm-proxy skill to set up)"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Create/verify custom provider JSON ──────────────────────────
trace_step 2 "provider_json" 0 "path=${PROVIDER_FILE}" 2>/dev/null || true

if [[ -f "$PROVIDER_FILE" ]]; then
  echo "✓ Provider JSON exists: $PROVIDER_FILE"
  if grep -q '"custom_headroom"' "$PROVIDER_FILE"; then
    echo "  ✓ Contains custom_headroom provider"
  else
    echo "  ⚠ File exists but may not contain custom_headroom"
    ERRORS=$((ERRORS + 1))
  fi
else
  if $CHECK_ONLY; then
    echo "⚠ Provider JSON not found: $PROVIDER_FILE"
    ERRORS=$((ERRORS + 1))
  else
    mkdir -p "$PROVIDER_DIR"
    cat > "$PROVIDER_FILE" << 'PROVIDER_EOF'
{
  "name": "custom_headroom",
  "engine": "openai",
  "display_name": "Headroom",
  "description": "Headroom context-optimization proxy → LiteLLM (Vertex AI Claude models)",
  "api_key_env": "",
  "base_url": "http://host.containers.internal:8787",
  "models": [
    {
      "name": "claude-opus-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-5",
      "context_limit": 128000,
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
  "fast_model": null,
  "preserves_thinking": true
}
PROVIDER_EOF
    echo "✓ Created provider JSON: $PROVIDER_FILE"
  fi
fi

# ── Step 3: Check/add .env API key ───────────────────────────────────────
trace_step 3 "env_api_key" 0 "path=${ENV_FILE}" 2>/dev/null || true

if [[ -f "$ENV_FILE" ]] && grep -q 'CUSTOM_HEADROOM_API_KEY' "$ENV_FILE"; then
  echo "✓ API key entry exists in .env"
else
  if $CHECK_ONLY; then
    echo "⚠ CUSTOM_HEADROOM_API_KEY not found in .env"
    ERRORS=$((ERRORS + 1))
  else
    echo 'CUSTOM_HEADROOM_API_KEY=sk-EXAMPLE-not-real' >> "$ENV_FILE"
    echo "✓ Added CUSTOM_HEADROOM_API_KEY to .env"
  fi
fi

# ── Step 4: Check config.yaml provider entry ─────────────────────────────
trace_step 4 "config_yaml" 0 "path=${CONFIG_YAML}" 2>/dev/null || true

if [[ -f "$CONFIG_YAML" ]]; then
  if grep -q 'custom_headroom' "$CONFIG_YAML"; then
    echo "✓ custom_headroom found in config.yaml"
    active=$(grep 'active_provider:' "$CONFIG_YAML" | awk '{print $2}')
    echo "  Current active_provider: ${active:-not set}"
  else
    echo "⚠ custom_headroom not found in config.yaml"
    echo "  Add manually or run 'goose configure' to register the provider"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠ config.yaml not found: $CONFIG_YAML"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ Headroom provider is configured."
else
  if $CHECK_ONLY; then
    echo "⚠ ${ERRORS} issue(s) found. Run without --check to apply fixes."
  else
    echo "⚠ Setup completed with ${ERRORS} warning(s). Review above."
  fi
fi

trace_end 2>/dev/null || true
exit $ERRORS
