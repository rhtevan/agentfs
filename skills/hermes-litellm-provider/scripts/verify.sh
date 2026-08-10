#!/usr/bin/env bash
# verify.sh — Verify Hermes LiteLLM provider configuration is complete and aligned
# Usage: bash verify.sh
# Exit codes: 0 = all checks pass, 1 = one or more checks failed
set -euo pipefail

HERMES_CONFIG="$HOME/.hermes/config.yaml"
LITELLM_URL="http://127.0.0.1:4000"
PROVIDER_NAME="litellm-vertex-ai"

PASS=0
FAIL=0

check() {
  local label="$1" status="$2"
  if [[ "$status" == "PASS" ]]; then
    echo "✅ $label"
    PASS=$((PASS + 1))
  else
    echo "❌ $label"
    FAIL=$((FAIL + 1))
  fi
}

# S1: LiteLLM proxy is running and healthy
if systemctl --user is-active litellm-proxy &>/dev/null; then
  check "S1a: litellm-proxy service active" "PASS"
else
  check "S1a: litellm-proxy service active" "FAIL"
fi

HEALTH=$(curl -sf "$LITELLM_URL/health" 2>/dev/null || echo '{}')
UNHEALTHY=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('unhealthy_count',1))" 2>/dev/null || echo "1")
if [[ "$UNHEALTHY" == "0" ]]; then
  check "S1b: All LiteLLM endpoints healthy" "PASS"
else
  check "S1b: All LiteLLM endpoints healthy" "FAIL"
fi

# S2: Hermes config.yaml exists and has litellm-vertex-ai provider
if [[ -f "$HERMES_CONFIG" ]]; then
  check "S2a: ~/.hermes/config.yaml exists" "PASS"
else
  check "S2a: ~/.hermes/config.yaml exists" "FAIL"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Results: $PASS passed, $FAIL failed"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi

# Check model.provider
MODEL_PROVIDER=$(awk '/^model:/{found=1} found && /^  provider:/{print $2; exit}' "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ "$MODEL_PROVIDER" == "$PROVIDER_NAME" ]]; then
  check "S2b: model.provider=$PROVIDER_NAME" "PASS"
else
  check "S2b: model.provider=$PROVIDER_NAME (got: $MODEL_PROVIDER)" "FAIL"
fi

# Check model.base_url
MODEL_BASE_URL=$(awk '/^model:/{found=1} found && /^  base_url:/{print $2; exit}' "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ "$MODEL_BASE_URL" == "$LITELLM_URL/v1" ]]; then
  check "S2c: model.base_url=$LITELLM_URL/v1" "PASS"
else
  check "S2c: model.base_url=$LITELLM_URL/v1 (got: $MODEL_BASE_URL)" "FAIL"
fi

# Check model.default
MODEL_DEFAULT=$(awk '/^model:/{found=1} found && /^  default:/{print $2; exit}' "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ -n "$MODEL_DEFAULT" ]]; then
  check "S2d: model.default set ($MODEL_DEFAULT)" "PASS"
else
  check "S2d: model.default set" "FAIL"
fi

# S3: Provider entry exists with correct fields
PROVIDER_BASE_URL=$(awk "/^  $PROVIDER_NAME:/{found=1} found && /^    base_url:/{print \$2; exit}" "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ "$PROVIDER_BASE_URL" == "$LITELLM_URL/v1" ]]; then
  check "S3a: providers.$PROVIDER_NAME.base_url=$LITELLM_URL/v1" "PASS"
else
  check "S3a: providers.$PROVIDER_NAME.base_url (got: $PROVIDER_BASE_URL)" "FAIL"
fi

PROVIDER_DISCOVER=$(awk "/^  $PROVIDER_NAME:/{found=1} found && /^    discover_models:/{print \$2; exit}" "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ "$PROVIDER_DISCOVER" == "true" ]]; then
  check "S3b: discover_models=true" "PASS"
else
  check "S3b: discover_models=true (got: $PROVIDER_DISCOVER)" "FAIL"
fi

PROVIDER_DEFAULT_MODEL=$(awk "/^  $PROVIDER_NAME:/{found=1} found && /^    default_model:/{print \$2; exit}" "$HERMES_CONFIG" 2>/dev/null || echo "")
if [[ -n "$PROVIDER_DEFAULT_MODEL" ]]; then
  check "S3c: providers.$PROVIDER_NAME.default_model set ($PROVIDER_DEFAULT_MODEL)" "PASS"
else
  check "S3c: providers.$PROVIDER_NAME.default_model set" "FAIL"
fi

# Check consistency: model.default == provider.default_model
if [[ -n "$MODEL_DEFAULT" && -n "$PROVIDER_DEFAULT_MODEL" && "$MODEL_DEFAULT" == "$PROVIDER_DEFAULT_MODEL" ]]; then
  check "S3d: model.default matches providers.$PROVIDER_NAME.default_model" "PASS"
else
  check "S3d: model.default ($MODEL_DEFAULT) matches providers.$PROVIDER_NAME.default_model ($PROVIDER_DEFAULT_MODEL)" "FAIL"
fi

# S4: Config models match live LiteLLM models
# Extract model names from the providers.<name>.models: hash keys
CONFIG_MODELS=$(awk "/^  $PROVIDER_NAME:/{found=1} found && /^    models:/{m=1; next} m && /^      [a-z]/{gsub(/:.*/, \"\"); print \$1} m && /^    [a-z]/ && !/^      /{m=0}" "$HERMES_CONFIG" 2>/dev/null | sort)
LIVE_MODELS=$(curl -sf "$LITELLM_URL/v1/models" 2>/dev/null | python3 -c "import sys,json; print('\n'.join(sorted(m['id'] for m in json.load(sys.stdin).get('data',[]))))" 2>/dev/null || echo "")

if [[ -n "$LIVE_MODELS" && "$CONFIG_MODELS" == "$LIVE_MODELS" ]]; then
  check "S4: Config models match live LiteLLM models" "PASS"
elif [[ -z "$LIVE_MODELS" ]]; then
  check "S4: Config models match live LiteLLM models (proxy unreachable)" "FAIL"
else
  check "S4: Config models match live LiteLLM models" "FAIL"
  echo "    Config models: $(echo $CONFIG_MODELS | tr '\n' ', ')"
  echo "    Live models:   $(echo $LIVE_MODELS | tr '\n' ', ')"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
