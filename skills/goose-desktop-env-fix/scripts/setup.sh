#!/usr/bin/env bash
# setup.sh — Install goose-shell wrapper + rm guard + environment.d config + desktop entry fix
# Usage: setup.sh [--dry-run] [--skip-desktop] [--skip-bashrc-check]
# Version: 1.8.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-desktop-env-fix" "1.8.0" 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=false
SKIP_DESKTOP=false
SKIP_BASHRC=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
    --skip-desktop) SKIP_DESKTOP=true ;;
    --skip-bashrc-check) SKIP_BASHRC=true ;;
  esac
done

WRAPPER="${HOME}/.local/bin/goose-shell"
GUARD_SRC="${SCRIPT_DIR}/rm-guard.sh"
GUARD_BIN="${HOME}/.local/share/goose-guard/bin/rm"
BASHRC="${HOME}/.bashrc"
TS="$(date +%Y%m%d_%H%M%S)"
ENV_CONF="${HOME}/.config/environment.d/60-goose-shell.conf"
DESKTOP_FILE="${HOME}/.local/share/applications/Goose.desktop"
SYSTEM_DESKTOP="/usr/share/applications/Goose.desktop"
REAL_HOME="$HOME"
ERRORS=0
CHANGES=0

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

write_wrapper() {
  local tmp
  mkdir -p "$(dirname "$WRAPPER")"
  tmp="$(mktemp "$(dirname "$WRAPPER")/.goose-shell.XXXXXX")"
  cat > "$tmp" << 'WRAPPER_EOF'
#!/bin/bash
# Goose Desktop shell wrapper — sources ~/.bashrc for full environment
# before executing the command passed via -c.
# goose-desktop-env-fix >= 1.8.0: also puts the rm guard first in PATH
# (goose shell commands only; terminals are not affected).
if [ -z "$__GOOSE_SHELL_SOURCED" ]; then
    export __GOOSE_SHELL_SOURCED=1
    unset __ETC_PROFILE_NIX_SOURCED
    unset BASHRCSOURCED
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi
# rm guard: keep its directory first in PATH (move it to the front if present)
__gg="$HOME/.local/share/goose-guard/bin"
__p=":$PATH:"; __p="${__p//:$__gg:/:}"; __p="${__p#:}"; __p="${__p%:}"
export PATH="$__gg${__p:+:$__p}"
unset __gg __p
exec /bin/bash "$@"
WRAPPER_EOF
  bash -n "$tmp"
  chmod 755 "$tmp"
  mv -f "$tmp" "$WRAPPER"
}

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
  if grep -q 'goose-guard/bin' "$WRAPPER"; then
    echo "  ✓ Puts the rm guard first in PATH"
  elif $DRY_RUN; then
    echo "  Would upgrade wrapper to put the rm guard first in PATH (backup: ${WRAPPER}.bak.<timestamp>)"
    CHANGES=$((CHANGES + 1))
  else
    cp -p "$WRAPPER" "${WRAPPER}.bak.${TS}"
    write_wrapper
    echo "  ✓ Upgraded wrapper: rm guard first in PATH (backup: ${WRAPPER}.bak.${TS})"
  fi
else
  echo "⚠ goose-shell wrapper not found: $WRAPPER"
  if $DRY_RUN; then
    echo "  Would create wrapper"
    CHANGES=$((CHANGES + 1))
  else
    write_wrapper
    echo "✓ Created goose-shell wrapper: $WRAPPER"
  fi
fi

# ── Step 2b: Install/verify the rm guard ─────────────────────────────────
trace_step 2 "rm_guard" 0 "path=${GUARD_BIN}" 2>/dev/null || true

if [[ ! -f "$GUARD_SRC" ]]; then
  echo "✗ rm guard source missing: $GUARD_SRC"
  ERRORS=$((ERRORS + 1))
elif [[ -x "$GUARD_BIN" ]] && cmp -s "$GUARD_SRC" "$GUARD_BIN"; then
  echo "✓ rm guard installed and current: $GUARD_BIN"
