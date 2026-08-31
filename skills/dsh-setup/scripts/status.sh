#!/usr/bin/env bash
# status.sh — Show DSH backend status, desktop path, and version
# Usage: bash status.sh
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
SERVICE_FILE="$HOME/.config/systemd/user/dsh.service"
PKG_JSON="$DSH_DIR/node_modules/@deepseek-ai/dsh/package.json"

echo "=== DSH Status ==="
echo ""

# --- Systemd service ---
if [[ -f "$SERVICE_FILE" ]]; then
  STATUS=$(systemctl --user is-active dsh.service 2>/dev/null || true)
  case "$STATUS" in
    active)   echo "  Backend:  ✅ running" ;;
    inactive) echo "  Backend:  ⏹  stopped" ;;
    failed)   echo "  Backend:  ❌ failed" ;;
    *)        echo "  Backend:  ⚠️  $STATUS" ;;
  esac
else
  echo "  Backend:  ⚠️  systemd service not installed"
fi

# --- Port 3080 ---
if curl -s --connect-timeout 1 "http://127.0.0.1:3080" >/dev/null 2>&1; then
  echo "  Port:     ✅ 3080 listening"
else
  echo "  Port:     ⏹  3080 not listening"
fi

# --- Desktop file ---
if [[ -f "$DESKTOP_FILE" ]]; then
  echo "  Desktop:  ✅ $DESKTOP_FILE"
else
  echo "  Desktop:  ❌ not installed"
fi

# --- Version check ---
if [[ -f "$PKG_JSON" ]]; then
  INSTALLED=$(grep '"version"' "$PKG_JSON" | head -1 | sed 's/.*"version": *"\([^"]*\)".*/\1/')
  LATEST=$(npm view @deepseek-ai/dsh version 2>/dev/null || echo "")
  if [[ -z "$LATEST" ]]; then
    echo "  Version:  $INSTALLED (registry unreachable — cannot check for updates)"
  elif [[ "$INSTALLED" == "$LATEST" ]]; then
    echo "  Version:  ✅ $INSTALLED (latest)"
  else
    echo "  Version:  ⬆️  $INSTALLED → $LATEST available (run: update dsh)"
  fi
else
  echo "  Version:  ❌ DSH not installed"
fi
