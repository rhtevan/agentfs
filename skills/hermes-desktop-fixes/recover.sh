#!/usr/bin/env bash
# Hermes Desktop Fixes — Full Recovery Script (v3.0)
# Re-applies patches, installs desktop entry, configures launcher.
# Safe to run multiple times (idempotent).

set -euo pipefail
REPO="$HOME/.hermes/hermes-agent"
HERMES_HOME="$HOME/.hermes"

echo "=== Hermes Desktop Fixes Recovery (v3.0) ==="
echo ""

# --- 1. Ensure hermes-env.sh exists ---
ENV_FILE="${HERMES_HOME}/hermes-env.sh"
if [ ! -f "${ENV_FILE}" ]; then
    cat > "${ENV_FILE}" << 'ENVEOF'
# Hermes launcher environment customizations.
PATH="$(echo "$PATH" | tr ':' '\n' | grep -v '/usr/lib/Goose/resources/bin' | tr '\n' ':' | sed 's/:$//')"
export PATH
export ELECTRON_DISABLE_SANDBOX=1
ENVEOF
    echo "✓ Created hermes-env.sh"
else
    echo "✓ hermes-env.sh exists"
fi

# --- 2. Ensure .env has ELECTRON_DISABLE_SANDBOX ---
DOT_ENV="${HERMES_HOME}/.env"
if ! grep -q "ELECTRON_DISABLE_SANDBOX" "${DOT_ENV}" 2>/dev/null; then
    echo "ELECTRON_DISABLE_SANDBOX=1" >> "${DOT_ENV}"
    echo "✓ Added ELECTRON_DISABLE_SANDBOX to .env"
else
    echo "✓ .env has ELECTRON_DISABLE_SANDBOX"
fi

# --- 3. Install the apply-patches script ---
APPLY="${HERMES_HOME}/hermes-apply-patches.sh"
cat > "${APPLY}" << 'APPLYEOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="$HOME/.hermes/hermes-agent"
LAUNCHER="$HOME/.local/bin/hermes"
ENV_FILE="$HOME/.hermes/hermes-env.sh"

# Launcher — ensure it sources hermes-env.sh
if [ -f "${LAUNCHER}" ] && [ -f "${ENV_FILE}" ]; then
    grep -q "hermes-env.sh" "${LAUNCHER}" || \
        sed -i '1a\[ -f "'"${ENV_FILE}"'" ] && . "'"${ENV_FILE}"'"' "${LAUNCHER}"
fi

# Provider identity fix (tui_gateway/server.py)
SERVER="${REPO}/tui_gateway/server.py"
if [ -f "${SERVER}" ] && ! grep -q "_resolve_session_info_provider" "${SERVER}"; then
    sed -i '/^def _session_info(agent/i\
\
\
def _resolve_session_info_provider(agent) -> str:\
    """Map bare "custom" back to the config-level custom:<name> identity."""\
    provider = str(getattr(agent, "provider", "") or "")\
    if provider != "custom":\
        return provider\
    base_url = str(getattr(agent, "base_url", "") or "")\
    if not base_url:\
        return provider\
    try:\
        from hermes_cli.runtime_provider import find_custom_provider_identity\
        identity = find_custom_provider_identity(base_url)\
        if identity:\
            return identity\
    except Exception:\
        pass\
    return provider\
' "${SERVER}"
    sed -i 's/"provider": getattr(agent, "provider", "")/"provider": _resolve_session_info_provider(agent)/' "${SERVER}"
fi

# Set skip-worktree (only for files that are still patched)
cd "${REPO}"
git update-index --skip-worktree tui_gateway/server.py 2>/dev/null || true
echo "[hermes-patches] All patches applied."
APPLYEOF
chmod +x "${APPLY}"
echo "✓ Installed hermes-apply-patches.sh"

# --- 4. Install the revert-patches script ---
REVERT="${HERMES_HOME}/hermes-revert-patches.sh"
cat > "${REVERT}" << 'REVERTEOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="$HOME/.hermes/hermes-agent"
cd "${REPO}"
# Only revert files that are still actively patched
git update-index --no-skip-worktree tui_gateway/server.py 2>/dev/null || true
git checkout -- tui_gateway/server.py 2>/dev/null || true
echo "[hermes-patches] Patches reverted for clean update."
REVERTEOF
chmod +x "${REVERT}"
echo "✓ Installed hermes-revert-patches.sh"

# --- 5. Create/update the launcher ---
LAUNCHER="$HOME/.local/bin/hermes"
mkdir -p "$(dirname "${LAUNCHER}")"
cat > "${LAUNCHER}" << 'LAUNCHEOF'
#!/usr/bin/env bash
[ -f "$HOME/.hermes/hermes-env.sh" ] && . "$HOME/.hermes/hermes-env.sh"
unset PYTHONPATH
unset PYTHONHOME

HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"

# Intercept "hermes update" — revert patched files so git pull succeeds,
# then re-apply patches on the new upstream code afterward.
if [ "$1" = "update" ]; then
    bash $HOME/.hermes/hermes-revert-patches.sh 2>/dev/null
    "$HERMES_BIN" "$@"
    rc=$?
    bash $HOME/.hermes/hermes-apply-patches.sh 2>/dev/null
    exit $rc
fi

# Desktop entry fix: upstream writes hermes.desktop on every launch with a
# broken Exec path. Our real entry is com.nousresearch.hermes.desktop (matches
# Electron's Wayland app-id). Background watcher deletes the upstream duplicate
# and ensures our entry stays correct.
if [ "$1" = "desktop" ]; then
    _DESKTOP_DIR="$HOME/.local/share/applications"
    _UPSTREAM_ENTRY="$_DESKTOP_DIR/hermes.desktop"
    _OUR_ENTRY="$_DESKTOP_DIR/com.nousresearch.hermes.desktop"
    _DESIRED_EXEC="env ELECTRON_DISABLE_SANDBOX=1 $HOME/.local/bin/hermes desktop --skip-build"
    (
        # Wait for upstream to write hermes.desktop (up to 30s), then remove it
        for _i in $(seq 1 30); do
            sleep 1
            if [ -f "$_UPSTREAM_ENTRY" ]; then
                rm -f "$_UPSTREAM_ENTRY"
                # Ensure our entry has the correct Exec
                cat > "$_OUR_ENTRY" << ENTRY
[Desktop Entry]
Name=Hermes Agent
Comment=Hermes Agent Desktop App
Exec=${_DESIRED_EXEC}
Icon=hermes
Terminal=false
Type=Application
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=Hermes
ENTRY
                chmod +x "$_OUR_ENTRY"
                update-desktop-database "$_DESKTOP_DIR" 2>/dev/null
                break
            fi
        done
    ) &
fi

exec "$HERMES_BIN" "$@"
LAUNCHEOF
chmod +x "${LAUNCHER}"
echo "✓ Installed launcher with update interception + desktop entry watcher"

# --- 6. Install post-merge hook ---
HOOK="${REPO}/.git/hooks/post-merge"
cat > "${HOOK}" << 'HOOKEOF'
#!/usr/bin/env bash
APPLY="$HOME/.hermes/hermes-apply-patches.sh"
[ -x "${APPLY}" ] && bash "${APPLY}"
HOOKEOF
chmod +x "${HOOK}"
echo "✓ Installed post-merge hook"

# --- 7. Apply patches now ---
echo ""
echo "→ Applying patches..."
bash "${APPLY}"

# --- 8. Install desktop entry ---
DESKTOP_DIR="$HOME/.local/share/applications"
OUR_ENTRY="${DESKTOP_DIR}/com.nousresearch.hermes.desktop"
UPSTREAM_ENTRY="${DESKTOP_DIR}/hermes.desktop"
OLD_ENTRY="${DESKTOP_DIR}/hermes-desktop.desktop"

# Remove stale entries
rm -f "${UPSTREAM_ENTRY}" "${OLD_ENTRY}" 2>/dev/null

cat > "${OUR_ENTRY}" << DESKEOF
[Desktop Entry]
Name=Hermes Agent
Comment=Hermes Agent Desktop App
Exec=env ELECTRON_DISABLE_SANDBOX=1 $HOME/.local/bin/hermes desktop --skip-build
Icon=hermes
Terminal=false
Type=Application
Categories=Development;Utility;
StartupNotify=true
StartupWMClass=Hermes
DESKEOF
chmod +x "${OUR_ENTRY}"
update-desktop-database "${DESKTOP_DIR}" 2>/dev/null
echo "✓ Installed com.nousresearch.hermes.desktop (Wayland app-id match)"

# Refresh icon cache (upstream installs hicolor icons via linux_desktop_entry.py)
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null && \
    echo "✓ Refreshed hicolor icon cache" || \
    echo "⚠ Could not refresh icon cache (icons may still work)"

# Update GNOME favorites if old entry is pinned
FAVS=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "")
if echo "${FAVS}" | grep -q "hermes-desktop.desktop"; then
    NEW_FAVS=$(echo "${FAVS}" | sed "s/'hermes-desktop.desktop'/'com.nousresearch.hermes.desktop'/g")
    gsettings set org.gnome.shell favorite-apps "${NEW_FAVS}" 2>/dev/null && \
        echo "✓ Updated GNOME favorites to com.nousresearch.hermes.desktop" || true