elif $DRY_RUN; then
  echo "  Would install rm guard: $GUARD_BIN"
  CHANGES=$((CHANGES + 1))
else
  bash -n "$GUARD_SRC"
  mkdir -p "$(dirname "$GUARD_BIN")"
  install -m 755 "$GUARD_SRC" "$GUARD_BIN"
  echo "✓ Installed rm guard: $GUARD_BIN"
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
  if $DRY_RUN; then
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
      if $DRY_RUN; then
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

# ── Step 5b: Export GOOSE_SHELL from ~/.bashrc ───────────────────────────
# environment.d only reaches processes of the desktop login session. This line
# also covers goose started from SSH logins and any other bash shell. Placed
# above the interactive guard so non-interactive shells get it too.
trace_step 5 "bashrc_goose_shell" 0 "" 2>/dev/null || true

if [[ ! -f "$BASHRC" ]]; then
  echo "ℹ No ~/.bashrc — skipping GOOSE_SHELL export"
elif grep -qE '^[[:space:]]*export GOOSE_SHELL=' "$BASHRC"; then
  echo "✓ ~/.bashrc exports GOOSE_SHELL"
elif $DRY_RUN; then
  echo "  Would add 'export GOOSE_SHELL=...' to ~/.bashrc (backup: ~/.bashrc.bak.goose-env-fix.<timestamp>)"
  CHANGES=$((CHANGES + 1))
else
  tmp_rc="$(mktemp)"
  # Insert above the interactive guard AND the comment block directly above it.
  awk -v block='# Goose: use the goose-shell wrapper (full env + rm guard) for goose started from any shell\nexport GOOSE_SHELL="$HOME/.local/bin/goose-shell"\n' '
    NR == FNR { ln[NR] = $0; if (!g && $0 ~ /^\[\[ \$- != \*i\* \]\] && return/) g = NR; next }
    FNR == 1  { s = g; while (s > 1 && ln[s-1] ~ /^#/) s-- }
    !done && g && FNR == s { printf "%s\n", block; done = 1 }
    { print }
    END { if (!done) printf "\n%s", block }
  ' "$BASHRC" "$BASHRC" > "$tmp_rc"
  if bash -n "$tmp_rc" && grep -qE '^export GOOSE_SHELL=' "$tmp_rc"; then
    cp -p "$BASHRC" "${BASHRC}.bak.goose-env-fix.${TS}"
    cat "$tmp_rc" > "$BASHRC"     # keep inode, mode and any symlink
    echo "✓ Added GOOSE_SHELL export to ~/.bashrc (backup: ${BASHRC}.bak.goose-env-fix.${TS})"
  else
    echo "✗ Generated ~/.bashrc failed syntax check — left unchanged"
    ERRORS=$((ERRORS + 1))
  fi
  rm -f "$tmp_rc"
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
if $DRY_RUN; then
  if [[ $CHANGES -eq 0 && $ERRORS -eq 0 ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
    echo "✅ Goose Desktop environment fix is in place. No changes needed."
  else
    echo "DRY_RUN_RESULT=PENDING"
    [[ $CHANGES -gt 0 ]] && echo "$CHANGES change(s) would be applied."
    [[ $ERRORS -gt 0 ]] && echo "$ERRORS precondition issue(s) found."
  fi
  exit 0
else
  if [[ $ERRORS -eq 0 ]]; then
    echo "APPLY_RESULT=OK"
    echo "✅ Setup complete. Restart Goose Desktop to apply changes."
    echo ""
    echo "Post-restart verification:"
    echo "  1. In Goose Desktop, run: echo \$GOOSE_SHELL"
    echo "  2. Run: which gh && which oc"
    echo "  3. Check no fork bombs: ps aux | grep 'devbox global shellenv' | grep -v grep | wc -l"
  else
    echo "APPLY_RESULT=PARTIAL"
    echo "⚠ Setup completed with ${ERRORS} warning(s). Review above."
  fi
fi

trace_end 2>/dev/null || true
exit $ERRORS
