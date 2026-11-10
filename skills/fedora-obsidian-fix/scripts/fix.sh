#!/usr/bin/env bash
# fix.sh — Apply the Obsidian Snap portal fix for Fedora Wayland
# Usage: bash fix.sh [--dry-run]
# Exit codes: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

DRY_RUN=false
CHANGES=0
ERRORS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done

WRAPPER="$HOME/.local/bin/obsidian-wrapper.sh"
USER_DESKTOP="$HOME/.local/share/applications/obsidian_md.obsidian.Obsidian.desktop"
SNAP_DESKTOP="/var/lib/snapd/desktop/applications/obsidian_md.obsidian.Obsidian.desktop"
SNAP_DEFAULT_DESKTOP="/var/lib/snapd/desktop/applications/obsidian_obsidian.desktop"
SNAP_DEFAULT_OVERRIDE="$HOME/.local/share/applications/obsidian_obsidian.desktop"
SNAP_ICON="/var/lib/snapd/snap/obsidian/current/meta/gui/obsidian.png"
WMCLASS="md.obsidian.Obsidian"

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

# --- Dry-run check ---
if $DRY_RUN; then
  [[ -f "$WRAPPER" ]] \
    && echo "[dry-run] NO CHANGE — wrapper script already exists" \
    || { echo "[dry-run] WOULD: Create wrapper script $WRAPPER"; CHANGES=$((CHANGES + 1)); }
  [[ -f "$USER_DESKTOP" ]] \
    && echo "[dry-run] NO CHANGE — desktop override already exists" \
    || { echo "[dry-run] WOULD: Create desktop override $USER_DESKTOP"; CHANGES=$((CHANGES + 1)); }
  if [[ -f "$SNAP_DEFAULT_DESKTOP" ]] && [[ ! -f "$SNAP_DEFAULT_OVERRIDE" ]]; then
    echo "[dry-run] WOULD: Shadow competing Snap .desktop file"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — Snap shadow already handled"
  fi
  echo ""
  if [[ $CHANGES -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "DRY_RUN_RESULT=PENDING"
  fi
  echo "Changes: ${CHANGES}"
  exit 0
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
  --class=md.obsidian.Obsidian \
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

# Step 3: Shadow the Snap-provided default .desktop file
# Snap installs obsidian_obsidian.desktop with the same StartupWMClass.
# If both files are visible to GNOME, it matches running windows to both,
# causing a duplicate icon on the Dash. Shadow it with a Hidden override.
echo "3. Shadowing competing Snap .desktop file"
if [[ -f "$SNAP_DEFAULT_DESKTOP" ]]; then
  cat > "$SNAP_DEFAULT_OVERRIDE" << SHADOW_EOF
[Desktop Entry]
Name=Obsidian (Snap default)
Type=Application
NoDisplay=true
Hidden=true
SHADOW_EOF
  echo "   ✅ Created user override to hide $SNAP_DEFAULT_DESKTOP"
else
  echo "   ℹ️  No competing Snap .desktop file found — skipping"
fi

# Step 4: Update desktop database
echo "4. Updating desktop database"
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
  echo "   ✅ Desktop database updated"
else
  echo "   ⚠️  update-desktop-database not found — GNOME will pick up changes on next login"
fi

# Step 5: Clean stale singleton locks
echo "5. Cleaning stale Obsidian locks"
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
