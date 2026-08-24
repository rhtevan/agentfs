#!/usr/bin/env bash
# update.sh — Update DSH to the latest version
# Usage: bash update.sh
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
PNPM_BIN="$HOME/.local/share/pnpm/node_modules/.bin/pnpm"
NODE="/usr/bin/node"

# --- Preflight ---
if [[ ! -d "$DSH_DIR/node_modules/@deepseek-ai/dsh" ]]; then
  echo "❌ DSH not installed at $DSH_DIR. Run install.sh first." >&2
  exit 1
fi

if [[ ! -x "$PNPM_BIN" ]]; then
  echo "❌ pnpm not found at $PNPM_BIN. Run install.sh first." >&2
  exit 1
fi

# --- Strip Goose hermit from PATH ---
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'goose.*hermit' | grep -v 'Goose.*bin' | tr '\n' ':')
CLEAN_PATH="${CLEAN_PATH%:}"

# --- Show current version ---
OLD_VERSION=$(cd "$DSH_DIR" && PATH="$CLEAN_PATH" ./node_modules/.bin/dsh --version 2>/dev/null || echo "unknown")
echo "📦 Current DSH version: $OLD_VERSION"

# --- Update ---
echo "🔄 Updating DSH..."
cd "$DSH_DIR"
PATH="$CLEAN_PATH" $NODE "$PNPM_BIN" update @deepseek-ai/dsh 2>&1 | tail -10

# Re-approve builds if needed
PATH="$CLEAN_PATH" $NODE "$PNPM_BIN" approve-builds --all 2>&1 | tail -3

# --- Show new version ---
NEW_VERSION=$(cd "$DSH_DIR" && PATH="$CLEAN_PATH" ./node_modules/.bin/dsh --version 2>/dev/null || echo "unknown")
echo ""
if [[ "$OLD_VERSION" == "$NEW_VERSION" ]]; then
  echo "✅ DSH is already at the latest version ($NEW_VERSION)"
else
  echo "✅ DSH updated: $OLD_VERSION → $NEW_VERSION"
fi
