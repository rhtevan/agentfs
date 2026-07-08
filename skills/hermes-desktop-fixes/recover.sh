#!/usr/bin/env bash
# Hermes Desktop Fixes — Full Recovery Script
# Re-applies all patches, sets skip-worktree, clears stale Desktop cache.
# Safe to run multiple times (idempotent).

set -euo pipefail
REPO="/home/ezhang/.hermes/hermes-agent"
HERMES_HOME="/home/ezhang/.hermes"

echo "=== Hermes Desktop Fixes Recovery ==="
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
REPO="/home/ezhang/.hermes/hermes-agent"
LAUNCHER="/home/ezhang/.local/bin/hermes"
ENV_FILE="/home/ezhang/.hermes/hermes-env.sh"

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

# Sandbox bypass (hermes_cli/main.py)
MAIN="${REPO}/hermes_cli/main.py"
if [ -f "${MAIN}" ] && ! grep -q "ELECTRON_DISABLE_SANDBOX" "${MAIN}"; then
    sed -i '/def _desktop_linux_sandbox_fixup/,/return True/{
        /return True/a\
\
    if os.environ.get("ELECTRON_DISABLE_SANDBOX"):\
        return True
    }' "${MAIN}"
fi

# Electron workspace symlink (prebuilder script)
PREBUILDER="${REPO}/apps/desktop/scripts/patch-electron-builder-mac-binary.cjs"
MARKER="hermes-electron-workspace-symlink"
if [ -f "${PREBUILDER}" ] && ! grep -q "${MARKER}" "${PREBUILDER}"; then
    sed -i "2a\\
\\
// ${MARKER}: bridge npm workspace hoisting gap\\
const _rootElectron = path.join(path.resolve(__dirname, '..', '..', '..'), 'node_modules', 'electron')\\
const _wsElectron = path.join(__dirname, '..', 'node_modules', 'electron')\\
if (!fs.existsSync(_rootElectron) \&\& fs.existsSync(path.join(_wsElectron, 'dist'))) {\\
  fs.symlinkSync(_wsElectron, _rootElectron)\\
  console.log('[prebuilder] symlinked root electron -> workspace electron')\\
}\\
" "${PREBUILDER}"
fi

# Set skip-worktree
cd "${REPO}"
for f in tui_gateway/server.py hermes_cli/main.py apps/desktop/scripts/patch-electron-builder-mac-binary.cjs; do
    git update-index --skip-worktree "$f" 2>/dev/null || true
done
echo "[hermes-patches] All patches applied."
APPLYEOF
chmod +x "${APPLY}"
echo "✓ Installed hermes-apply-patches.sh"

# --- 4. Install the revert-patches script ---
REVERT="${HERMES_HOME}/hermes-revert-patches.sh"
cat > "${REVERT}" << 'REVERTEOF'
#!/usr/bin/env bash
set -euo pipefail
REPO="/home/ezhang/.hermes/hermes-agent"
cd "${REPO}"
FILES=(tui_gateway/server.py hermes_cli/main.py apps/desktop/scripts/patch-electron-builder-mac-binary.cjs)
for f in "${FILES[@]}"; do
    git update-index --no-skip-worktree "$f" 2>/dev/null || true
    git checkout -- "$f" 2>/dev/null || true
done
echo "[hermes-patches] Patches reverted for clean update."
REVERTEOF
chmod +x "${REVERT}"
echo "✓ Installed hermes-revert-patches.sh"

# --- 5. Create/update the launcher ---
LAUNCHER="/home/ezhang/.local/bin/hermes"
mkdir -p "$(dirname "${LAUNCHER}")"
cat > "${LAUNCHER}" << 'LAUNCHEOF'
#!/usr/bin/env bash
[ -f "/home/ezhang/.hermes/hermes-env.sh" ] && . "/home/ezhang/.hermes/hermes-env.sh"
unset PYTHONPATH
unset PYTHONHOME

HERMES_BIN="/home/ezhang/.hermes/hermes-agent/venv/bin/hermes"

