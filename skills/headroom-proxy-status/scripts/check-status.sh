#!/bin/bash
# check-status.sh — Gather headroom proxy status facts
#
# Queries systemd, health endpoint, stats endpoint, and configs.
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
else
  trace_step() { echo "[trace] $*" >&2; }
fi

HEALTH_URL="http://127.0.0.1:8787/health"
STATS_URL="http://127.0.0.1:8787/stats"
STATS_HISTORY_URL="http://127.0.0.1:8787/stats-history"
SERVICE_FILE="$HOME/.config/systemd/user/headroom-proxy.service"
PROVIDER_FILE="$HOME/.config/goose/custom_providers/custom_headroom.json"

# --- Step 1: systemd status ---
trace_step "Checking systemd service status"
echo "--- SYSTEMD STATUS ---"
if systemctl --user is-active headroom-proxy &>/dev/null; then
  echo "Service: active"
  systemctl --user status headroom-proxy --no-pager 2>/dev/null | head -15
else
  echo "Service: inactive"
  systemctl --user status headroom-proxy --no-pager 2>/dev/null | head -5 || echo "Service not found"
fi
echo ""

# --- Step 2: health endpoint ---
trace_step "Checking health endpoint"
echo "--- HEALTH ---"
health_json=$(curl -s --connect-timeout 3 "$HEALTH_URL" 2>/dev/null || echo "UNREACHABLE")
if [[ "$health_json" == "UNREACHABLE" ]]; then
  echo "Health: unreachable (proxy not running or port 8787 not listening)"
else
  echo "$health_json" | python3 -m json.tool 2>/dev/null || echo "$health_json"
fi
echo ""

# --- Step 3: stats endpoint ---
trace_step "Checking compression stats"
echo "--- STATS ---"
stats_json=$(curl -s --connect-timeout 3 "$STATS_URL" 2>/dev/null || echo "UNREACHABLE")
if [[ "$stats_json" == "UNREACHABLE" ]]; then
  echo "Stats: unreachable"
else
  echo "$stats_json" | python3 -m json.tool 2>/dev/null || echo "$stats_json"
fi
echo ""

# --- Step 4: stats history (optional) ---
trace_step "Checking stats history"
echo "--- STATS HISTORY ---"
history_json=$(curl -s --connect-timeout 3 "$STATS_HISTORY_URL" 2>/dev/null || echo "UNREACHABLE")
if [[ "$history_json" == "UNREACHABLE" ]]; then
  echo "Stats history: unreachable"
else
  echo "$history_json" | python3 -m json.tool 2>/dev/null || echo "$history_json"
fi
echo ""

# --- Step 5: service config ---
trace_step "Reading service configuration"
echo "--- SERVICE CONFIG ---"
if [[ -f "$SERVICE_FILE" ]]; then
  cat "$SERVICE_FILE"
else
  echo "Service file not found: $SERVICE_FILE"
fi
echo ""

# --- Step 6: provider config ---
trace_step "Reading Goose provider configuration"
echo "--- PROVIDER CONFIG ---"
if [[ -f "$PROVIDER_FILE" ]]; then
  cat "$PROVIDER_FILE" | python3 -m json.tool 2>/dev/null || cat "$PROVIDER_FILE"
else
  echo "Provider file not found: $PROVIDER_FILE"
fi
echo ""

trace_step "Status check complete"
