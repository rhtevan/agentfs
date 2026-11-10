#!/usr/bin/env bash
# setup.sh — Configure systemd-resolved stale DNS caching on Fedora
# Usage: sudo bash setup.sh [--dry-run]
#   or:  bash setup.sh [--dry-run] (will prompt for sudo in apply mode)
set -euo pipefail

DRY_RUN=false
CHANGES=0
ERRORS=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
  esac
done

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "fedora-dns-cache" "1.2.0" 2>/dev/null || true

CONF_DIR="/etc/systemd/resolved.conf.d"
CONF_FILE="${CONF_DIR}/fast-timeout.conf"
SERVICE="systemd-resolved"

# --- Preflight checks ---

# Verify systemd-resolved is active
if ! systemctl is-active --quiet "$SERVICE"; then
  echo "ERROR: $SERVICE is not active. This skill requires systemd-resolved." >&2
  exit 1
fi

# Check if already configured (idempotent)
if [[ -f "$CONF_FILE" ]]; then
  if grep -q 'StaleRetentionSec=3600' "$CONF_FILE" 2>/dev/null; then
    echo "✅ Stale DNS caching is already configured in $CONF_FILE"
    echo "   Current setting:"
    grep 'StaleRetentionSec' "$CONF_FILE"
    if $DRY_RUN; then
      echo ""
      echo "DRY_RUN_RESULT=CONVERGED"
    else
      echo "APPLY_RESULT=OK"
    fi
    exit 0
  fi
fi

# --- Dry-run exit ---
if $DRY_RUN; then
  echo "[dry-run] WOULD: Create $CONF_FILE with StaleRetentionSec=3600"
  CHANGES=$((CHANGES + 1))
  echo "[dry-run] WOULD: Restart $SERVICE"
  CHANGES=$((CHANGES + 1))
  echo ""
  echo "DRY_RUN_RESULT=PENDING"
  echo "Changes: ${CHANGES}"
  exit 0
fi

# --- Escalate to root if needed ---

if [[ $EUID -ne 0 ]]; then
  echo "Root access required. Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

# --- Apply configuration ---

mkdir -p "$CONF_DIR"

cat > "$CONF_FILE" <<'EOF'
# Reduce DNS pain when ISP connection drops
# Installed by: fedora-dns-cache skill
[Resolve]
# Serve stale (expired) cached records when upstream DNS is unreachable
# rather than waiting for a timeout. Stale records served for up to 1 hour.
StaleRetentionSec=3600
EOF

echo "✅ Created $CONF_FILE"

# --- Restart resolved ---

systemctl restart "$SERVICE"
echo "✅ Restarted $SERVICE"

# --- Verify ---

if systemd-analyze cat-config systemd/resolved.conf 2>/dev/null | grep -q 'StaleRetentionSec=3600'; then
  echo "✅ Verified: StaleRetentionSec=3600 is active"
else
  echo "⚠️  Warning: Could not verify StaleRetentionSec setting" >&2
  ERRORS=$((ERRORS + 1))
fi

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo "APPLY_RESULT=OK"
  echo "Done. DNS lookups will now use stale cache when upstream is unreachable."
else
  echo "APPLY_RESULT=PARTIAL"
fi
