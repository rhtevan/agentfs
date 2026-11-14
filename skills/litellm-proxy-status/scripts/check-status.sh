#!/bin/bash
# check-status.sh — Gather LiteLLM proxy status facts
#
# Queries systemd, health endpoint, model list, and configs.
# Outputs structured facts for the agent to report.
#
# Usage: check-status.sh
#
# Exit codes:
#   0 — Facts gathered (even if service is down)
#   1 — Critical failure (cannot run at all)

set -euo pipefail

# Source trace library if available
if [[ -f "$HOME/.agents/scripts/trace-lib.sh" ]]; then
  source "$HOME/.agents/scripts/trace-lib.sh"
  trace_init "litellm-proxy-status" "1.2.0" 2>/dev/null || true
else
  trace_step() { :; }; trace_end() { :; }
fi

HEALTH_URL="http://127.0.0.1:4000/health"
MODELS_URL="http://127.0.0.1:4000/v1/models"
CONFIG_FILE="$HOME/.config/litellm/config.yaml"
SERVICE_FILE="$HOME/.config/systemd/user/litellm-proxy.service"

# --- Step 1: systemd status ---
trace_step 1 "checking-systemd-service-status" 0 "" 2>/dev/null || true
echo "--- SYSTEMD STATUS ---"
if systemctl --user is-active litellm-proxy &>/dev/null; then
  echo "Service: active"
  systemctl --user status litellm-proxy --no-pager 2>/dev/null | head -15
else
  echo "Service: inactive"
  systemctl --user status litellm-proxy --no-pager 2>/dev/null | head -5 || echo "Service not found"
fi
echo ""

# --- Step 2: health endpoint ---
trace_step 2 "checking-health-endpoint" 0 "" 2>/dev/null || true
echo "--- HEALTH ---"
health_json=$(curl -s --connect-timeout 3 "$HEALTH_URL" 2>/dev/null || echo "UNREACHABLE")
if [[ "$health_json" == "UNREACHABLE" ]]; then
  echo "Health: unreachable (proxy not running or port 4000 not listening)"
else
  echo "$health_json" | python3 -m json.tool 2>/dev/null || echo "$health_json"
fi
echo ""

# --- Step 3: model list ---
trace_step 3 "listing-available-models" 0 "" 2>/dev/null || true
echo "--- MODELS ---"
models_json=$(curl -s --connect-timeout 3 "$MODELS_URL" 2>/dev/null || echo "UNREACHABLE")
if [[ "$models_json" == "UNREACHABLE" ]]; then
  echo "Models: unreachable"
else
  echo "$models_json" | python3 -m json.tool 2>/dev/null || echo "$models_json"
fi
echo ""

# --- Step 4: LiteLLM config ---
trace_step 4 "reading-litellm-configuration" 0 "" 2>/dev/null || true
echo "--- LITELLM CONFIG ---"
if [[ -f "$CONFIG_FILE" ]]; then
  cat "$CONFIG_FILE"
else
  echo "Config file not found: $CONFIG_FILE"
fi
echo ""

# --- Step 5: service config ---
trace_step 5 "reading-service-configuration" 0 "" 2>/dev/null || true
echo "--- SERVICE CONFIG ---"
if [[ -f "$SERVICE_FILE" ]]; then
  cat "$SERVICE_FILE"
else
  echo "Service file not found: $SERVICE_FILE"
fi
echo ""

trace_step 6 "status-check-complete" 0 "" 2>/dev/null || true
trace_end 2>/dev/null || true
