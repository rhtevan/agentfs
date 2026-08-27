#!/usr/bin/env bash
# fix.sh — Apply the Obsidian Snap portal fix for Fedora Wayland
# Usage: bash fix.sh
# Exit codes: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

WRAPPER="$HOME/.local/bin/obsidian-wrapper.sh"
USER_DESKTOP="$HOME/.local/share/applications/obsidian_md.obsidian.Obsidian.desktop"
SNAP_DESKTOP="/var/lib/snapd/desktop/applications/obsidian_md.obsidian.Obsidian.desktop"
SNAP_ICON="/var/lib/snapd/snap/obsidian/current/meta/gui/obsidian.png"

echo "=== Applying Obsidian Snap Portal Fix ==="
echo ""

# Precondition: Obsidian must be installed via Snap
if ! snap list obsidian &>/dev/null; then
  echo "❌ Obsidian is not installed via Snap. Aborting."
  exit 2
fi

# Precondition: Snap desktop file must exist
if [[ ! -f "$SNAP_DESKTOP" ]]; then
  echo "❌ Snap desktop file not found at: $SNAP_DESKTOP"
  echo "   The snap package structure may have changed."
  exit 1
fi

# Step 1: Create wrapper script
echo "1. Creating wrapper script: $WRAPPER"
mkdir -p "$(dirname "$WRAPPER")"
cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
export BAMF_DESKTOP_FILE_HINT="/var/lib/snapd/desktop/applications/obsidian_md.obsidian.Obsidian.desktop"
export SNAP_DESKTOP_FILE="/var/lib/snapd/desktop/applications/obsidian_md.obsidian.Obsidian.desktop"
export GTK_USE_PORTAL=1
exec /snap/obsidian/current/app/obsidian \
  --ozone-platform=x11 \
  "$@"
WRAPPER_EOF
chmod +x "$WRAPPER"
echo "   ✅ Wrapper created and made executable"

# Step 2: Create user-local .desktop override
echo "2. Creating desktop override: $USER_DESKTOP"
mkdir -p "$(dirname "$USER_DESKTOP")"
cat > "$USER_DESKTOP" << DESKTOP_EOF
[Desktop Entry]
X-SnapInstanceName=obsidian
Name=Obsidian
X-SnapAppName=obsidian
Exec=${WRAPPER} %U
Terminal=false
Type=Application
Icon=${SNAP_ICON}
StartupWMClass=md.obsidian.Obsidian
Comment=Obsidian
MimeType=x-scheme-handler/obsidian;
Categories=Office;
DESKTOP_EOF
echo "   ✅ Desktop override created"

# Step 3: Update desktop database
echo "3. Updating desktop database"
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
  echo "   ✅ Desktop database updated"
else
  echo "   ⚠️  update-desktop-database not found — GNOME will pick up changes on next login"
fi

# Step 4: Clean stale singleton locks
echo "4. Cleaning stale Obsidian locks"
OBSIDIAN_CONFIG="$HOME/.config/obsidian"
if [[ -L "$OBSIDIAN_CONFIG/SingletonLock" ]]; then
  LOCK_PID=$(readlink "$OBSIDIAN_CONFIG/SingletonLock" 2>/dev/null | grep -oP '\d+$' || echo "")
  if [[ -n "$LOCK_PID" ]] && ! ps -p "$LOCK_PID" &>/dev/null; then
    rm -f "$OBSIDIAN_CONFIG/SingletonLock" \
          "$OBSIDIAN_CONFIG/SingletonCookie" \
          "$OBSIDIAN_CONFIG/SingletonSocket"
    echo "   ✅ Removed stale singleton locks (PID $LOCK_PID no longer running)"
  else
    echo "   ℹ️  Obsidian is currently running — restart it manually after this fix"
  fi
else
  echo "   ✅ No stale locks found"
fi

echo ""
echo "=== Fix Applied ==="
echo ""
echo "Next steps:"
echo "  1. Quit Obsidian completely (if running)"
echo "  2. Relaunch from the Dash or run: $WRAPPER"
echo "  3. Click 'Open folder as vault' — the file picker should work"
