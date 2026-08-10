#!/usr/bin/env bash
# verify.sh — Verify LiteLLM Vertex AI proxy is running and configured correctly
# Usage: bash verify.sh
# Exit codes: 0 = all checks pass, 1 = one or more checks failed
set -euo pipefail

LITELLM_URL="http://127.0.0.1:4000"
CONFIG_FILE="$HOME/.config/litellm/config.yaml"
SERVICE_FILE="$HOME/.config/systemd/user/litellm-proxy.service"

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

# S1: systemd service exists and is active
if [[ -f "$SERVICE_FILE" ]]; then
  check "S1a: systemd service file exists" "PASS"
else
  check "S1a: systemd service file exists" "FAIL"
fi

if systemctl --user is-active litellm-proxy &>/dev/null; then
  check "S1b: litellm-proxy service active" "PASS"
else
  check "S1b: litellm-proxy service active" "FAIL"
fi

if systemctl --user is-enabled litellm-proxy &>/dev/null; then
  check "S1c: litellm-proxy service enabled (auto-start)" "PASS"
else
  check "S1c: litellm-proxy service enabled (auto-start)" "FAIL"
fi

# S2: Config file exists and has model_list
if [[ -f "$CONFIG_FILE" ]]; then
  check "S2a: config.yaml exists" "PASS"
else
  check "S2a: config.yaml exists" "FAIL"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  MODEL_COUNT=$(grep -c 'model_name:' "$CONFIG_FILE" 2>/dev/null || echo "0")
  if [[ "$MODEL_COUNT" -ge 1 ]]; then
    check "S2b: config has $MODEL_COUNT model(s)" "PASS"
  else
    check "S2b: config has models" "FAIL"
  fi

  # Check vertex_location is explicit (not global)
  if grep -q 'vertex_location:' "$CONFIG_FILE" 2>/dev/null; then
    LOCATIONS=$(grep 'vertex_location:' "$CONFIG_FILE" | awk '{print $2}' | sort -u)
    check "S2c: vertex_location set ($LOCATIONS)" "PASS"
  else
    check "S2c: vertex_location set" "FAIL"
  fi
fi

# S3: Service account credentials configured
if [[ -f "$SERVICE_FILE" ]]; then
  CRED_PATH=$(grep 'GOOGLE_APPLICATION_CREDENTIALS=' "$SERVICE_FILE" 2>/dev/null | sed 's/.*GOOGLE_APPLICATION_CREDENTIALS=//' | tr -d '"' || echo "")
  if [[ -n "$CRED_PATH" && -f "$CRED_PATH" ]]; then
    check "S3a: GOOGLE_APPLICATION_CREDENTIALS file exists" "PASS"
    # Verify it's a service account key (not user creds)
    KEY_TYPE=$(python3 -c "import json; print(json.load(open('$CRED_PATH')).get('type',''))" 2>/dev/null || echo "")
    if [[ "$KEY_TYPE" == "service_account" ]]; then
      check "S3b: Credentials type is service_account" "PASS"
    else
      check "S3b: Credentials type is service_account (got: $KEY_TYPE)" "FAIL"
    fi
  elif [[ -n "$CRED_PATH" ]]; then
    check "S3a: GOOGLE_APPLICATION_CREDENTIALS file exists ($CRED_PATH missing)" "FAIL"
  else
    check "S3a: GOOGLE_APPLICATION_CREDENTIALS configured" "FAIL"
  fi
fi

# S4: Health endpoint responds
HEALTH=$(curl -sf "$LITELLM_URL/health" 2>/dev/null || echo '{}')
HEALTHY=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('healthy_count',0))" 2>/dev/null || echo "0")
UNHEALTHY=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('unhealthy_count',1))" 2>/dev/null || echo "1")

if [[ "$HEALTHY" -ge 1 ]]; then
  check "S4a: Health endpoint responds ($HEALTHY healthy)" "PASS"
else
  check "S4a: Health endpoint responds" "FAIL"
fi

if [[ "$UNHEALTHY" == "0" ]]; then
  check "S4b: No unhealthy endpoints" "PASS"
else
  check "S4b: No unhealthy endpoints ($UNHEALTHY unhealthy)" "FAIL"
fi

# S5: Models endpoint returns models
MODEL_LIST=$(curl -sf "$LITELLM_URL/v1/models" 2>/dev/null | python3 -c "import sys,json; [print(m['id']) for m in json.load(sys.stdin).get('data',[])]" 2>/dev/null || echo "")
if [[ -n "$MODEL_LIST" ]]; then
  MODEL_N=$(echo "$MODEL_LIST" | wc -l)
  check "S5: /v1/models returns $MODEL_N model(s)" "PASS"
  echo "    Models: $(echo $MODEL_LIST | tr '\n' ', ')" 
else
  check "S5: /v1/models returns models" "FAIL"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
