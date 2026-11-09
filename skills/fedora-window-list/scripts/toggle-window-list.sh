#!/usr/bin/env bash
# toggle-window-list.sh — Enable, disable, or check GNOME window list
#
# Usage: toggle-window-list.sh {enable|disable|status}
#
# Exit codes:
#   0 — Operation succeeded
#   1 — Extension not installed or operation failed

set -euo pipefail

# Trace instrumentation for Observable scoring
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "fedora-window-list" "1.2.0" 2>/dev/null || true

EXT="window-list@gnome-shell-extensions.gcampax.github.com"
ACTION="${1:-status}"

case "$ACTION" in
  enable)
    echo "Enabling GNOME window list..."
    if gnome-extensions enable "$EXT" 2>&1; then
      echo "✅ Window list enabled"
    else
      echo "❌ Failed to enable — is the extension installed?"
      echo "   Install: sudo dnf install gnome-shell-extension-window-list"
      exit 1
    fi
    ;;
  disable)
    echo "Disabling GNOME window list..."
    if gnome-extensions disable "$EXT" 2>&1; then
      echo "✅ Window list disabled"
    else
      echo "❌ Failed to disable"
      exit 1
    fi
    ;;
  status)
    echo "GNOME Window List Status"
    echo "════════════════════════"
    if gnome-extensions info "$EXT" 2>/dev/null; then
      STATE=$(gnome-extensions info "$EXT" 2>/dev/null | grep -i 'state:' | awk '{print $2}')
      echo ""
      if [[ "$STATE" == "ACTIVE" ]]; then
        echo "✅ Window list is ACTIVE (enabled)"
      elif [[ "$STATE" == "INACTIVE" ]]; then
        echo "⚠️  Window list is INACTIVE (disabled)"
      else
        echo "State: $STATE"
      fi
    else
      echo "❌ Extension not installed"
      echo "   Install: sudo dnf install gnome-shell-extension-window-list"
      exit 1
    fi
    ;;
  *)
    echo "Usage: toggle-window-list.sh {enable|disable|status}" >&2
    exit 1
    ;;
esac

trace_step 1 "toggle_action" 0 "action=$ACTION" 2>/dev/null || true
trace_end 2>/dev/null || true
