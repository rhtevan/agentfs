#!/usr/bin/env bash
# install.sh — Install crcstart and crcstop wrapper commands
# Usage: install.sh [--dry-run]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-cmd" "1.0.0" 2>/dev/null || true

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
if [[ "${1:-}" == "--check" ]]; then echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true; fi

BIN_DIR="${HOME}/.local/bin"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== CRC Wrapper Commands Install ==="
echo ""

# ── Step 1: Check prerequisites ─────────────────────────────────────────
trace_step 1 "prerequisites" 0 "" 2>/dev/null || true

if command -v crc >/dev/null 2>&1; then
  echo "✓ crc found: $(which crc)"
else
  echo "⚠ crc not found in PATH"
fi

if [[ -d "$BIN_DIR" ]]; then
  echo "✓ $BIN_DIR exists"
else
  if $DRY_RUN; then
    echo "⚠ $BIN_DIR does not exist (would create)"
  else
    mkdir -p "$BIN_DIR"
    echo "✓ Created $BIN_DIR"
  fi
fi

# Check PATH includes ~/.local/bin
if echo "$PATH" | tr ':' '\n' | grep -q "$BIN_DIR"; then
  echo "✓ $BIN_DIR is in PATH"
else
  echo "⚠ $BIN_DIR is not in PATH — commands won't be found"
fi

# ── Step 2: Check/install crcstop ───────────────────────────────────────
trace_step 2 "install_crcstop" 0 "target=${BIN_DIR}/crcstop" 2>/dev/null || true

CRCSTOP="${BIN_DIR}/crcstop"
if [[ -f "$CRCSTOP" ]]; then
  echo "✓ crcstop exists ($(wc -l < "$CRCSTOP") lines)"
  if [[ -x "$CRCSTOP" ]]; then
    echo "  ✓ Is executable"
  else
    echo "  ⚠ Not executable"
    $DRY_RUN || chmod +x "$CRCSTOP"
  fi
else
  if $DRY_RUN; then
    echo "⚠ crcstop not installed"
  else
    # Extract crcstop from SKILL.md
    echo "  Installing crcstop from SKILL.md..."
    sed -n '/^## crcstop script/,/^## crcstart script/{/^```bash$/,/^```$/{/^```/d;p}}' \
      "$SKILL_DIR/SKILL.md" > "$CRCSTOP"
    chmod +x "$CRCSTOP"
    echo "✓ Installed crcstop ($(wc -l < "$CRCSTOP") lines)"
  fi
fi

# ── Step 3: Check/install crcstart ──────────────────────────────────────
trace_step 3 "install_crcstart" 0 "target=${BIN_DIR}/crcstart" 2>/dev/null || true

CRCSTART="${BIN_DIR}/crcstart"
if [[ -f "$CRCSTART" ]]; then
  echo "✓ crcstart exists ($(wc -l < "$CRCSTART") lines)"
  if [[ -x "$CRCSTART" ]]; then
    echo "  ✓ Is executable"
  else
    echo "  ⚠ Not executable"
    $DRY_RUN || chmod +x "$CRCSTART"
  fi
else
  if $DRY_RUN; then
    echo "⚠ crcstart not installed"
  else
    echo "  Installing crcstart from SKILL.md..."
    sed -n '/^## crcstart script/,/^## Changelog/{/^```bash$/,/^```$/{/^```/d;p}}' \
      "$SKILL_DIR/SKILL.md" > "$CRCSTART"
    chmod +x "$CRCSTART"
    echo "✓ Installed crcstart ($(wc -l < "$CRCSTART") lines)"
  fi
fi

# ── Step 4: Verify ──────────────────────────────────────────────────────
trace_step 4 "verify" 0 "" 2>/dev/null || true

echo ""
if $DRY_RUN; then
  if [[ -x "$CRCSTOP" && -x "$CRCSTART" ]]; then
    echo "DRY_RUN_RESULT=CONVERGED"
    echo "✅ Both crcstart and crcstop are installed. No changes needed."
  else
    echo "DRY_RUN_RESULT=PENDING"
    echo "Installation needed. Run without --dry-run to install."
  fi
  exit 0
else
  if [[ -x "$CRCSTOP" && -x "$CRCSTART" ]]; then
    echo "APPLY_RESULT=OK"
    echo "✅ Both crcstart and crcstop are installed and executable."
    echo "  crcstart: $CRCSTART"
    echo "  crcstop:  $CRCSTOP"
  else
    echo "APPLY_RESULT=PARTIAL"
    echo "⚠ Installation incomplete. Review above."
  fi
fi

trace_end 2>/dev/null || true
