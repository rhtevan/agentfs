#!/usr/bin/env bash
# teardown.sh — Stop Skupper sites and clean up systemd state
# Usage: bash teardown.sh <NAMESPACE> <REMOTE_SSH_HOST> [--full]
#   --full: also remove firewall rule (prompts for FIREWALL_ZONE)
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST> [--full]" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"
FULL="${3:-}"

echo "=== Stopping remote site ==="
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux stop" 2>/dev/null || true

echo ""
echo "=== Stopping local site ==="
skupper system -n "${NAMESPACE}" -p linux stop 2>/dev/null || true

echo ""
echo "=== Cleaning up systemd state ==="
systemctl --user reset-failed "skupper-${NAMESPACE}.service" 2>/dev/null || true
systemctl --user daemon-reload

ssh "${REMOTE_SSH_HOST}" "systemctl --user reset-failed skupper-${NAMESPACE}.service 2>/dev/null || true; systemctl --user daemon-reload"

# Verify
echo ""
echo "=== Verification ==="

LOCAL_PROC=$(pgrep -c skrouterd 2>/dev/null || echo 0)
REMOTE_PROC=$(ssh "${REMOTE_SSH_HOST}" 'pgrep -c skrouterd 2>/dev/null || echo 0')

LOCAL_SVC=$(systemctl --user list-units --all 2>/dev/null | grep -c "skupper-${NAMESPACE}" || echo 0)
REMOTE_SVC=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user list-units --all 2>/dev/null | grep -c skupper-${NAMESPACE}" || echo 0)

echo "localhost:  skrouterd processes=$LOCAL_PROC  systemd units=$LOCAL_SVC"
echo "remote:    skrouterd processes=$REMOTE_PROC  systemd units=$REMOTE_SVC"

if [[ "$LOCAL_PROC" == "0" && "$REMOTE_PROC" == "0" && "$LOCAL_SVC" == "0" && "$REMOTE_SVC" == "0" ]]; then
  echo "✅ All Skupper resources cleaned up"
else
  echo "⚠️  Some resources may still be present"
fi

if [[ "$FULL" == "--full" ]]; then
  echo ""
  echo "=== Firewall cleanup ==="
  echo "To remove the firewall rule, run:"
  echo "  sudo firewall-cmd --zone=<ZONE> --remove-port=45671/tcp --permanent"
  echo "  sudo firewall-cmd --reload"
fi
