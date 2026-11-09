#!/usr/bin/env bash
# setup.sh — Install and configure Headroom LiteLLM proxy
#
# Usage: setup.sh [--check] [--port PORT] [--upstream URL]
#   --check      Show current state without modifying anything
#   --port PORT  Headroom listen port (default: 9000)
#   --upstream   LiteLLM upstream URL (default: http://127.0.0.1:4000)
#
# Exit codes:
#   0 — Setup complete
#   1 — Error

set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "headroom-litellm-proxy" "1.2.0" 2>/dev/null || true

PORT=9000
UPSTREAM="http://127.0.0.1:4000"
CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK=true; shift ;;
    --port) PORT="$2"; shift 2 ;;
    --upstream) UPSTREAM="$2"; shift 2 ;;
    *) echo "Usage: setup.sh [--check] [--port PORT] [--upstream URL]" >&2; exit 2 ;;
  esac
done

SERVICE_FILE="$HOME/.config/systemd/user/headroom-proxy.service"

echo "=== Headroom LiteLLM Proxy Setup ==="
echo ""

# Step 1: Check current state
echo "1. Checking current state..."
if command -v headroom > /dev/null 2>&1; then
  echo "   ✅ headroom installed: $(headroom --version 2>/dev/null || echo 'unknown version')"
else
  echo "   ❌ headroom not installed"
fi

if [[ -f "$SERVICE_FILE" ]]; then
  echo "   ✅ Systemd service file exists"
  state=$(systemctl --user is-active headroom-proxy 2>/dev/null || echo "inactive")
  echo "   Service state: $state"
else
  echo "   ❌ Systemd service file not found"
fi

if curl -s "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
  echo "   ✅ Health endpoint responding on port $PORT"
else
  echo "   ❌ Health endpoint not responding on port $PORT"
fi
trace_step 1 "check_state" 0 "" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  trace_end 2>/dev/null || true
  exit 0
fi

# Step 2: Install headroom
echo ""
echo "2. Installing headroom..."
if command -v headroom > /dev/null 2>&1; then
  echo "   ✅ Already installed"
else
  if command -v uv > /dev/null 2>&1; then
    uv tool install 'headroom-ai[proxy]'
    echo "   ✅ Installed via uv"
  else
    echo "   ❌ uv not found. Install uv first: curl -LsSf https://astral.sh/uv/install.sh | sh"
    exit 1
  fi
fi
trace_step 2 "install" 0 "" 2>/dev/null || true

# Step 3: Create systemd service
echo ""
echo "3. Creating systemd service..."
mkdir -p "$(dirname "$SERVICE_FILE")"
HEADROOM_BIN=$(command -v headroom 2>/dev/null || echo "$HOME/.local/bin/headroom")
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Headroom Proxy - Context optimization layer for LLM traffic
After=litellm-proxy.service
Wants=litellm-proxy.service

[Service]
Type=simple
ExecStart=${HEADROOM_BIN} proxy --port ${PORT} --upstream ${UPSTREAM}
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOF
echo "   ✅ Service file created: $SERVICE_FILE"
systemctl --user daemon-reload
trace_step 3 "create_service" 0 "" 2>/dev/null || true

# Step 4: Enable and start
echo ""
echo "4. Enabling and starting service..."
systemctl --user enable headroom-proxy 2>/dev/null || true
systemctl --user start headroom-proxy 2>/dev/null || true
sleep 2
state=$(systemctl --user is-active headroom-proxy 2>/dev/null || echo "unknown")
echo "   Service state: $state"
[[ "$state" == "active" ]] && echo "   ✅ Running" || echo "   ⚠️  Not active — check: journalctl --user -u headroom-proxy"
trace_step 4 "start_service" 0 "state=$state" 2>/dev/null || true

# Step 5: Verify health
echo ""
echo "5. Verifying health endpoint..."
if curl -sf "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
  echo "   ✅ Health endpoint responding"
else
  echo "   ⚠️  Health endpoint not responding (may need a few seconds)"
fi
trace_step 5 "verify_health" 0 "" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
trace_end 2>/dev/null || true
