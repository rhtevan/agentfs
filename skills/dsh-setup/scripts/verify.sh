#!/usr/bin/env bash
# verify.sh — Verify DSH installation and launcher
# Usage: bash verify.sh
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
PNPM_BIN="$HOME/.local/share/pnpm/node_modules/.bin/pnpm"
LAUNCHER="$HOME/.local/bin/dsh-launcher"
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_FILE="$HOME/.local/share/icons/hicolor/256x256/apps/dsh.png"
DSH_HOME="$HOME/.dsh"
NODE="/usr/bin/node"

passed=0
failed=0

check() {
  local label="$1" result="$2"
  if [[ "$result" == ok* ]]; then
    echo "  ✅ $label — $result"
    ((passed++)) || true
  else
    echo "  ❌ $label — $result"
    ((failed++)) || true
  fi
}

echo "=== DSH Installation Verification ==="
echo ""

# --- Node.js ---
if [[ -x "$NODE" ]]; then
  check "Node.js" "ok ($($NODE --version))"
else
  check "Node.js" "not found at $NODE"
fi

# --- pnpm ---
if [[ -x "$PNPM_BIN" ]]; then
  check "pnpm" "ok ($($NODE "$PNPM_BIN" --version 2>/dev/null))"
else
  check "pnpm" "not installed at $PNPM_BIN"
fi

# --- DSH install directory ---
if [[ -d "$DSH_DIR/node_modules/@deepseek-ai/dsh" ]]; then
  check "DSH package" "ok"
else
  check "DSH package" "not found at $DSH_DIR"
fi

# --- DSH binary ---
if [[ -x "$DSH_DIR/node_modules/.bin/dsh" ]]; then
  CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'goose.*hermit' | grep -v 'Goose.*bin' | tr '\n' ':')
  DSH_VERSION=$(cd "$DSH_DIR" && PATH="${CLEAN_PATH%:}" ./node_modules/.bin/dsh --version 2>/dev/null || echo "unknown")
  check "DSH binary" "ok (v$DSH_VERSION)"
else
  check "DSH binary" "not found"
fi

# --- Launcher ---
if [[ -x "$LAUNCHER" ]]; then
  check "Launcher" "ok"
else
  check "Launcher" "not found at $LAUNCHER"
fi

# --- Desktop file ---
if [[ -f "$DESKTOP_FILE" ]]; then
  # Validate WMClass
  if grep -q 'StartupWMClass=dsh' "$DESKTOP_FILE" 2>/dev/null; then
    check "Desktop file" "ok (WMClass correct)"
  else
    check "Desktop file" "present but StartupWMClass mismatch"
  fi
else
  check "Desktop file" "not found at $DESKTOP_FILE"
fi

# --- Icon ---
if [[ -f "$ICON_FILE" ]]; then
  check "Icon" "ok"
else
  check "Icon" "not found (will use fallback)"
fi

# --- Chrome ---
if command -v google-chrome &>/dev/null; then
  check "Google Chrome" "ok ($(google-chrome --version 2>/dev/null | head -1))"
else
  check "Google Chrome" "not found"
fi

# --- DSH home ---
if [[ -d "$DSH_HOME" ]]; then
  check "DSH home (~/.dsh)" "ok"
else
  echo "  ℹ️  DSH home (~/.dsh) — not yet created (created on first launch)"
fi

# --- Systemd service ---
SERVICE_FILE="$HOME/.config/systemd/user/dsh.service"
if [[ -f "$SERVICE_FILE" ]]; then
  if systemctl --user is-active --quiet dsh.service 2>/dev/null; then
    check "Systemd service" "ok (active)"
  else
    check "Systemd service" "ok (installed, inactive)"
  fi
else
  check "Systemd service" "not installed at $SERVICE_FILE"
fi

# --- Port 3080 status ---
if curl -s --connect-timeout 1 "http://127.0.0.1:3080" >/dev/null 2>&1; then
  check "Port 3080" "ok (DSH backend is running)"
else
  echo "  ℹ️  Port 3080 — DSH backend not running (expected when idle)"
fi

echo ""
echo "=== Results: $passed passed, $failed failed ==="

if [[ $failed -gt 0 ]]; then
  exit 1
fi
