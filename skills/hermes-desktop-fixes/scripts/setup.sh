#!/usr/bin/env bash
# setup.sh — Apply Hermes Desktop fixes (env, desktop entry, patch system)
# Usage: setup.sh [--check] [--skip-patches]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "hermes-desktop-fixes" "1.0.0" 2>/dev/null || true

CHECK_ONLY=false
SKIP_PATCHES=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --skip-patches) SKIP_PATCHES=true ;;
  esac
done

HERMES_DIR="${HOME}/.hermes"
HERMES_AGENT="${HERMES_DIR}/hermes-agent"
DESKTOP_FILE="${HOME}/.local/share/applications/com.nousresearch.hermes.desktop"
ERRORS=0

echo "=== Hermes Desktop Fixes ==="
echo ""

# ── Step 1: Check Hermes installation ───────────────────────────────────
trace_step 1 "check_hermes" 0 "" 2>/dev/null || true

if [[ -d "$HERMES_AGENT" ]]; then
  echo "✓ Hermes agent dir exists: $HERMES_AGENT"
else
  echo "✗ Hermes agent not found at $HERMES_AGENT"
  exit 1
fi

# ── Step 2: Check/create hermes-env.sh ───────────────────────────────────
trace_step 2 "hermes_env" 0 "path=${HERMES_DIR}/hermes-env.sh" 2>/dev/null || true

if [[ -f "${HERMES_DIR}/hermes-env.sh" ]]; then
  echo "✓ hermes-env.sh exists"
  issues=0
  grep -q 'ELECTRON_DISABLE_SANDBOX' "${HERMES_DIR}/hermes-env.sh" || { echo "  ⚠ Missing ELECTRON_DISABLE_SANDBOX"; issues=$((issues+1)); }
  grep -q 'LC_CTYPE' "${HERMES_DIR}/hermes-env.sh" || { echo "  ⚠ Missing LC_CTYPE fix"; issues=$((issues+1)); }
  grep -q 'Goose.*resources.*bin' "${HERMES_DIR}/hermes-env.sh" || { echo "  ⚠ Missing Goose node wrapper PATH strip"; issues=$((issues+1)); }
  [[ $issues -eq 0 ]] && echo "  ✓ Contains all expected fixes"
  ERRORS=$((ERRORS + issues))
else
  echo "⚠ hermes-env.sh not found"
  if ! $CHECK_ONLY; then
    cat > "${HERMES_DIR}/hermes-env.sh" << 'ENVEOF'
#!/usr/bin/env bash
# hermes-env.sh — Environment fixes for Hermes Desktop

# Fix LC_CTYPE locale warning (Bug #0)
if [[ "${LC_CTYPE:-}" == "UTF-8" || -z "${LC_CTYPE:-}" ]]; then
  export LC_CTYPE="en_US.UTF-8"
fi

# Disable Electron sandbox (Bug #3 replacement)
export ELECTRON_DISABLE_SANDBOX=1

# Strip Goose node wrapper from PATH (Bug #2)
if [[ "$PATH" == *"/usr/lib/Goose/resources/bin"* ]]; then
  PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'Goose/resources/bin' | tr '\n' ':')
  PATH="${PATH%:}"
  export PATH
fi
ENVEOF
    echo "✓ Created hermes-env.sh"
  else
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Step 3: Check/create .env file ───────────────────────────────────────
trace_step 3 "dot_env" 0 "path=${HERMES_DIR}/.env" 2>/dev/null || true

if [[ -f "${HERMES_DIR}/.env" ]]; then
  echo "✓ .env exists"
  grep -q 'ELECTRON_DISABLE_SANDBOX' "${HERMES_DIR}/.env" && echo "  ✓ ELECTRON_DISABLE_SANDBOX set" || echo "  ⚠ Missing ELECTRON_DISABLE_SANDBOX"
  grep -q 'LC_CTYPE' "${HERMES_DIR}/.env" && echo "  ✓ LC_CTYPE set" || echo "  ⚠ Missing LC_CTYPE"
