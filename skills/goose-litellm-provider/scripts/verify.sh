#!/usr/bin/env bash
# verify.sh — Verify Goose LiteLLM provider configuration is complete and aligned
# Usage: bash verify.sh
# Exit codes: 0 = all checks pass, 1 = one or more checks failed
set -euo pipefail

PROVIDER_JSON="$HOME/.config/goose/custom_providers/custom_redhat.json"
CONFIG_YAML="$HOME/.config/goose/config.yaml"
LITELLM_URL="http://127.0.0.1:4000"

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

# S2: Custom provider JSON exists and has required fields
if [[ -f "$PROVIDER_JSON" ]]; then
  check "S2a: custom_redhat.json exists" "PASS"
else
  check "S2a: custom_redhat.json exists" "FAIL"
fi

if [[ -f "$PROVIDER_JSON" ]]; then
  ENGINE=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d.get('engine',''))" 2>/dev/null)
  BASE_URL=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d.get('base_url',''))" 2>/dev/null)
  FAST_MODEL=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(d.get('fast_model') or 'null')" 2>/dev/null)
  MODEL_COUNT=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print(len(d.get('models',[])))" 2>/dev/null)

  [[ "$ENGINE" == "openai" ]] && check "S2b: engine=openai" "PASS" || check "S2b: engine=openai (got: $ENGINE)" "FAIL"
  [[ "$BASE_URL" == "http://localhost:4000" ]] && check "S2c: base_url=http://localhost:4000" "PASS" || check "S2c: base_url=http://localhost:4000 (got: $BASE_URL)" "FAIL"
  [[ "$MODEL_COUNT" -ge 1 ]] && check "S2d: models list non-empty ($MODEL_COUNT models)" "PASS" || check "S2d: models list non-empty" "FAIL"
  [[ "$FAST_MODEL" != "null" ]] && check "S2e: fast_model is set ($FAST_MODEL)" "PASS" || check "S2e: fast_model is set (got: null)" "FAIL"
fi

# S3: config.yaml has custom_redhat with a default model
if [[ -f "$CONFIG_YAML" ]]; then
  if grep -q 'custom_redhat:' "$CONFIG_YAML" 2>/dev/null; then
    check "S3a: custom_redhat in config.yaml" "PASS"
  else
    check "S3a: custom_redhat in config.yaml" "FAIL"
  fi

  # Extract default model using grep/awk (no pyyaml dependency)
  DEFAULT_MODEL=$(awk '/^[[:space:]]+custom_redhat:/{found=1} found && /^[[:space:]]+model:/{print $2; exit}' "$CONFIG_YAML" 2>/dev/null || echo "")

  if [[ -n "$DEFAULT_MODEL" ]]; then
    check "S3b: default model set ($DEFAULT_MODEL)" "PASS"
  else
    check "S3b: default model set" "FAIL"
  fi
else
  check "S3a: config.yaml exists" "FAIL"
fi

# S4: Models in JSON match models served by LiteLLM
if [[ -f "$PROVIDER_JSON" ]]; then
  JSON_MODELS=$(python3 -c "import json; d=json.load(open('$PROVIDER_JSON')); print('\n'.join(sorted(m['name'] for m in d.get('models',[]))))" 2>/dev/null)
  LIVE_MODELS=$(curl -sf "$LITELLM_URL/v1/models" 2>/dev/null | python3 -c "import sys,json; print('\n'.join(sorted(m['id'] for m in json.load(sys.stdin).get('data',[]))))" 2>/dev/null || echo "")

  if [[ -n "$LIVE_MODELS" && "$JSON_MODELS" == "$LIVE_MODELS" ]]; then
    check "S4: Provider JSON models match live LiteLLM models" "PASS"
  elif [[ -z "$LIVE_MODELS" ]]; then
    check "S4: Provider JSON models match live LiteLLM models (proxy unreachable)" "FAIL"
  else
    check "S4: Provider JSON models match live LiteLLM models" "FAIL"
    echo "    JSON models:  $JSON_MODELS"
    echo "    Live models:  $LIVE_MODELS"
  fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
