#!/usr/bin/env bash
# link-sites.sh — Generate a link token on the interior site (remote) and apply it on the edge site (local)
# Usage: bash link-sites.sh <NAMESPACE> <REMOTE_SSH_HOST>
#
# Architecture: Remote host runs the interior site (accepts inbound links).
#               Local host runs the edge site (connects outbound to remote).
#               Link token is generated on the remote interior site.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST>" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"

TOKEN_FILE=$(mktemp /tmp/link-token-XXXXXX.yaml)

# Get the remote host's reachable IP
REMOTE_IP=$(ssh "${REMOTE_SSH_HOST}" "hostname -I | awk '{print \$1}'")
echo "Interior site IP (remote): ${REMOTE_IP}"

echo ""
echo "=== Generating link token on interior site (${REMOTE_SSH_HOST}) ==="
ssh "${REMOTE_SSH_HOST}" "skupper link generate -n ${NAMESPACE} -p linux --host ${REMOTE_IP}" > "${TOKEN_FILE}"
echo "Token generated: ${TOKEN_FILE}"

echo ""
echo "=== Verifying local host can reach interior site on port 45671 ==="
nc -zv "${REMOTE_IP}" 45671 -w 5 2>&1 || {
  echo "⚠️  Cannot reach ${REMOTE_IP}:45671"
  echo "   Check firewall rules on the interior site (${REMOTE_SSH_HOST})."
  rm -f "${TOKEN_FILE}"
  exit 1
}

echo ""
echo "=== Applying link token on edge site (localhost) ==="
skupper system -n "${NAMESPACE}" -p linux apply -f "${TOKEN_FILE}"
skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | { grep -v 'WARN certificate' || true; }

echo ""
echo "=== Waiting for link to establish ==="
sleep 10

echo ""
echo "=== TCP connection check ==="
# The edge (local) connects outbound to the interior (remote) on port 45671
ss -tnp 2>/dev/null | { grep 45671 || true; } | { grep ESTAB || true; }
LINK_ESTAB=$(ss -tnp 2>/dev/null | { grep 45671 || true; } | { grep ESTAB || true; } | wc -l)
if [[ "$LINK_ESTAB" -gt 0 ]]; then
  echo "✅ TCP link established (${LINK_ESTAB} connections)"
else
  echo "⚠️  No ESTAB connection found on 45671"
fi

echo ""
echo "=== Link status (from edge site — localhost) ==="
skupper link status -n "${NAMESPACE}" -p linux

# Cleanup
rm -f "${TOKEN_FILE}"

echo ""
echo "Link setup complete. Note: status may show 'Pending' — verify with TCP check above."
