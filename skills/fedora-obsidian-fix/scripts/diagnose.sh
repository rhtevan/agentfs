#!/usr/bin/env bash
# diagnose.sh — Check whether the Obsidian Snap portal fix is needed
# Usage: bash diagnose.sh
# Exit codes: 0 = fix needed, 1 = error, 2 = fix not applicable
set -euo pipefail

PASS=0
FAIL=0
WARN=0

info()  { echo "  ✅ $*"; }
warn()  { echo "  ⚠️  $*"; ((WARN++)); }
fail()  { echo "  ❌ $*"; ((FAIL++)); }

echo "=== Obsidian Snap Portal Diagnostic ==="
echo ""

# 1. Check Obsidian is installed via Snap
echo "1. Obsidian installation"
if snap list obsidian &>/dev/null; then
  OBSIDIAN_VER=$(snap list obsidian 2>/dev/null | awk '/^obsidian/{print $2}')
  info "Obsidian Snap installed (v${OBSIDIAN_VER})"
  ((PASS++))
else
  fail "Obsidian is not installed via Snap — this fix is Snap-specific"
  echo ""
  echo "RESULT: Fix not applicable."
  exit 2
fi

# 2. Check session type
echo "2. Session type"
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  info "Wayland session detected"
  ((PASS++))
else
  warn "Session is '${XDG_SESSION_TYPE:-unknown}', not Wayland — issue may not apply"
fi

# 3. Check desktop environment
echo "3. Desktop environment"
if [[ "${XDG_CURRENT_DESKTOP:-}" == *"GNOME"* ]]; then
  info "GNOME desktop detected"
  ((PASS++))
else
  warn "Desktop is '${XDG_CURRENT_DESKTOP:-unknown}' — tested on GNOME only"
fi

# 4. Check portal services
echo "4. Portal services"
if systemctl --user is-active xdg-desktop-portal &>/dev/null; then
  info "xdg-desktop-portal is running"
  ((PASS++))
else
  fail "xdg-desktop-portal is not running"
fi

if systemctl --user is-active xdg-desktop-portal-gnome &>/dev/null; then
  info "xdg-desktop-portal-gnome is running"
  ((PASS++))
else
  warn "xdg-desktop-portal-gnome is not running (may use -gtk instead)"
fi

# 5. Check Snap desktop file
echo "5. Snap desktop file"
SNAP_DESKTOP="/var/lib/snapd/desktop/applications/obsidian_md.obsidian.Obsidian.desktop"
if [[ -f "$SNAP_DESKTOP" ]]; then
  info "Snap desktop file exists: $SNAP_DESKTOP"
  ((PASS++))
else
  fail "Snap desktop file not found at expected path"
fi

# 6. Check if fix is already applied
echo "6. Existing fix"
USER_DESKTOP="$HOME/.local/share/applications/obsidian_md.obsidian.Obsidian.desktop"
WRAPPER="$HOME/.local/bin/obsidian-wrapper.sh"

if [[ -f "$WRAPPER" ]] && [[ -f "$USER_DESKTOP" ]]; then
  if grep -q "obsidian-wrapper.sh" "$USER_DESKTOP" 2>/dev/null; then
    info "Fix already applied (wrapper + desktop override in place)"
    echo ""
    echo "RESULT: Fix is already applied. If the issue persists, re-run fix.sh."
    exit 0
  fi
fi
warn "Fix not yet applied"

# 7. Check for the portal error signature
echo "7. Portal error check"
if journalctl --user -u xdg-desktop-portal --since "today" --no-pager 2>/dev/null \
   | grep -q "DesktopFile.*Snap Info" 2>/dev/null; then
  fail "Portal 'DesktopFile' error found in today's logs — confirms the issue"
else
  info "No portal error in today's logs (may appear after clicking the button)"
fi

echo ""
echo "=== Summary ==="
echo "  Checks passed: $PASS"
echo "  Warnings:      $WARN"
echo "  Failures:      $FAIL"
echo ""

if ((FAIL > 0)) && ! snap list obsidian &>/dev/null; then
  echo "RESULT: Fix not applicable."
  exit 2
else
  echo "RESULT: Fix is applicable. Run fix.sh to apply."
  exit 0
fi
