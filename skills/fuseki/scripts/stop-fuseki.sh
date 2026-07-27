#!/usr/bin/env bash
# stop-fuseki.sh — Stop the Fuseki systemd user service
# Usage: bash stop-fuseki.sh
set -euo pipefail

SERVICE="fuseki.service"
PORT=3030

echo "══════════════════════════════════════════════════════"
echo "  Stopping Fuseki"
echo "══════════════════════════════════════════════════════"

# Check if service unit exists
if ! systemctl --user cat "${SERVICE}" &>/dev/null; then
    echo "  [~] Service unit not found. Nothing to stop."
    exit 0
fi

# Check if running
if ! systemctl --user is-active "${SERVICE}" &>/dev/null; then
    echo "  [~] Fuseki is not running"
else
    echo "  [+] Stopping ${SERVICE}..."
    systemctl --user stop "${SERVICE}"
    echo "  [✓] Service stopped"
fi

# Verify port is released
sleep 2
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 2 \
    "http://localhost:${PORT}/\$/ping" 2>/dev/null) || true

if [[ "$HTTP_CODE" == "000" || -z "$HTTP_CODE" ]]; then
    echo "  [✓] Port ${PORT} is released"
else
    echo "  [!] Port ${PORT} still responding (HTTP ${HTTP_CODE})"
    echo "      Checking for lingering processes..."
    if pgrep -f fuseki-server &>/dev/null; then
        echo "      Killing lingering fuseki-server process..."
        pkill -f fuseki-server
        sleep 2
        echo "      [✓] Process killed"
    fi
fi

echo ""
echo "══════════════════════════════════════════════════════"
