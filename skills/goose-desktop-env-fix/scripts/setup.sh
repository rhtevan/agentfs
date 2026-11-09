#!/usr/bin/env bash
# setup.sh — Install goose-shell wrapper + environment.d config + desktop entry fix
# Usage: setup.sh [--check] [--skip-desktop] [--skip-bashrc-check]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-desktop-env-fix" "1.0.0" 2>/dev/null || true

CHECK_ONLY=false
SKIP_DESKTOP=false
SKIP_BASHRC=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --skip-desktop) SKIP_DESKTOP=true ;;
    --skip-bashrc-check) SKIP_BASHRC=true ;;
  esac
done

WRAPPER="${HOME}/.local/bin/goose-shell"
ENV_CONF="${HOME}/.config/environment.d/60-goose-shell.conf"
DESKTOP_FILE="${HOME}/.local/share/applications/Goose.desktop"
SYSTEM_DESKTOP="/usr/share/applications/Goose.desktop"
REAL_HOME="$HOME"
ERRORS=0

echo "=== Goose Desktop Environment Fix ==="
echo ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────
trace_step 1 "check_prerequisites" 0 "" 2>/dev/null || true

if [[ -d /usr/lib/Goose ]]; then
  echo "✓ Goose Desktop installed at /usr/lib/Goose"
else
  echo "✗ Goose Desktop not found at /usr/lib/Goose"
  echo "  This fix is only needed for Goose Desktop (Electron app)"
  exit 1
fi

if [[ -f "${HOME}/.bashrc" ]]; then
  echo "✓ ~/.bashrc exists"
else
  echo "✗ ~/.bashrc not found"
  ERRORS=$((ERRORS + 1))
fi

# ── Step 2: Create/verify goose-shell wrapper ────────────────────────────
trace_step 2 "goose_shell_wrapper" 0 "path=${WRAPPER}" 2>/dev/null || true

if [[ -f "$WRAPPER" ]]; then
  echo "✓ goose-shell wrapper exists: $WRAPPER"
  if grep -q '__GOOSE_SHELL_SOURCED' "$WRAPPER"; then
    echo "  ✓ Has recursion guard (__GOOSE_SHELL_SOURCED)"
  else
    echo "  ⚠ Missing recursion guard — may cause infinite loops"
    ERRORS=$((ERRORS + 1))
  fi
  if [[ -x "$WRAPPER" ]]; then
    echo "  ✓ Is executable"
  else
    echo "  ✗ Not executable"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠ goose-shell wrapper not found: $WRAPPER"
  if $CHECK_ONLY; then
    echo "  Would create wrapper"
    ERRORS=$((ERRORS + 1))
  else
    mkdir -p "$(dirname "$WRAPPER")"
    cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/bin/bash
# Goose Desktop shell wrapper — sources ~/.bashrc for full environment
if [ -z "$__GOOSE_SHELL_SOURCED" ]; then
    export __GOOSE_SHELL_SOURCED=1
    unset __ETC_PROFILE_NIX_SOURCED
    unset BASHRCSOURCED
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
exec /bin/bash "$@"
WRAPPER_EOF
    chmod +x "$WRAPPER"
    echo "✓ Created goose-shell wrapper: $WRAPPER"
  fi
fi

# ── Step 3: Create/verify environment.d config ──────────────────────────
trace_step 3 "environment_d_config" 0 "path=${ENV_CONF}" 2>/dev/null || true

if [[ -f "$ENV_CONF" ]]; then
  echo "✓ environment.d config exists: $ENV_CONF"
  if grep -q 'GOOSE_SHELL' "$ENV_CONF"; then
    echo "  ✓ Sets GOOSE_SHELL"
  else
    echo "  ⚠ Does not set GOOSE_SHELL"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "⚠ environment.d config not found: $ENV_CONF"
  if $CHECK_ONLY; then
    echo "  Would create config"
    ERRORS=$((ERRORS + 1))
  else
    mkdir -p "$(dirname "$ENV_CONF")"
    cat > "$ENV_CONF" << EOF
# Tell Goose Desktop to use our wrapper shell that sources ~/.bashrc
GOOSE_SHELL=${REAL_HOME}/.local/bin/goose-shell
EOF
    echo "✓ Created environment.d config: $ENV_CONF"
  fi
fi

# ── Step 4: Check/fix desktop entry ─────────────────────────────────────
trace_step 4 "desktop_entry" 0 "path=${DESKTOP_FILE}" 2>/dev/null || true

