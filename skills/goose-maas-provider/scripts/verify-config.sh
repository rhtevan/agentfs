#!/usr/bin/env bash
# verify-config.sh — Verify MaaS provider configuration completeness
#
# Usage: verify-config.sh
# Env:   GOOSE_CONFIG_DIR (default ~/.config/goose)
#
# Read-only. Never prints the API key. GOOSE_TOOLSHIM is NOT required (1.6.0):
# it is a global, experimental setting that needs a separate interpreter model.
#
# Exit codes:
#   0 — All checks pass (warnings allowed)
#   1 — One or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
PROVIDER_FILE="$GOOSE_CONFIG_DIR/custom_providers/custom_maas.json"
CONFIG_FILE="$GOOSE_CONFIG_DIR/config.yaml"

PASS=0
FAIL=0
WARN=0

check_pass() { echo "  ✅ $1"; PASS=$((PASS+1)); }
check_fail() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }
check_warn() { echo "  ⚠️  $1"; WARN=$((WARN+1)); }

echo "MaaS Provider Configuration Verification"
echo "═════════════════════════════════════════"
echo ""

# 1. config.yaml entry (read first: the default model is checked against the JSON)
CFG_MODEL=""
CFG_ENABLED=""
ACTIVE=""
if [[ -f "$CONFIG_FILE" ]]; then
  check_pass "config.yaml exists"
  read -r CFG_ENABLED CFG_MODEL ACTIVE < <(CFG="$CONFIG_FILE" python3 -c '
import os, yaml
c = yaml.safe_load(open(os.environ["CFG"])) or {}
p = (c.get("providers") or {}).get("custom_maas")
if p is None:
    print("__NONE__ - %s" % (c.get("active_provider") or "-"))
else:
    print(str(p.get("enabled")).lower(), p.get("model") or "-", c.get("active_provider") or "-")
' 2>/dev/null || echo "__ERR__ - -")
  case "$CFG_ENABLED" in
    __ERR__)  check_fail "config.yaml could not be parsed" ;;
    __NONE__) check_fail "providers.custom_maas NOT in config.yaml — run restore-provider.sh" ;;
    true)     check_pass "providers.custom_maas enabled: true" ;;
    *)        check_warn "providers.custom_maas enabled: $CFG_ENABLED" ;;
  esac
  [[ "$CFG_MODEL" == "-" ]] && CFG_MODEL=""
  if [[ "$CFG_ENABLED" != __NONE__ && "$CFG_ENABLED" != __ERR__ ]]; then
    if [[ -n "$CFG_MODEL" ]]; then check_pass "Default model: $CFG_MODEL"; else check_fail "No model configured for custom_maas"; fi
  fi
  if [[ "$ACTIVE" == "custom_maas" ]]; then
    check_pass "Active provider: custom_maas"
  else
    check_warn "Active provider: ${ACTIVE/#-/not set} (custom_maas not active — fine if you switch per session)"
  fi
else
  check_fail "config.yaml NOT FOUND at $CONFIG_FILE"
fi

# 2. Provider JSON
if [[ -f "$PROVIDER_FILE" ]]; then
  check_pass "custom_maas.json exists"
  if ! jq empty "$PROVIDER_FILE" 2>/dev/null; then
    check_fail "custom_maas.json is not valid JSON"
  else
    n=$(jq '.models | length' "$PROVIDER_FILE")
    if [[ "$n" -gt 0 ]]; then check_pass "$n model(s) listed"; else check_fail "no models listed"; fi
    if [[ -n "$CFG_MODEL" ]]; then
      if jq -e --arg m "$CFG_MODEL" '[.models[].name] | index($m) != null' "$PROVIDER_FILE" >/dev/null; then
        check_pass "Default model $CFG_MODEL is in the model list"
      else
        check_fail "Default model $CFG_MODEL is NOT in the model list"
      fi
    fi
    rt=$(jq '[.models[] | select(.reasoning == true)] | length' "$PROVIDER_FILE")
    if [[ "$rt" == "0" ]]; then check_pass "reasoning: false on all models"; else check_fail "$rt model(s) have reasoning: true"; fi
    pt=$(jq -r '.preserves_thinking' "$PROVIDER_FILE")
    if [[ "$pt" == "false" ]]; then check_pass "preserves_thinking: false"; else check_fail "preserves_thinking is $pt (expected false)"; fi
    to=$(jq -r '.timeout_seconds // "null"' "$PROVIDER_FILE")
    if [[ "$to" =~ ^[0-9]+$ && "$to" -ge 60 ]]; then check_pass "timeout_seconds: $to"; else check_warn "timeout_seconds: $to (recommend ≥60)"; fi
    ak=$(jq -r '.api_key_env' "$PROVIDER_FILE")
    if [[ "$ak" == "CUSTOM_MAAS_API_KEY" ]]; then check_pass "api_key_env: CUSTOM_MAAS_API_KEY"; else check_fail "api_key_env is $ak (expected CUSTOM_MAAS_API_KEY)"; fi
  fi
else
  check_fail "custom_maas.json NOT FOUND at $PROVIDER_FILE"
fi

# 3. Informational: GOOSE_TOOLSHIM (global; not required)
if [[ -f "$CONFIG_FILE" ]] && grep -q '^GOOSE_TOOLSHIM:' "$CONFIG_FILE"; then
  check_warn "GOOSE_TOOLSHIM is set globally — it affects every provider and needs an interpreter model (Ollama). Not required for MaaS."
fi

# 4. API key in keyring (lock-aware, value never printed)
if command -v secret-tool &>/dev/null && command -v gdbus &>/dev/null; then
  rc=0; KEY=$(keyring_get CUSTOM_MAAS_API_KEY) || rc=$?
  if [[ $rc -eq 0 ]]; then
    check_pass "CUSTOM_MAAS_API_KEY in GNOME Keyring (${#KEY} chars)"
  elif [[ $rc -eq 1 ]]; then
    check_warn "CUSTOM_MAAS_API_KEY not in GNOME Keyring — run store-key.sh (your own terminal) or goose configure → MaaS"
  else
    check_warn "$(keyring_explain "$rc" CUSTOM_MAAS_API_KEY)"
  fi
  unset KEY
else
  check_warn "secret-tool/gdbus not available — cannot verify keyring"
fi

echo ""
echo "═════════════════════════════════════════"
echo "Results: $PASS passed, $FAIL failed, $WARN warnings"
if [[ "$FAIL" -eq 0 ]]; then
  echo "✅ Configuration complete"
  exit 0
fi
echo "❌ Configuration incomplete — fix failed checks"
exit 1
