#!/usr/bin/env bash
# setup.sh — Clone and configure aap-demo for CRC deployment
# Usage: setup.sh [--check] [--target DIR]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-aap-demo-config" "1.0.0" 2>/dev/null || true

CHECK_ONLY=false
TARGET_DIR="${HOME}/app/playground/aap-demo"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --target) TARGET_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

REPO_URL="https://github.com/RedHatOfficial/aap-demo.git"
echo "=== AAP Demo Configuration ==="
echo ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────
trace_step 1 "prerequisites" 0 "" 2>/dev/null || true

if ! command -v crc >/dev/null 2>&1; then
  echo "✗ crc not found in PATH"
  exit 1
fi
echo "✓ crc found: $(which crc)"

CRC_STATUS=$(crc status 2>/dev/null | grep 'CRC VM' | awk '{print $NF}' || echo "unknown")
echo "  CRC status: $CRC_STATUS"

# ── Step 2: Check/clone repository ──────────────────────────────────────
trace_step 2 "clone_repo" 0 "target=${TARGET_DIR}" 2>/dev/null || true

if [[ -d "$TARGET_DIR" ]]; then
  if git -C "$TARGET_DIR" remote get-url origin 2>/dev/null | grep -q 'aap-demo'; then
    echo "✓ aap-demo already cloned: $TARGET_DIR"
  else
    echo "⚠ Directory exists but is not aap-demo repo: $TARGET_DIR"
  fi
else
  if $CHECK_ONLY; then
    echo "⚠ aap-demo not cloned. Would clone to: $TARGET_DIR"
  else
    echo "  Cloning aap-demo..."
    git clone "$REPO_URL" "$TARGET_DIR"
    echo "✓ Cloned to $TARGET_DIR"
  fi
fi

# ── Step 3: Pre-flight CRC checks ──────────────────────────────────────
trace_step 3 "preflight" 0 "" 2>/dev/null || true

echo ""
echo "── Pre-flight checks ──"

# Check CRC preset
PRESET=$(crc config get preset 2>/dev/null | awk '{print $NF}' || echo "unknown")
echo "  CRC preset: $PRESET"

# Check resources
CPUS=$(crc config get cpus 2>/dev/null | awk '{print $NF}' || echo "?")
MEMORY=$(crc config get memory 2>/dev/null | awk '{print $NF}' || echo "?")
DISK=$(crc config get disk-size 2>/dev/null | awk '{print $NF}' || echo "?")
echo "  CPUs: $CPUS, Memory: ${MEMORY}MB, Disk: ${DISK}GB"

# ── Step 4: Check aap-demo configuration files ─────────────────────────
trace_step 4 "config_check" 0 "" 2>/dev/null || true

if [[ -d "$TARGET_DIR" ]]; then
  echo ""
  echo "── aap-demo config status ──"
  if [[ -f "$TARGET_DIR/.env" ]]; then
    echo "  ✓ .env file exists"
    # Check for key settings without exposing values
    grep -q 'PULL_SECRET' "$TARGET_DIR/.env" && echo "    ✓ PULL_SECRET set" || echo "    ⚠ PULL_SECRET not set"
  else
    echo "  ⚠ .env file not found (copy from .env.example)"
  fi

  if [[ -f "$TARGET_DIR/.env.example" ]]; then
    echo "  ✓ .env.example exists"
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if $CHECK_ONLY; then
  echo "✅ Pre-flight check complete."
else
  echo "✅ Setup complete. Review .env configuration before running aap-demo."
fi

trace_end 2>/dev/null || true
