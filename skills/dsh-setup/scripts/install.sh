#!/usr/bin/env bash
# install.sh — Install pnpm and DSH to ~/.local/share/dsh/
# Usage: bash install.sh
set -euo pipefail

DSH_DIR="$HOME/.local/share/dsh"
PNPM_DIR="$HOME/.local/share/pnpm"
PNPM_BIN="$PNPM_DIR/node_modules/.bin/pnpm"
NODE="/usr/bin/node"

# --- Preflight: Node.js version ---
if [[ ! -x "$NODE" ]]; then
  echo "❌ Node.js not found at $NODE" >&2
  exit 1
fi

NODE_VERSION=$($NODE --version | sed 's/^v//')
NODE_MAJOR=$(echo "$NODE_VERSION" | cut -d. -f1)
NODE_MINOR=$(echo "$NODE_VERSION" | cut -d. -f2)

if [[ "$NODE_MAJOR" -lt 22 ]]; then
  echo "❌ Node.js >= 22.19.0 or >= 24.0.0 required (found v$NODE_VERSION)" >&2
  exit 1
fi
if [[ "$NODE_MAJOR" -eq 22 && "$NODE_MINOR" -lt 19 ]]; then
  echo "❌ Node.js 22.x requires >= 22.19.0 (found v$NODE_VERSION)" >&2
  exit 1
fi
if [[ "$NODE_MAJOR" -eq 23 ]]; then
  echo "❌ Node.js 23.x is not supported by DSH (need ^22.19.0 || >=24.0.0, found v$NODE_VERSION)" >&2
  exit 1
fi
echo "✅ Node.js v$NODE_VERSION"

# --- Install pnpm (if needed) ---
if [[ -x "$PNPM_BIN" ]]; then
  PNPM_VERSION=$($NODE "$PNPM_BIN" --version 2>/dev/null || echo "unknown")
  echo "✅ pnpm already installed ($PNPM_VERSION)"
else
  echo "📦 Installing pnpm to $PNPM_DIR..."
  mkdir -p "$PNPM_DIR"
  npm install --prefix "$PNPM_DIR" pnpm@11.7.0 2>&1 | tail -3
  if [[ ! -x "$PNPM_BIN" ]]; then
    echo "❌ pnpm installation failed" >&2
    exit 1
  fi
  echo "✅ pnpm installed ($($NODE "$PNPM_BIN" --version))"
fi

# --- Install DSH ---
if [[ -d "$DSH_DIR/node_modules/@deepseek-ai/dsh" ]]; then
  CURRENT=$($NODE "$DSH_DIR/node_modules/.bin/dsh" --version 2>/dev/null || echo "unknown")
  echo "✅ DSH already installed ($CURRENT) at $DSH_DIR"
  echo "   Run update.sh to upgrade."
  exit 0
fi

echo "📦 Installing DSH to $DSH_DIR..."
mkdir -p "$DSH_DIR"

# Create minimal package.json if missing
if [[ ! -f "$DSH_DIR/package.json" ]]; then
  echo '{"name":"dsh-local","private":true}' > "$DSH_DIR/package.json"
fi

# Install DSH via pnpm
# Strip Goose hermit from PATH to prevent its node wrapper from
# hijacking build scripts (it changes CWD to mcp-hermit dir).
CLEAN_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v 'goose.*hermit' | grep -v 'Goose.*bin' | tr '\n' ':')
CLEAN_PATH="${CLEAN_PATH%:}"

cd "$DSH_DIR"
PATH="$CLEAN_PATH" $NODE "$PNPM_BIN" add @deepseek-ai/dsh 2>&1 | tail -10

# Approve required build scripts
echo "🔨 Approving build scripts..."
PATH="$CLEAN_PATH" $NODE "$PNPM_BIN" approve-builds --all 2>&1 | tail -5

# Verify binary
if [[ ! -x "$DSH_DIR/node_modules/.bin/dsh" ]]; then
  echo "❌ DSH binary not found after install" >&2
  exit 1
fi

echo "✅ DSH installed successfully to $DSH_DIR"
echo "   Binary: $DSH_DIR/node_modules/.bin/dsh"
echo "   Next: run install-desktop.sh to create the app launcher"
