#!/usr/bin/env bash
# status.sh — Read-only report of the Hermes Agent installation state.
# Usage: bash status.sh
# Exit: 0 installed (command + checkout + config) · 1 not installed / incomplete
set -uo pipefail

# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "hermes-install" "1.1.0" 2>/dev/null || true

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
MISSING=0

echo "=== Hermes Agent — STATUS ==="
echo "  HERMES_HOME: $HERMES_HOME"
echo "  Checkout:    $INSTALL_DIR"
echo

# 1. hermes command (PATH first, then the publish location used by the installer)
HERMES_BIN="$(command -v hermes 2>/dev/null || true)"
[[ -z "$HERMES_BIN" && -x "$HOME/.local/bin/hermes" ]] && HERMES_BIN="$HOME/.local/bin/hermes"
if [[ -n "$HERMES_BIN" ]] && VER="$("$HERMES_BIN" --version 2>/dev/null | head -1)" && [[ -n "$VER" ]]; then
  echo "  ✅ Command:   $HERMES_BIN ($VER)"
else
  echo "  ❌ Command:   hermes not found or not runnable"
  MISSING=$((MISSING + 1))
fi
trace_step 1 "command" "$([[ -n "$HERMES_BIN" ]] && echo 0 || echo 1)" "bin=${HERMES_BIN}" 2>/dev/null || true

# 2. git checkout
if git -C "$INSTALL_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
  REF="$(git -C "$INSTALL_DIR" describe --tags --always 2>/dev/null || git -C "$INSTALL_DIR" rev-parse --short HEAD)"
  echo "  ✅ Checkout:  $REF"
else
  echo "  ❌ Checkout:  missing or not a usable git repo"
  MISSING=$((MISSING + 1))
fi
trace_step 2 "checkout" 0 "" 2>/dev/null || true

# 3. config.yaml
if [[ -f "$HERMES_HOME/config.yaml" ]]; then
  echo "  ✅ Config:    $HERMES_HOME/config.yaml"
else
  echo "  ❌ Config:    $HERMES_HOME/config.yaml missing"
  MISSING=$((MISSING + 1))
fi

# 4. desktop app (informational — only needed for Hermes Desktop)
if compgen -G "$INSTALL_DIR/apps/desktop/release/*" >/dev/null 2>&1; then
  echo "  ✅ Desktop:   built ($INSTALL_DIR/apps/desktop/release)"
else
  echo "  ⚠️  Desktop:   not built (install.sh builds it unless --no-desktop)"
fi

# 5. bash completion (informational — install.sh writes the lazy loader)
COMP_FILE="${BASH_COMPLETION_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion}/completions/hermes"
if [[ -f "$COMP_FILE" ]]; then
  echo "  ✅ Completion: $COMP_FILE"
else
  echo "  ⚠️  Completion: not set up (install.sh writes $COMP_FILE)"
fi

# 6. existing user data (informational — shows what an install must preserve)
DATA=()
for f in state.db kanban.db skills plugins cron logs .env; do
  [[ -e "$HERMES_HOME/$f" ]] && DATA+=("$f")
done
echo "  ℹ️  Data:      ${DATA[*]:-(none)}"
trace_step 3 "config_desktop_data" 0 "missing=${MISSING}" 2>/dev/null || true

echo
if [[ $MISSING -eq 0 ]]; then
  echo "✅ Hermes Agent installed"
  trace_end 2>/dev/null || true
  exit 0
fi
echo "❌ Hermes Agent not installed or incomplete ($MISSING missing)"
trace_end 2>/dev/null || true
exit 1