else
  echo "⚠ .env not found"
  if ! $CHECK_ONLY; then
    cat > "${HERMES_DIR}/.env" << 'DOTENVEOF'
ELECTRON_DISABLE_SANDBOX=1
LC_CTYPE=en_US.UTF-8
DOTENVEOF
    echo "✓ Created .env"
  else
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Step 4: Check desktop entry ──────────────────────────────────────────
trace_step 4 "desktop_entry" 0 "path=${DESKTOP_FILE}" 2>/dev/null || true

if [[ -f "$DESKTOP_FILE" ]]; then
  echo "✓ Desktop entry exists: $DESKTOP_FILE"
  grep -q 'StartupWMClass=com.nousresearch.hermes' "$DESKTOP_FILE" && echo "  ✓ Correct WMClass" || { echo "  ⚠ Wrong WMClass"; ERRORS=$((ERRORS+1)); }
  grep -q 'Icon=hermes' "$DESKTOP_FILE" && echo "  ✓ Themed icon" || echo "  ℹ Custom icon path"
else
  echo "⚠ Desktop entry not found (will be created on next 'hermes desktop' launch)"
fi

# Check for duplicate hermes.desktop
if [[ -f "${HOME}/.local/share/applications/hermes.desktop" ]]; then
  echo "⚠ Duplicate hermes.desktop found (upstream-generated, causes duplicate icon)"
  if ! $CHECK_ONLY; then
    rm -f "${HOME}/.local/share/applications/hermes.desktop"
    echo "  ✓ Removed duplicate"
  else
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Step 5: Check launcher wrapper ───────────────────────────────────────
trace_step 5 "launcher_wrapper" 0 "path=${HOME}/.local/bin/hermes" 2>/dev/null || true

if [[ -x "${HOME}/.local/bin/hermes" ]]; then
  echo "✓ Launcher wrapper exists and is executable"
  if grep -q 'hermes-env.sh' "${HOME}/.local/bin/hermes"; then
    echo "  ✓ Sources hermes-env.sh"
  else
    echo "  ⚠ Does not source hermes-env.sh"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠ Launcher wrapper not found at ~/.local/bin/hermes"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 6: Check patch system ───────────────────────────────────────────
trace_step 6 "patch_system" 0 "" 2>/dev/null || true

if $SKIP_PATCHES; then
  echo "⏭ Skipping patch system check (--skip-patches)"
else
  if [[ -f "${HERMES_DIR}/hermes-check-patches.sh" ]]; then
    echo "✓ Patch health check script exists"
    if bash "${HERMES_DIR}/hermes-check-patches.sh" 2>/dev/null; then
      echo "  ✓ Patches healthy"
    else
      echo "  ⚠ Patch health check reported issues"
      ERRORS=$((ERRORS + 1))
    fi
  else
    echo "ℹ No patch system installed (OK if no source patches needed)"
  fi

  # Check git hooks
  if [[ -f "${HERMES_AGENT}/.git/hooks/post-merge" ]]; then
    echo "✓ post-merge hook installed"
  else
    echo "ℹ No post-merge hook (patches won't auto-apply after git pull)"
  fi
fi

# ── Step 7: Check locale config ──────────────────────────────────────────
trace_step 7 "locale_config" 0 "" 2>/dev/null || true

LOCALE_CONF="${HOME}/.config/environment.d/50-locale-fix.conf"
if [[ -f "$LOCALE_CONF" ]]; then
  echo "✓ Locale fix in environment.d: $LOCALE_CONF"
else
  echo "ℹ No environment.d locale fix (optional, hermes-env.sh handles it)"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "✅ All Hermes Desktop fixes are in place."
else
  if $CHECK_ONLY; then
    echo "⚠ ${ERRORS} issue(s) found. Run without --check to apply fixes."
  else
    echo "⚠ Completed with ${ERRORS} warning(s). Review above."
  fi
fi

trace_end 2>/dev/null || true
exit $ERRORS
