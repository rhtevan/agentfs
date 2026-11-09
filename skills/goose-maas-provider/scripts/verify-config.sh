#!/usr/bin/env bash
# verify-config.sh — Verify MaaS provider configuration completeness
#
# Checks all configuration requirements from the verification checklist.
#
# Usage: verify-config.sh
#
# Exit codes:
#   0 — All checks pass
#   1 — One or more checks failed

set -euo pipefail

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_maas.json"
CONFIG_FILE="$HOME/.config/goose/config.yaml"

PASS=0
FAIL=0
WARN=0

check_pass() { echo "  ✅ $1"; ((PASS++)); }
check_fail() { echo "  ❌ $1"; ((FAIL++)); }
check_warn() { echo "  ⚠️  $1"; ((WARN++)); }

echo "MaaS Provider Configuration Verification"
echo "═════════════════════════════════════════"
echo ""

# 1. Provider JSON exists
if [[ -f "$PROVIDER_FILE" ]]; then
  check_pass "custom_maas.json exists"
else
  check_fail "custom_maas.json NOT FOUND at $PROVIDER_FILE"
fi

# 2. Provider JSON content checks (if file exists)
if [[ -f "$PROVIDER_FILE" ]]; then
  # Default model check
  if python3 -c "
import json
with open('$PROVIDER_FILE') as f:
    d = json.load(f)
models = [m['name'] for m in d.get('models',[])]
if 'llama-scout-17b' in models:
    exit(0)
exit(1)
" 2>/dev/null; then
    check_pass "llama-scout-17b in model list"
  else
    check_fail "llama-scout-17b NOT in model list"
  fi

  # reasoning: false on all models
  reasoning_true=$(python3 -c "
import json
with open('$PROVIDER_FILE') as f:
    d = json.load(f)
count = sum(1 for m in d.get('models',[]) if m.get('reasoning') == True)
print(count)
" 2>/dev/null || echo "?")
  if [[ "$reasoning_true" == "0" ]]; then
    check_pass "reasoning: false on all models"
  else
    check_fail "$reasoning_true model(s) have reasoning: true"
  fi

  # preserves_thinking: false
  pt=$(python3 -c "
import json
with open('$PROVIDER_FILE') as f:
    d = json.load(f)
print(d.get('preserves_thinking', 'missing'))
" 2>/dev/null || echo "?")
  if [[ "$pt" == "False" ]]; then
    check_pass "preserves_thinking: false"
  else
    check_fail "preserves_thinking is $pt (expected false)"
  fi

  # timeout_seconds
  timeout=$(python3 -c "
import json
with open('$PROVIDER_FILE') as f:
    d = json.load(f)
print(d.get('timeout_seconds', 'null'))
" 2>/dev/null || echo "?")
  if [[ "$timeout" =~ ^[0-9]+$ && "$timeout" -ge 60 ]]; then
    check_pass "timeout_seconds: $timeout"
  else
    check_warn "timeout_seconds: $timeout (recommend ≥60)"
  fi
fi

# 3. config.yaml checks
if [[ -f "$CONFIG_FILE" ]]; then
  check_pass "config.yaml exists"

  # custom_maas in providers
  if grep -q 'custom_maas:' "$CONFIG_FILE" 2>/dev/null; then
    check_pass "custom_maas in providers section"
  else
    check_fail "custom_maas NOT in providers section"
  fi

  # enabled: true
  if grep -A3 'custom_maas:' "$CONFIG_FILE" 2>/dev/null | grep -q 'enabled: true'; then
    check_pass "custom_maas enabled: true"
  else
    check_warn "custom_maas may not be enabled"
  fi

  # model setting
  model=$(grep -A3 'custom_maas:' "$CONFIG_FILE" 2>/dev/null | grep 'model:' | head -1 | awk '{print $2}')
  if [[ -n "$model" ]]; then
    if [[ "$model" == "llama-scout-17b" ]]; then
      check_pass "Default model: $model (recommended)"
    else
      check_warn "Default model: $model (llama-scout-17b recommended for Goose compatibility)"
    fi
  else
    check_fail "No model configured for custom_maas"
  fi

  # GOOSE_TOOLSHIM
  if grep -q 'GOOSE_TOOLSHIM: true' "$CONFIG_FILE" 2>/dev/null; then
    check_pass "GOOSE_TOOLSHIM: true"
  else
    check_fail "GOOSE_TOOLSHIM not set (required for tool calls with MaaS models)"
  fi

  # active_provider check
  active=$(grep '^active_provider:' "$CONFIG_FILE" 2>/dev/null | awk '{print $2}')
  if [[ "$active" == "custom_maas" ]]; then
    check_pass "Active provider: custom_maas"
  else
    check_warn "Active provider: ${active:-not set} (custom_maas not active)"
  fi
else
  check_fail "config.yaml NOT FOUND at $CONFIG_FILE"
fi

# 4. API key in keyring
if command -v secret-tool &>/dev/null; then
  if secret-tool search service goose 2>/dev/null | grep -q 'CUSTOM_MAAS'; then
    check_pass "API key found in GNOME Keyring"
  else
    check_warn "API key not found in GNOME Keyring — run 'goose configure' to store"
  fi
else
  check_warn "secret-tool not available — cannot verify keyring"
fi

echo ""
echo "═════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
[[ "$FAIL" -eq 0 ]] && echo "✅ Configuration complete" || echo "❌ Configuration incomplete — fix failed checks"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
