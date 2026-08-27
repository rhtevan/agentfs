#!/usr/bin/env bash
# crc-cleanup.sh — Reclaim disk space inside the CRC VM
# Usage: bash crc-cleanup.sh [--dry-run]
#
# Actions:
#   1. Prune unused CRI-O container images (crictl rmi --prune)
#   2. Vacuum systemd journal logs to 256 MB
#   3. Delete API server logs older than 3 days
#   4. Delete completed/succeeded pods via oc
#   5. Report disk usage before and after
#
# Requires: CRC VM running, SSH accessible on 127.0.0.1:2222
set -euo pipefail

SSH_KEY="$HOME/.crc/machines/crc/id_ed25519"
SSH_HOST="127.0.0.1"
SSH_PORT="2222"
SSH_USER="core"
DRY_RUN="${1:-}"
JOURNAL_MAX="256M"

# --- helpers ---

ssh_cmd() {
  ssh -i "$SSH_KEY" \
      -o StrictHostKeyChecking=no \
      -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR \
      -p "$SSH_PORT" \
      "${SSH_USER}@${SSH_HOST}" "$@"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# --- pre-flight ---

[[ -f "$SSH_KEY" ]] || die "SSH key not found: $SSH_KEY"

# Check CRC is running
if ! crc status 2>/dev/null | grep -q "Running"; then
  die "CRC VM is not running. Start it first."
fi

# Test SSH connectivity
ssh_cmd "echo ssh_ok" >/dev/null 2>&1 || die "Cannot SSH into CRC VM on ${SSH_HOST}:${SSH_PORT}"

# --- capture before state ---

echo "=== CRC Disk Usage (Before) ==="
crc status 2>/dev/null | grep -E "Disk Usage|RAM Usage"
echo ""

DISK_BEFORE=$(ssh_cmd "df --output=used / | tail -1" 2>/dev/null | tr -d ' ')

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  echo "[DRY RUN] Would perform the following cleanup actions:"
  echo "  1. Prune unused container images (crictl rmi --prune)"
  echo "  2. Vacuum journal logs to $JOURNAL_MAX"
  echo "  3. Delete API server logs older than 3 days"
  echo "  4. Delete completed/succeeded pods (oc)"
  exit 0
fi

# --- cleanup inside VM ---

echo "--- Pruning unused container images ---"
PRUNED=$(ssh_cmd "sudo crictl rmi --prune 2>&1 | wc -l" 2>/dev/null)
echo "  Pruned $PRUNED image(s)"

echo "--- Vacuuming journal logs (keeping $JOURNAL_MAX) ---"
JOURNAL_FREED=$(ssh_cmd "sudo journalctl --vacuum-size=$JOURNAL_MAX 2>&1 | grep -oP 'freed \K[^.]+' | tail -1" 2>/dev/null || echo "0B")
echo "  Journal freed: ${JOURNAL_FREED:-0B}"

echo "--- Cleaning old API server logs (>3 days) ---"
ssh_cmd "sudo find /var/log/kube-apiserver/ /var/log/openshift-apiserver/ /var/log/oauth-apiserver/ -name '*.log' -mtime +3 -delete 2>/dev/null; echo done" 2>/dev/null
echo "  Old API server logs cleaned"

# --- cleanup via oc (runs on host) ---

echo "--- Deleting completed/succeeded pods ---"
SUCCEEDED=$(oc get pods --all-namespaces --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
if [[ "$SUCCEEDED" -gt 0 ]]; then
  oc delete pods --all-namespaces --field-selector=status.phase=Succeeded --wait=false 2>/dev/null | wc -l | xargs -I{} echo "  Deleted {} completed pod(s)"
else
  echo "  No completed pods to delete"
fi

FAILED=$(oc get pods --all-namespaces --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
if [[ "$FAILED" -gt 0 ]]; then
  oc delete pods --all-namespaces --field-selector=status.phase=Failed --wait=false 2>/dev/null | wc -l | xargs -I{} echo "  Deleted {} failed pod(s)"
else
  echo "  No failed pods to delete"
fi

# --- capture after state ---

echo ""
echo "=== CRC Disk Usage (After) ==="
crc status 2>/dev/null | grep -E "Disk Usage|RAM Usage"

DISK_AFTER=$(ssh_cmd "df --output=used / | tail -1" 2>/dev/null | tr -d ' ')

if [[ -n "$DISK_BEFORE" && -n "$DISK_AFTER" ]]; then
  FREED_KB=$((DISK_BEFORE - DISK_AFTER))
  if [[ $FREED_KB -gt 1048576 ]]; then
    FREED_HUMAN="$((FREED_KB / 1048576)) GB"
  elif [[ $FREED_KB -gt 1024 ]]; then
    FREED_HUMAN="$((FREED_KB / 1024)) MB"
  else
    FREED_HUMAN="${FREED_KB} KB"
  fi
  echo ""
  echo "Total space reclaimed: ~${FREED_HUMAN}"
fi

echo ""
echo "Cleanup complete."