fi
# Also handle if hermes.desktop was pinned
if echo "${FAVS}" | grep -q "'hermes.desktop'"; then
    FAVS=$(gsettings get org.gnome.shell favorite-apps 2>/dev/null || echo "")
    NEW_FAVS=$(echo "${FAVS}" | sed "s/'hermes.desktop'/'com.nousresearch.hermes.desktop'/g")
    gsettings set org.gnome.shell favorite-apps "${NEW_FAVS}" 2>/dev/null && \
        echo "✓ Updated GNOME favorites to com.nousresearch.hermes.desktop" || true
fi

# --- 9. Clear stale Desktop localStorage ---
LEVELDB="$HOME/.config/Hermes/Local Storage/leveldb"
if [ -d "${LEVELDB}" ]; then
    rm -rf "${LEVELDB}"
    echo "✓ Cleared stale Desktop localStorage"
fi

# --- 10. Install health-check script ---
cat > "${HERMES_HOME}/hermes-check-patches.sh" << 'CHECKEOF'
#!/usr/bin/env bash
REPO="$HOME/.hermes/hermes-agent"
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
skip() { echo "  ○ $1 (retired)"; SKIP=$((SKIP+1)); }

echo "Hermes Desktop patch status:"; echo

# Active patches
grep -q "_resolve_session_info_provider" "${REPO}/tui_gateway/server.py" 2>/dev/null \
    && ok "Provider identity fix (server.py)" \
    || fail "Provider identity fix MISSING (server.py)"

SW=$(cd "${REPO}" && git ls-files -v tui_gateway/server.py 2>/dev/null | grep -c '^S')
[ "$SW" = "1" ] && ok "Skip-worktree flag set (server.py)" || fail "Skip-worktree flag missing (server.py)"

# Retired patches (informational only)
skip "Sandbox bypass (main.py) — env var ELECTRON_DISABLE_SANDBOX sufficient"
skip "Electron symlink (prebuilder) — file removed upstream"

# Infrastructure
grep -q "hermes-env.sh" "$HOME/.local/bin/hermes" 2>/dev/null \
    && ok "Launcher sources hermes-env.sh" \
    || fail "Launcher missing hermes-env.sh source"
grep -q 'hermes-revert-patches' "$HOME/.local/bin/hermes" 2>/dev/null \
    && ok "Launcher intercepts 'hermes update'" \
    || fail "Launcher missing update interception"
grep -q 'com.nousresearch.hermes' "$HOME/.local/bin/hermes" 2>/dev/null \
    && ok "Launcher has desktop entry watcher" \
    || fail "Launcher missing desktop entry watcher"
[ -x "$HOME/.hermes/hermes-apply-patches.sh" ] \
    && ok "Apply-patches script present" \
    || fail "Apply-patches script MISSING"
[ -x "$HOME/.hermes/hermes-revert-patches.sh" ] \
    && ok "Revert-patches script present" \
    || fail "Revert-patches script MISSING"
[ -x "${REPO}/.git/hooks/post-merge" ] \
    && ok "Post-merge hook installed" \
    || fail "Post-merge hook MISSING"

# Desktop entry
[ -f "$HOME/.local/share/applications/com.nousresearch.hermes.desktop" ] \
    && ok "Desktop entry (com.nousresearch.hermes.desktop)" \
    || fail "Desktop entry MISSING (com.nousresearch.hermes.desktop)"
[ ! -f "$HOME/.local/share/applications/hermes-desktop.desktop" ] \
    && ok "Old desktop entry removed (hermes-desktop.desktop)" \
    || fail "Stale desktop entry exists (hermes-desktop.desktop) — remove it"

# Icon theme
python3 -c "
import gi; gi.require_version('Gtk','3.0')
from gi.repository import Gtk
i = Gtk.IconTheme.get_default().lookup_icon('hermes',48,0)
exit(0 if i else 1)
" 2>/dev/null \
    && ok "Icon theme resolves 'hermes'" \
    || fail "Icon theme cannot resolve 'hermes' — run: gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor"

echo ""
echo "Active: ${PASS} passed, ${FAIL} failed | Retired: ${SKIP} skipped"
[ "$FAIL" -eq 0 ] && echo "All checks healthy." || echo "WARNING: ${FAIL} check(s) failed! Run: bash ~/.agents/skills/hermes-desktop-fixes/recover.sh"
CHECKEOF
chmod +x "${HERMES_HOME}/hermes-check-patches.sh"
echo "✓ Installed health-check script"

echo ""
echo "=== Recovery complete ==="
echo "Run: bash ~/.hermes/hermes-check-patches.sh"