if $SKIP_DESKTOP; then
  echo "⏭ Skipping desktop entry check (--skip-desktop)"
else
  if [[ -f "$DESKTOP_FILE" ]]; then
    echo "✓ User desktop file exists: $DESKTOP_FILE"
    if grep -q 'GOOSE_SHELL' "$DESKTOP_FILE"; then
      echo "  ✓ GOOSE_SHELL is set in Exec line"
    else
      echo "  ⚠ GOOSE_SHELL not found in Exec line"
      if $CHECK_ONLY; then
        echo "  Would add GOOSE_SHELL to Exec line"
        ERRORS=$((ERRORS + 1))
      else
        if grep -q 'Exec=env' "$DESKTOP_FILE"; then
          sed -i "s|Exec=env |Exec=env GOOSE_SHELL=${REAL_HOME}/.local/bin/goose-shell |" "$DESKTOP_FILE"
          echo "  ✓ Added GOOSE_SHELL to existing Exec=env line"
        else
          echo "  ⚠ Exec line format not recognized — manual edit needed"
          ERRORS=$((ERRORS + 1))
        fi
      fi
    fi
    if grep -q 'ozone-platform=x11' "$DESKTOP_FILE"; then
      echo "  ✓ Has --ozone-platform=x11 (GPU crash workaround)"
    else
      echo "  ℹ No --ozone-platform=x11 (only needed if GPU crashes on Wayland)"
    fi
  elif [[ -f "$SYSTEM_DESKTOP" ]]; then
    echo "ℹ No user desktop override. System file: $SYSTEM_DESKTOP"
    echo "  environment.d config should be sufficient"
  else
    echo "ℹ No Goose.desktop file found (using environment.d only)"
  fi
fi

# ── Step 5: Check bashrc structure ───────────────────────────────────────
trace_step 5 "bashrc_structure" 0 "" 2>/dev/null || true

if $SKIP_BASHRC; then
  echo "⏭ Skipping bashrc structure check (--skip-bashrc-check)"
else
  if [[ -f "${HOME}/.bashrc" ]]; then
    if grep -q '\[\[ \$- != \*i\* \]\] && return' "${HOME}/.bashrc"; then
      echo "✓ ~/.bashrc has interactive guard"
    else
      echo "⚠ ~/.bashrc missing interactive guard ([[ \$- != *i* ]] && return)"
      echo "  Environment setup should be above the guard, completions below"
      ERRORS=$((ERRORS + 1))
    fi
    if grep -q '__devbox_shellenv_done' "${HOME}/.bashrc"; then
      echo "✓ ~/.bashrc has devbox shell-local guard"
    elif grep -q 'devbox global shellenv' "${HOME}/.bashrc"; then
      echo "⚠ ~/.bashrc calls devbox global shellenv without recursion guard"
      echo "  Risk: fork bomb in non-interactive shells"
      ERRORS=$((ERRORS + 1))
    else
      echo "ℹ No devbox shellenv in ~/.bashrc (OK if devbox not used)"
    fi
  fi
fi

# ── Step 6: Verify GOOSE_SHELL is set ───────────────────────────────────
trace_step 6 "verify_env" 0 "" 2>/dev/null || true

if [[ -n "${GOOSE_SHELL:-}" ]]; then
  echo "✓ GOOSE_SHELL is set: $GOOSE_SHELL"
  if [[ -x "$GOOSE_SHELL" ]]; then
    echo "  ✓ Points to executable file"
  else
    echo "  ✗ Not executable or not found"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "ℹ GOOSE_SHELL not set in current shell (normal for terminal sessions)"
  echo "  It will be set for Goose Desktop via environment.d or .desktop file"
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if $CHECK_ONLY; then
  if [[ $ERRORS -eq 0 ]]; then
    echo "✅ All checks passed. Goose Desktop environment fix is in place."
  else
    echo "⚠ ${ERRORS} issue(s) found. Run without --check to apply fixes."
  fi
else
  if [[ $ERRORS -eq 0 ]]; then
    echo "✅ Setup complete. Restart Goose Desktop to apply changes."
    echo ""
    echo "Post-restart verification:"
    echo "  1. In Goose Desktop, run: echo \$GOOSE_SHELL"
    echo "  2. Run: which gh && which oc"
    echo "  3. Check no fork bombs: ps aux | grep 'devbox global shellenv' | grep -v grep | wc -l"
  else
    echo "⚠ Setup completed with ${ERRORS} warning(s). Review above."
  fi
fi

trace_end 2>/dev/null || true
exit $ERRORS
