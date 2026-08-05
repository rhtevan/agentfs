#!/usr/bin/env bash
# teardown.sh — Stop Skupper sites and clean up systemd state
# Usage: bash teardown.sh <NAMESPACE> <REMOTE_SSH_HOST>
#
# Architecture: Remote=interior(hub), Local=edge.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST>" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"

echo "=== Stopping local site (edge) ==="
skupper system -n "${NAMESPACE}" -p linux stop 2>/dev/null || true

echo ""
echo "=== Stopping remote site (interior) ==="
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux stop" 2>/dev/null || true

echo ""
echo "=== Cleaning up systemd state ==="
systemctl --user reset-failed "skupper-${NAMESPACE}.service" 2>/dev/null || true
systemctl --user daemon-reload
ssh "${REMOTE_SSH_HOST}" "systemctl --user reset-failed skupper-${NAMESPACE}.service 2>/dev/null || true; systemctl --user daemon-reload"

# Verify
echo ""
echo "=== Verification ==="

LOCAL_PROC=$(pgrep -c skrouterd 2>/dev/null || true)
LOCAL_PROC=$(echo "$LOCAL_PROC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$LOCAL_PROC" ]] && LOCAL_PROC=0

REMOTE_PROC=$(ssh "${REMOTE_SSH_HOST}" 'pgrep -c skrouterd 2>/dev/null || true')
REMOTE_PROC=$(echo "$REMOTE_PROC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$REMOTE_PROC" ]] && REMOTE_PROC=0

LOCAL_SVC=$(systemctl --user list-units --all 2>/dev/null | { grep -c "skupper-${NAMESPACE}" || true; })
LOCAL_SVC=$(echo "$LOCAL_SVC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$LOCAL_SVC" ]] && LOCAL_SVC=0

REMOTE_SVC=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user list-units --all 2>/dev/null | grep -c skupper-${NAMESPACE} || true" 2>/dev/null)
REMOTE_SVC=$(echo "$REMOTE_SVC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$REMOTE_SVC" ]] && REMOTE_SVC=0

echo "localhost:      skrouterd processes=$LOCAL_PROC  systemd units=$LOCAL_SVC"
echo "${REMOTE_SSH_HOST}: skrouterd processes=$REMOTE_PROC  systemd units=$REMOTE_SVC"

if [[ "$LOCAL_PROC" == "0" && "$REMOTE_PROC" == "0" && "$LOCAL_SVC" == "0" && "$REMOTE_SVC" == "0" ]]; then
  echo "✅ All Skupper resources cleaned up"
else
  echo "⚠️  Some resources may still be present"
fi