# Intercept "hermes update" — revert patched files so git pull succeeds,
# then re-apply patches on the new upstream code afterward.
if [ "$1" = "update" ]; then
    bash /home/ezhang/.hermes/hermes-revert-patches.sh 2>/dev/null
    "$HERMES_BIN" "$@"
    rc=$?
    bash /home/ezhang/.hermes/hermes-apply-patches.sh 2>/dev/null
    exit $rc
fi

exec "$HERMES_BIN" "$@"
LAUNCHEOF
chmod +x "${LAUNCHER}"
echo "✓ Installed launcher with update interception"

# --- 6. Install post-merge hook ---
HOOK="${REPO}/.git/hooks/post-merge"
cat > "${HOOK}" << 'HOOKEOF'
#!/usr/bin/env bash
APPLY="/home/ezhang/.hermes/hermes-apply-patches.sh"
[ -x "${APPLY}" ] && bash "${APPLY}"
HOOKEOF
chmod +x "${HOOK}"
echo "✓ Installed post-merge hook"

# --- 7. Apply patches now ---
echo ""
echo "→ Applying patches..."
bash "${APPLY}"

# --- 8. Clear stale Desktop localStorage ---
LEVELDB="/home/ezhang/.config/Hermes/Local Storage/leveldb"
if [ -d "${LEVELDB}" ]; then
    rm -rf "${LEVELDB}"
    echo "✓ Cleared stale Desktop localStorage"
fi

# --- 9. Install health-check script ---
cat > "${HERMES_HOME}/hermes-check-patches.sh" << 'CHECKEOF'
#!/usr/bin/env bash
REPO="/home/ezhang/.hermes/hermes-agent"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
echo "Hermes Desktop patch status:"; echo
grep -q "_resolve_session_info_provider" "${REPO}/tui_gateway/server.py" 2>/dev/null && ok "Provider identity fix (server.py)" || fail "Provider identity fix MISSING (server.py)"
grep -q "ELECTRON_DISABLE_SANDBOX" "${REPO}/hermes_cli/main.py" 2>/dev/null && ok "Sandbox bypass (main.py)" || fail "Sandbox bypass MISSING (main.py)"
grep -q "hermes-electron-workspace-symlink" "${REPO}/apps/desktop/scripts/patch-electron-builder-mac-binary.cjs" 2>/dev/null && ok "Electron symlink (prebuilder)" || fail "Electron symlink MISSING (prebuilder)"
SW=$(cd "${REPO}" && git ls-files -v tui_gateway/server.py hermes_cli/main.py apps/desktop/scripts/patch-electron-builder-mac-binary.cjs 2>/dev/null | grep -c '^S')
[ "$SW" = "3" ] && ok "Skip-worktree flags set (${SW}/3)" || fail "Skip-worktree flags incomplete (${SW}/3)"
grep -q "hermes-env.sh" /home/ezhang/.local/bin/hermes 2>/dev/null && ok "Launcher sources hermes-env.sh" || fail "Launcher missing hermes-env.sh source"
grep -q 'hermes-revert-patches' /home/ezhang/.local/bin/hermes 2>/dev/null && ok "Launcher intercepts 'hermes update'" || fail "Launcher missing update interception"
[ -x /home/ezhang/.hermes/hermes-apply-patches.sh ] && ok "Apply-patches script present" || fail "Apply-patches script MISSING"
[ -x /home/ezhang/.hermes/hermes-revert-patches.sh ] && ok "Revert-patches script present" || fail "Revert-patches script MISSING"
[ -x "${REPO}/.git/hooks/post-merge" ] && ok "Post-merge hook installed" || fail "Post-merge hook MISSING"
echo
[ "$FAIL" -eq 0 ] && echo "All patches healthy. (${PASS} checks passed)" || echo "WARNING: ${FAIL} check(s) failed! Run: bash ~/.hermes/hermes-apply-patches.sh"
CHECKEOF
chmod +x "${HERMES_HOME}/hermes-check-patches.sh"
echo "✓ Installed health-check script"

echo ""
echo "=== Recovery complete ==="
echo "Run: bash ~/.hermes/hermes-check-patches.sh"
