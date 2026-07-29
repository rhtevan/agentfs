#!/usr/bin/env bash
# setup.sh — Configure systemd-resolved stale DNS caching on Fedora
# Usage: sudo bash setup.sh
#   or:  bash setup.sh  (will prompt for sudo)
set -euo pipefail

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
    exit 0
  fi
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
  exit 1
fi

echo ""
echo "Done. DNS lookups will now use stale cache when upstream is unreachable."
