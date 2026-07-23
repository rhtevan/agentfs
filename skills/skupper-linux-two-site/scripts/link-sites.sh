#!/usr/bin/env bash
# link-sites.sh — Generate a link token on the interior site and apply it on the edge site
# Usage: bash link-sites.sh <NAMESPACE> <LOCAL_IP> <REMOTE_SSH_HOST>
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <NAMESPACE> <LOCAL_IP> <REMOTE_SSH_HOST>" >&2
  echo "  LOCAL_IP: Reachable IP of the interior site" >&2
  exit 2
fi

NAMESPACE="$1"
LOCAL_IP="$2"
REMOTE_SSH_HOST="$3"

TOKEN_FILE=$(mktemp /tmp/link-token-XXXXXX.yaml)

echo "=== Generating link token on interior site ==="
skupper link generate -n "${NAMESPACE}" -p linux --host "${LOCAL_IP}" > "${TOKEN_FILE}"
echo "Token generated: ${TOKEN_FILE}"

echo ""
echo "=== Verifying remote can reach interior site on port 45671 ==="
ssh "${REMOTE_SSH_HOST}" "nc -zv ${LOCAL_IP} 45671 -w 5" 2>&1 || {
  echo "⚠️  Remote host cannot reach ${LOCAL_IP}:45671"
  echo "   Check firewall rules on the interior site."
  rm -f "${TOKEN_FILE}"
  exit 1
}

echo ""
echo "=== Applying link token on edge site ==="
REMOTE_TOKEN="/tmp/link-token.yaml"
scp -q "${TOKEN_FILE}" "${REMOTE_SSH_HOST}:${REMOTE_TOKEN}"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux apply -f ${REMOTE_TOKEN}"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux reload" 2>&1 | grep -v 'WARN certificate'

echo ""
echo "=== Waiting for link to establish ==="
sleep 10

echo ""
echo "=== TCP connection check ==="
ss -tnp | grep 45671 | grep ESTAB && echo "✅ TCP link established" || echo "⚠️  No ESTAB connection found on 45671"

echo ""
echo "=== Link status (from edge site) ==="
ssh "${REMOTE_SSH_HOST}" "skupper link status -n ${NAMESPACE} -p linux"

# Cleanup
rm -f "${TOKEN_FILE}"

echo ""
echo "Link setup complete. Note: status may show 'Pending' — verify with TCP check above."
