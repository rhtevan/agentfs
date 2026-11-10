#!/usr/bin/env bash
# toggle-window-list.sh — Enable, disable, or check GNOME window list
#
# Usage: toggle-window-list.sh [--dry-run] {enable|disable|status}
#
# Exit codes:
#   0 — Operation succeeded
#   1 — Extension not installed or operation failed

set -euo pipefail

DRY_RUN=false
CHANGES=0
ERRORS=0

# Parse flags first
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

# Trace instrumentation for Observable scoring
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "fedora-window-list" "1.3.0" 2>/dev/null || true

EXT="window-list@gnome-shell-extensions.gcampax.github.com"
ACTION="${1:-status}"

case "$ACTION" in
  enable)
    if $DRY_RUN; then
      STATE=$(gnome-extensions info "$EXT" 2>/dev/null | grep -i 'state:' | awk '{print $2}' || echo "UNKNOWN")
      if [[ "$STATE" == "ACTIVE" ]]; then
        echo "[dry-run] NO CHANGE — window list already enabled"
        echo "DRY_RUN_RESULT=CONVERGED"
      else
        echo "[dry-run] WOULD: Enable GNOME window list extension"
        CHANGES=$((CHANGES + 1))
        echo "DRY_RUN_RESULT=PENDING"
      fi
      echo "Changes: ${CHANGES}"
      exit 0
    fi
    echo "Enabling GNOME window list..."
    if gnome-extensions enable "$EXT" 2>&1; then
      echo "✅ Window list enabled"
      echo "APPLY_RESULT=OK"
    else
      echo "❌ Failed to enable — is the extension installed?"
      echo "   Install: sudo dnf install gnome-shell-extension-window-list"
      echo "APPLY_RESULT=PARTIAL"
      exit 1
    fi
    ;;
  disable)
    if $DRY_RUN; then
      STATE=$(gnome-extensions info "$EXT" 2>/dev/null | grep -i 'state:' | awk '{print $2}' || echo "UNKNOWN")
      if [[ "$STATE" == "INACTIVE" || "$STATE" == "UNKNOWN" ]]; then
        echo "[dry-run] NO CHANGE — window list already disabled or not installed"
        echo "DRY_RUN_RESULT=CONVERGED"
      else
        echo "[dry-run] WOULD: Disable GNOME window list extension"
        CHANGES=$((CHANGES + 1))
        echo "DRY_RUN_RESULT=PENDING"
      fi
      echo "Changes: ${CHANGES}"
      exit 0
    fi
    echo "Disabling GNOME window list..."
    if gnome-extensions disable "$EXT" 2>&1; then
      echo "✅ Window list disabled"
      echo "APPLY_RESULT=OK"
    else
      echo "❌ Failed to disable"
      echo "APPLY_RESULT=PARTIAL"
      exit 1
    fi
    ;;
  status)
    # Status is read-only — dry-run is a no-op
    if $DRY_RUN; then
      echo "[dry-run] Status is read-only. No changes to apply."
      echo "DRY_RUN_RESULT=CONVERGED"
      exit 0
    fi
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
    echo "Usage: toggle-window-list.sh [--dry-run] {enable|disable|status}" >&2
    exit 1
    ;;
esac

trace_step 1 "toggle_action" 0 "action=$ACTION" 2>/dev/null || true
trace_end 2>/dev/null || true
