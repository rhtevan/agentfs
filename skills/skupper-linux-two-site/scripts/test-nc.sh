#!/usr/bin/env bash
# test-nc.sh — Test inter-site connectivity using nc (netcat) through the Skupper VAN
# Usage: bash test-nc.sh <NAMESPACE> <REMOTE_SSH_HOST> <LOCAL_SITE_NAME> [TEST_PORT] [ROUTING_KEY]
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST> <LOCAL_SITE_NAME> [TEST_PORT] [ROUTING_KEY]" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"
LOCAL_SITE_NAME="$3"
TEST_PORT="${4:-9090}"
ROUTING_KEY="${5:-nc-test}"

TEST_MSG="hello from ${LOCAL_SITE_NAME} via skupper VAN"

# --- Create Connector on remote ---
echo "=== Creating Connector on remote ==="
CONNECTOR_YAML=$(mktemp /tmp/connector-XXXXXX.yaml)
cat > "${CONNECTOR_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: nc-connector
spec:
  routingKey: ${ROUTING_KEY}
  port: ${TEST_PORT}
  host: localhost
EOF

REMOTE_CONNECTOR="/tmp/connector-nc.yaml"
scp -q "${CONNECTOR_YAML}" "${REMOTE_SSH_HOST}:${REMOTE_CONNECTOR}"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux apply -f ${REMOTE_CONNECTOR}"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux reload" 2>&1 | grep -v 'WARN certificate'
sleep 2

# --- Create Listener on localhost ---
echo ""
echo "=== Creating Listener on localhost ==="
LISTENER_YAML=$(mktemp /tmp/listener-XXXXXX.yaml)
cat > "${LISTENER_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: nc-listener
spec:
  routingKey: ${ROUTING_KEY}
  host: localhost
  port: ${TEST_PORT}
EOF

skupper system -n "${NAMESPACE}" -p linux apply -f "${LISTENER_YAML}"
skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | grep -v 'WARN certificate'
sleep 2

# Verify listener port
echo ""
echo "=== Verifying listener port ==="
ss -tlnp | grep "${TEST_PORT}" || { echo "❌ Port ${TEST_PORT} not listening"; exit 1; }

# --- Start nc listener on remote ---
echo ""
echo "=== Starting nc listener on remote ==="
ssh "${REMOTE_SSH_HOST}" "nohup nc -l -k -p ${TEST_PORT} > /tmp/nc-received.txt 2>&1 &"
sleep 2

# --- Send test message ---
echo ""
echo "=== Sending test message ==="
echo "${TEST_MSG}" | nc -w 3 localhost "${TEST_PORT}"
sleep 2

# --- Verify ---
echo ""
echo "=== Verifying message received ==="
RECEIVED=$(ssh "${REMOTE_SSH_HOST}" 'cat /tmp/nc-received.txt 2>/dev/null' || true)

if [[ "$RECEIVED" == "$TEST_MSG" ]]; then
  echo "✅ Message received: ${RECEIVED}"
  RESULT=0
else
  echo "❌ Expected: ${TEST_MSG}"
  echo "   Got:      ${RECEIVED:-<empty>}"
  RESULT=1
fi

# --- Cleanup test resources ---
echo ""
echo "=== Cleaning up test resources ==="
ssh "${REMOTE_SSH_HOST}" 'pkill -f "nc -l" 2>/dev/null || true'
ssh "${REMOTE_SSH_HOST}" 'rm -f /tmp/nc-received.txt'
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux delete -f ${REMOTE_CONNECTOR}" 2>/dev/null || true
skupper system -n "${NAMESPACE}" -p linux delete -f "${LISTENER_YAML}" 2>/dev/null || true
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux reload" 2>&1 | grep -v 'WARN certificate'
skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | grep -v 'WARN certificate'

# Cleanup temp files
rm -f "${CONNECTOR_YAML}" "${LISTENER_YAML}"

echo ""
if [[ $RESULT -eq 0 ]]; then
  echo "✅ Inter-site nc test PASSED"
else
  echo "❌ Inter-site nc test FAILED"
fi
exit $RESULT
