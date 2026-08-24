#!/usr/bin/env bash
# teardown.sh — Remove DSH installation, launcher, and desktop entry
# Usage: bash teardown.sh [--with-data] [--no-data]
#   --with-data   Also remove ~/.dsh/ (user data, settings, sessions)
#   --no-data     Skip ~/.dsh/ removal without prompting (for testing)
#   (default)     Removes install + launcher only; skips user data
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
LAUNCHER="$HOME/.local/bin/dsh-launcher"
DESKTOP_FILE="$HOME/.local/share/applications/dsh.desktop"
ICON_FILE="$HOME/.local/share/icons/hicolor/256x256/apps/dsh.png"
DSH_HOME="$HOME/.dsh"

REMOVE_DATA=false
for arg in "$@"; do
  case "$arg" in
    --with-data) REMOVE_DATA=true ;;
    --no-data)   REMOVE_DATA=false ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

removed=0

SERVICE_FILE="$HOME/.config/systemd/user/dsh.service"

# --- Stop and remove systemd service ---
if systemctl --user is-active --quiet dsh.service 2>/dev/null; then
  echo "🛑 Stopping DSH service..."
  systemctl --user stop dsh.service
  echo "   Stopped"
fi
if [[ -f "$SERVICE_FILE" ]]; then
  systemctl --user disable dsh.service 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl --user daemon-reload
  echo "✅ Removed systemd service"
  ((removed++)) || true
fi

# --- Kill any orphaned DSH processes ---
if pgrep -f "dsh web" >/dev/null 2>&1; then
  echo "🛑 Stopping orphaned DSH processes..."
  pkill -f "dsh web" 2>/dev/null || true
  sleep 1
  echo "   Stopped"
fi

# --- Remove desktop entry ---
if [[ -f "$DESKTOP_FILE" ]]; then
  rm -f "$DESKTOP_FILE"
  echo "✅ Removed $DESKTOP_FILE"
  ((removed++)) || true
else
  echo "   (skip) $DESKTOP_FILE not found"
fi

# --- Remove icons (all hicolor sizes) ---
ICON_REMOVED=false
for size in 48 128 256 1024; do
  icon="$HOME/.local/share/icons/hicolor/${size}x${size}/apps/dsh.png"
  if [[ -f "$icon" ]]; then
    rm -f "$icon"
    ICON_REMOVED=true
  fi
done
if [[ "$ICON_REMOVED" == true ]]; then
  echo "✅ Removed icon files"
  ((removed++)) || true
  if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  fi
else
  echo "   (skip) No icon files found"
fi

# --- Remove launcher ---
if [[ -f "$LAUNCHER" ]]; then
  rm -f "$LAUNCHER"
  echo "✅ Removed $LAUNCHER"
  ((removed++)) || true
else
  echo "   (skip) $LAUNCHER not found"
fi

# --- Remove DSH install directory ---
if [[ -d "$DSH_DIR" ]]; then
  rm -rf "$DSH_DIR"
  echo "✅ Removed $DSH_DIR"
  ((removed++)) || true
else
  echo "   (skip) $DSH_DIR not found"
fi

# --- Remove user data (optional) ---
if [[ -d "$DSH_HOME" ]]; then
  if [[ "$REMOVE_DATA" == true ]]; then
    rm -rf "$DSH_HOME"
    echo "✅ Removed $DSH_HOME (user data)"
    ((removed++)) || true
  else
    echo "   (kept) $DSH_HOME — user data preserved (use --with-data to remove)"
  fi
else
  echo "   (skip) $DSH_HOME not found"
fi

# --- Update desktop database ---
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
fi

echo ""
if [[ $removed -eq 0 ]]; then
  echo "ℹ️  Nothing to remove — DSH was not installed"
else
  echo "🗑️  DSH teardown complete ($removed items removed)"
fi
