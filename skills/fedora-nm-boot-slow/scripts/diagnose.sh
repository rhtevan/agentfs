#!/usr/bin/env bash
# diagnose.sh — Diagnose NM-wait-online boot delay on Fedora
# Usage: diagnose.sh [--check] [--fix]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "fedora-nm-boot-slow" "1.0.0" 2>/dev/null || true

CHECK_ONLY=false
APPLY_FIX=false

for arg in "$@"; do
  case "$arg" in
    --check) CHECK_ONLY=true ;;
    --fix) APPLY_FIX=true ;;
  esac
done

echo "=== NM-wait-online Boot Delay Diagnosis ==="
echo ""

# ── Step 1: Check boot blame ────────────────────────────────────────────
trace_step 1 "boot_blame" 0 "" 2>/dev/null || true

echo "── Top 10 boot services by time ──"
systemd-analyze blame 2>/dev/null | head -10
echo ""

NM_TIME=$(systemd-analyze blame 2>/dev/null | grep 'NetworkManager-wait-online' | awk '{print $1}' || echo "0s")
echo "NM-wait-online time: $NM_TIME"

# Parse seconds from time string
NM_SECS=$(echo "$NM_TIME" | sed 's/min/m/;s/s$//' | awk -F'[hm]' '{
  if (NF==3) print $1*3600+$2*60+$3;
  else if (NF==2) print $1*60+$2;
  else print $1
}')

if (( $(echo "$NM_SECS > 3" | bc -l 2>/dev/null || echo 0) )); then
  echo "⚠ NM-wait-online is a significant bottleneck (>3s)"
else
  echo "✓ NM-wait-online is not a significant bottleneck (≤3s)"
fi

# ── Step 2: Check critical chain ────────────────────────────────────────
trace_step 2 "critical_chain" 0 "" 2>/dev/null || true

echo ""
echo "── Critical chain (first 15 lines) ──"
systemd-analyze critical-chain 2>/dev/null | head -15
echo ""

# ── Step 3: Check auto-connected interfaces ─────────────────────────────
trace_step 3 "autoconnect_interfaces" 0 "" 2>/dev/null || true

echo "── Auto-connected interfaces ──"
nmcli -f NAME,TYPE,DEVICE con show --active 2>/dev/null || echo "  (nmcli not available)"
echo ""

echo "── Connections with autoconnect=yes ──"
nmcli -t -f NAME,connection.autoconnect con show 2>/dev/null | grep ':yes' | cut -d: -f1 | while read name; do
  type=$(nmcli -t -f connection.type con show "$name" 2>/dev/null | cut -d: -f2)
  echo "  $name ($type)"
done
echo ""

# ── Step 4: Check NM-wait-online service status ─────────────────────────
trace_step 4 "nm_wait_online_status" 0 "" 2>/dev/null || true

echo "── NM-wait-online service ──"
if systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
  echo "  Status: enabled"
  if systemctl is-active NetworkManager-wait-online.service >/dev/null 2>&1; then
    echo "  Active: yes"
  else
    echo "  Active: no (completed or not started)"
  fi
else
  echo "  Status: disabled (already fixed)"
fi

# ── Step 5: Check for common fixes ──────────────────────────────────────
trace_step 5 "check_fixes" 0 "" 2>/dev/null || true

echo ""
echo "── Fix options ──"

# Option A: Disable NM-wait-online entirely
if systemctl is-enabled NetworkManager-wait-online.service >/dev/null 2>&1; then
  echo "  [A] Disable NM-wait-online service (recommended for desktops)"
  echo "      sudo systemctl disable NetworkManager-wait-online.service"
  if $APPLY_FIX; then
    sudo systemctl disable NetworkManager-wait-online.service 2>/dev/null && \
      echo "      ✓ Disabled" || echo "      ✗ Failed (need sudo)"
  fi
else
  echo "  [A] Already disabled ✓"
fi

# Option B: Set timeout
NM_CONF="/etc/NetworkManager/conf.d/90-wait-online-timeout.conf"
if [[ -f "$NM_CONF" ]]; then
  echo "  [B] Timeout config exists: $NM_CONF"
  cat "$NM_CONF" | sed 's/^/      /'
else
  echo "  [B] Set wait-online timeout (alternative to full disable)"
  echo "      Create $NM_CONF with:"
  echo "      [connection]"
  echo "      wait-online-timeout=5"
fi

# Option C: Mark non-essential connections
echo "  [C] Mark VPN/bridge connections as non-essential:"
nmcli -t -f NAME,connection.autoconnect con show 2>/dev/null | grep ':yes' | cut -d: -f1 | while read name; do
  type=$(nmcli -t -f connection.type con show "$name" 2>/dev/null | cut -d: -f2)
  case "$type" in
    vpn|bridge|tun|bond)
      echo "      nmcli con modify \"$name\" connection.wait-device-timeout 0"
      ;;
  esac
done

echo ""
echo "=== Diagnosis complete ==="

trace_end 2>/dev/null || true
