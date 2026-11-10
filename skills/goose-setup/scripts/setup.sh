#!/usr/bin/env bash
# setup.sh — Setup Goose persistent instructions
#
# Creates ~/.config/goose/instructions.md with default content
# and registers it in config.yaml via GOOSE_MOIM_MESSAGE_FILE.
#
# Usage: setup.sh [--check]
#   --check   Show current state without modifying anything
#
# Exit codes:
#   0 — Setup complete or already configured
#   1 — Error

set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "goose-setup" "1.5.0" 2>/dev/null || true

CONFIG_DIR="$HOME/.config/goose"
INSTRUCTIONS="$CONFIG_DIR/instructions.md"
CONFIG_YAML="$CONFIG_DIR/config.yaml"

CHECK=false
DRY_RUN=false
CHANGES=0
case "${1:-}" in
  --check) CHECK=true ;;
  --dry-run) DRY_RUN=true ;;
esac

echo "=== Goose Persistent Instructions Setup ==="
echo ""

# Step 1: Check current state
echo "1. Checking current state..."
if [[ -f "$INSTRUCTIONS" ]]; then
  lines=$(wc -l < "$INSTRUCTIONS")
  echo "   ✅ Instructions file exists ($lines lines)"
else
  echo "   ❌ Instructions file not found"
fi

if [[ -f "$CONFIG_YAML" ]]; then
  if grep -q 'GOOSE_MOIM_MESSAGE_FILE' "$CONFIG_YAML" 2>/dev/null; then
    echo "   ✅ GOOSE_MOIM_MESSAGE_FILE registered in config.yaml"
  else
    echo "   ❌ GOOSE_MOIM_MESSAGE_FILE not in config.yaml"
  fi
else
  echo "   ❌ config.yaml not found"
fi
trace_step 1 "check_state" 0 "" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  if [[ -f "$INSTRUCTIONS" ]]; then
    echo ""
    echo "   Current instructions content:"
    echo "   ---"
    head -20 "$INSTRUCTIONS" | sed 's/^/   /'
    [[ $(wc -l < "$INSTRUCTIONS") -gt 20 ]] && echo "   ... ($(wc -l < "$INSTRUCTIONS") lines total)"
  fi
  trace_end 2>/dev/null || true
  exit 0
fi

# Dry-run check
if [[ "$DRY_RUN" == true ]]; then
  [[ -f "$INSTRUCTIONS" ]] \
    && echo "[dry-run] NO CHANGE — instructions.md already exists" \
    || { echo "[dry-run] WOULD: Create $INSTRUCTIONS"; CHANGES=$((CHANGES + 1)); }
  if [[ -f "$CONFIG_YAML" ]] && grep -q 'GOOSE_MOIM_MESSAGE_FILE' "$CONFIG_YAML" 2>/dev/null; then
    echo "[dry-run] NO CHANGE — GOOSE_MOIM_MESSAGE_FILE already registered"
  elif [[ -f "$CONFIG_YAML" ]]; then
    echo "[dry-run] WOULD: Add GOOSE_MOIM_MESSAGE_FILE to config.yaml"
    CHANGES=$((CHANGES + 1))
  else
    echo "[dry-run] NO CHANGE — config.yaml not found (cannot register)"
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

# Step 2: Create instructions file
echo ""
echo "2. Creating instructions file..."
mkdir -p "$CONFIG_DIR"
if [[ -f "$INSTRUCTIONS" ]]; then
  echo "   ℹ️  File already exists — preserving current content"
else
  cat > "$INSTRUCTIONS" <<'INSTRUCTIONS_EOF'
## Path Hygiene

- **Never use explicit home directory paths** like `/home/<user>/` in scripts, configurations, or output.
- Always use `~` or `$HOME` instead.

## Git Push Safety

Before any `git push`, follow the pre-push scan workflow.
Do NOT skip the scan even if the user says "go ahead".
INSTRUCTIONS_EOF
  echo "   ✅ Created $INSTRUCTIONS"
fi
trace_step 2 "create_instructions" 0 "" 2>/dev/null || true

# Step 3: Register in config.yaml
echo ""
echo "3. Registering in config.yaml..."
if [[ ! -f "$CONFIG_YAML" ]]; then
  echo "   ❌ config.yaml not found at $CONFIG_YAML"
  echo "   Create it first or run 'goose configure'"
  trace_end 2>/dev/null || true
  exit 1
fi

if grep -q 'GOOSE_MOIM_MESSAGE_FILE' "$CONFIG_YAML" 2>/dev/null; then
  echo "   ✅ Already registered"
else
  echo "" >> "$CONFIG_YAML"
  echo "GOOSE_MOIM_MESSAGE_FILE: ~/.config/goose/instructions.md" >> "$CONFIG_YAML"
  echo "   ✅ Added GOOSE_MOIM_MESSAGE_FILE to config.yaml"
fi
trace_step 3 "register_config" 0 "" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo "Start a new Goose session to verify instructions are active."
trace_end 2>/dev/null || true
