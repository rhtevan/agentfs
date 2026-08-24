#!/usr/bin/env bash
# verify.sh — Verify DSH LiteLLM provider configuration
# Usage: bash verify.sh
set -euo pipefail

DSH_HOME="${DSH_HOME:-$HOME/.dsh}"
SETTINGS="$DSH_HOME/settings.yaml"
LITELLM_URL="http://127.0.0.1:4000"
PROVIDER_ID="litellm-vertex-ai"

passed=0
failed=0

check() {
  local label="$1" result="$2"
  if [[ "$result" == ok* ]]; then
    echo "  ✅ $label"
    passed=$((passed + 1)) || true
  else
    echo "  ❌ $label — $result"
    failed=$((failed + 1)) || true
  fi
}

echo "=== DSH LiteLLM Provider Verification ==="
echo ""

# --- Settings file exists ---
if [[ -f "$SETTINGS" ]]; then
  check "Settings file ($SETTINGS)" "ok"
else
  check "Settings file" "$SETTINGS not found"
  echo ""
  echo "=== Results: $passed passed, $failed failed ==="
  exit 1
fi

# --- Provider block exists ---
if grep -q "$PROVIDER_ID:" "$SETTINGS" 2>/dev/null; then
  check "Provider block ($PROVIDER_ID)" "ok"
else
  check "Provider block" "$PROVIDER_ID not found in settings"
fi

# --- Base URL correct ---
if grep -q "baseURL:.*127\.0\.0\.1:4000" "$SETTINGS" 2>/dev/null; then
  check "Base URL" "ok"
else
  check "Base URL" "expected 127.0.0.1:4000"
fi

# --- API type ---
if grep -q "api: openai-completions" "$SETTINGS" 2>/dev/null; then
  check "API protocol" "ok"
else
  check "API protocol" "expected openai-completions"
fi

# --- Compat flags ---
if grep -q "supportsDeveloperRole: false" "$SETTINGS" 2>/dev/null; then
  check "supportsDeveloperRole flag" "ok"
else
  check "supportsDeveloperRole flag" "not set to false"
fi

if grep -q "maxTokensField: max_tokens" "$SETTINGS" 2>/dev/null; then
  check "maxTokensField flag" "ok"
else
  check "maxTokensField flag" "not set to max_tokens"
fi

# --- Models present ---
MODEL_COUNT=$(grep -c 'id: claude-' "$SETTINGS" 2>/dev/null || echo 0)
if [[ "$MODEL_COUNT" -gt 0 ]]; then
  check "Models configured" "ok ($MODEL_COUNT models)"
else
  check "Models configured" "no claude models found"
fi

# --- LiteLLM proxy reachable ---
if curl -s --connect-timeout 3 "$LITELLM_URL/health" >/dev/null 2>&1; then
  check "LiteLLM proxy reachable" "ok"
else
  check "LiteLLM proxy reachable" "not responding at $LITELLM_URL"
fi

# --- Cross-check: models in settings match running LiteLLM ---
if curl -s --connect-timeout 3 "$LITELLM_URL/v1/models" >/dev/null 2>&1; then
  LIVE_MODELS=$(curl -s "$LITELLM_URL/v1/models" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('data', []):
    print(m['id'])
" 2>/dev/null | sort)

  SETTINGS_MODELS=$(grep 'id:' "$SETTINGS" 2>/dev/null | sed 's/.*id: //' | sort)

  MISSING=$(comm -23 <(echo "$LIVE_MODELS") <(echo "$SETTINGS_MODELS") 2>/dev/null)
  if [[ -z "$MISSING" ]]; then
    check "Model sync (LiteLLM ↔ settings)" "ok"
  else
    check "Model sync" "models in LiteLLM but not in settings: $MISSING"
  fi
fi

# --- Backup exists ---
if [[ -f "$SETTINGS.bak" ]]; then
  echo "  ℹ️  Backup: $SETTINGS.bak"
fi

echo ""
echo "=== Results: $passed passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
