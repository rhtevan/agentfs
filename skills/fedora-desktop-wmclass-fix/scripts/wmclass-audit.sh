#!/usr/bin/env bash
# wmclass-audit.sh — Audit and fix StartupWMClass in .desktop files for Electron apps
# Usage: bash wmclass-audit.sh [--fix] [--app <desktop-file-basename>]
#   --fix   Apply fixes automatically (default: dry-run report only)
#   --app   Target a specific .desktop file (e.g., "Goose" for Goose.desktop)
#           Without --app, scans all .desktop files in both system and user dirs
set -euo pipefail

FIX_MODE=false
TARGET_APP=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX_MODE=true; shift ;;
    --app) TARGET_APP="$2"; shift 2 ;;
    *) echo "Usage: bash wmclass-audit.sh [--fix] [--app <name>]"; exit 2 ;;
  esac
done

USER_APPS="$HOME/.local/share/applications"
SYSTEM_APPS="/usr/share/applications"
FLATHUB_APPS="/var/lib/flatpak/exports/share/applications"
SNAP_APPS="/var/lib/snapd/desktop/applications"

# Collect desktop files to scan
declare -a DESKTOP_FILES=()

find_desktop_files() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    while IFS= read -r -d '' f; do
      DESKTOP_FILES+=("$f")
    done < <(find "$dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
  fi
}

if [[ -n "$TARGET_APP" ]]; then
  # Look for specific app in user dir first, then system
  for dir in "$USER_APPS" "$SYSTEM_APPS" "$FLATHUB_APPS" "$SNAP_APPS"; do
    [[ -f "$dir/${TARGET_APP}.desktop" ]] && DESKTOP_FILES+=("$dir/${TARGET_APP}.desktop")
  done
  if [[ ${#DESKTOP_FILES[@]} -eq 0 ]]; then
    echo "ERROR: No .desktop file found for '$TARGET_APP'"
    exit 1
  fi
else
  find_desktop_files "$USER_APPS"
  find_desktop_files "$SYSTEM_APPS"
  find_desktop_files "$FLATHUB_APPS"
  find_desktop_files "$SNAP_APPS"
fi

# Detect if a .desktop file is an Electron app
is_electron_app() {
  local desktop_file="$1"
  local binary
  binary=$(extract_binary_from_exec "$desktop_file")

  # Resolve the binary
  if [[ -z "$binary" ]] || [[ ! -x "$binary" && ! -x "$(command -v "$binary" 2>/dev/null || true)" ]]; then
    return 1
  fi

  # Check if it's an Electron app by looking for resources/app.asar
  local binary_dir
  binary_dir=$(dirname "$(readlink -f "$binary" 2>/dev/null || echo "$binary")")
  if [[ -f "$binary_dir/resources/app.asar" ]] || [[ -f "$binary_dir/resources/app.asar.unpacked/package.json" ]]; then
    return 0
  fi

  # Also check common Electron indicators in the binary path
  if [[ "$binary_dir" == */lib/* ]] && [[ -d "$binary_dir/resources" ]]; then
    return 0
  fi

  return 1
}

# Extract the actual binary path from an Exec= line (shared helper)
extract_binary_from_exec() {
  local desktop_file="$1"
  local exec_line
  exec_line=$(grep -m1 '^Exec=' "$desktop_file" 2>/dev/null || true)
  echo "$exec_line" | sed 's/^Exec=//' | awk '{
    for (i=1; i<=NF; i++) {
      if ($i == "env") continue
      if ($i ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue
      print $i; exit
    }
  }'
}

# Get the expected WMClass for an Electron app (lowercase binary name)
get_expected_wmclass() {
  local desktop_file="$1"
  local binary
  binary=$(extract_binary_from_exec "$desktop_file")
  binary=$(basename "$binary")

  # Electron on Wayland uses lowercase binary name as app-id
  echo "$binary" | tr '[:upper:]' '[:lower:]'
}

# Get current StartupWMClass
get_current_wmclass() {
  local desktop_file="$1"
  grep -m1 '^StartupWMClass=' "$desktop_file" 2>/dev/null | sed 's/^StartupWMClass=//' || true
}

# Report header
printf '\n%-40s %-12s %-20s %-20s %s\n' "DESKTOP FILE" "ELECTRON?" "CURRENT WMClass" "EXPECTED WMClass" "STATUS"
printf '%-40s %-12s %-20s %-20s %s\n' "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..12})" "$(printf '%0.s-' {1..20})" "$(printf '%0.s-' {1..20})" "$(printf '%0.s-' {1..10})"

ISSUES_FOUND=0
FIXED=0

for df in "${DESKTOP_FILES[@]}"; do
  basename_df=$(basename "$df")

  if ! is_electron_app "$df"; then
    # Not Electron — still check for missing StartupWMClass
    continue
  fi

  current=$(get_current_wmclass "$df")
  expected=$(get_expected_wmclass "$df")
  status=""

  if [[ -z "$current" ]]; then
    status="⚠️  MISSING"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  elif [[ "$current" != "$expected" ]]; then
    status="⚠️  MISMATCH"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  else
    status="✅ OK"
  fi

  printf '%-40s %-12s %-20s %-20s %s\n' "$basename_df" "Yes" "${current:-(none)}" "$expected" "$status"

  # Apply fix if requested
  if [[ "$FIX_MODE" == true ]] && [[ "$status" != "✅ OK" ]]; then
    # Determine writable location
    local_df="$USER_APPS/$basename_df"

    # If the file is in a system dir, copy to user dir first
    if [[ "$df" != "$local_df" ]] && [[ ! -f "$local_df" ]]; then
      mkdir -p "$USER_APPS"
      cp "$df" "$local_df"
      echo "  → Copied to $local_df"
    fi

    target="$local_df"
    [[ -f "$target" ]] || target="$df"

    if grep -q '^StartupWMClass=' "$target"; then
      sed -i "s/^StartupWMClass=.*/StartupWMClass=$expected/" "$target"
    else
      echo "StartupWMClass=$expected" >> "$target"
    fi
    echo "  → Fixed: StartupWMClass=$expected in $target"
    FIXED=$((FIXED + 1))
  fi
done

echo
if [[ $ISSUES_FOUND -eq 0 ]]; then
  echo "✅ All Electron .desktop files have correct StartupWMClass."
else
  echo "⚠️  Found $ISSUES_FOUND issue(s)."
  if [[ "$FIX_MODE" == true ]]; then
    echo "✅ Fixed $FIXED file(s)."
    update-desktop-database "$USER_APPS" 2>/dev/null || true
    echo "Desktop database updated. Restart affected apps to see changes."
  else
    echo "Run with --fix to apply corrections."
  fi
fi

exit $ISSUES_FOUND
