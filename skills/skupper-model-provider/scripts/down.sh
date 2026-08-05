#!/usr/bin/env bash
# down.sh — Idempotent teardown of Skupper VAN + remote model runtime
# Usage: bash down.sh <NAMESPACE> <REMOTE_SSH_HOST>
#
# Architecture: Local=edge, Remote=interior/hub.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST>" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"

# ============================================================
# Phase 1: Remove Skupper Connector + Listener
# ============================================================
echo "══════════════════════════════════════════════════════════"
echo "Phase 1: Remove Skupper Connector + Listener"
echo "══════════════════════════════════════════════════════════"

# Remove Connector on remote (interior)
CONNECTOR_YAML=$(mktemp /tmp/connector-XXXXXX.yaml)
cat > "${CONNECTOR_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: model-connector
spec:
  routingKey: model-api
  port: 8000
  host: localhost
EOF

scp -q "${CONNECTOR_YAML}" "${REMOTE_SSH_HOST}:/tmp/model-connector.yaml"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux delete -f /tmp/model-connector.yaml" 2>/dev/null || true
rm -f "${CONNECTOR_YAML}"
echo "✅ Connector removed (or was not present)"

# Remove Listener on localhost (edge)
LISTENER_YAML=$(mktemp /tmp/listener-XXXXXX.yaml)
cat > "${LISTENER_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: model-listener
spec:
  routingKey: model-api
  host: localhost
  port: 8000
EOF

skupper system -n "${NAMESPACE}" -p linux delete -f "${LISTENER_YAML}" 2>/dev/null || true
rm -f "${LISTENER_YAML}"
echo "✅ Listener removed (or was not present)"

# Reload both sides
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux reload" 2>&1 | { grep -v 'WARN certificate' || true; }
skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | { grep -v 'WARN certificate' || true; }

# ============================================================
# Phase 2: Stop Model Runtime on Remote
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 2: Stop Model Runtime on ${REMOTE_SSH_HOST}"
echo "══════════════════════════════════════════════════════════"

# Stop all model containers (they share port 8000)
for ALIAS in g350m g1b g8b; do
  CONTAINER="model-${ALIAS}"
  RUNNING=$(ssh "${REMOTE_SSH_HOST}" "podman ps --filter name=${CONTAINER} --filter status=running --format '{{.Names}}' 2>/dev/null" || true)
  if [[ -n "$RUNNING" ]]; then
    echo "→ Stopping ${CONTAINER}..."
    ssh "${REMOTE_SSH_HOST}" "podman stop ${CONTAINER}" 2>/dev/null || true
    echo "✅ ${CONTAINER} stopped"
  else
    echo "  ${CONTAINER}: not running"
  fi
done

# ============================================================
# Phase 3: Stop Skupper Sites
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 3: Stop Skupper Sites"
echo "══════════════════════════════════════════════════════════"

# Stop local site (edge) first
LOCAL_SVC=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || echo "inactive")
if [[ "$LOCAL_SVC" == "active" ]]; then
  echo "→ Stopping local site (edge)..."
  skupper system -n "${NAMESPACE}" -p linux stop 2>/dev/null || true
  echo "✅ Local site stopped"
else
  echo "  Local site: already stopped"
fi

# Stop remote site (interior)
REMOTE_SVC=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null || echo inactive")
if [[ "$REMOTE_SVC" == "active" ]]; then
  echo "→ Stopping remote site (interior)..."
  ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux stop" 2>/dev/null || true
  echo "✅ Remote site stopped"
else
  echo "  Remote site: already stopped"
fi

# ============================================================
# Phase 4: Clean up systemd state
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 4: Clean up systemd state"
echo "══════════════════════════════════════════════════════════"

systemctl --user reset-failed "skupper-${NAMESPACE}.service" 2>/dev/null || true
systemctl --user daemon-reload
ssh "${REMOTE_SSH_HOST}" "systemctl --user reset-failed skupper-${NAMESPACE}.service 2>/dev/null || true; systemctl --user daemon-reload"
echo "✅ systemd state cleaned"

# ============================================================
# Verification
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Verification"
echo "══════════════════════════════════════════════════════════"

LOCAL_PROC=$(pgrep -c skrouterd 2>/dev/null || true)
LOCAL_PROC=${LOCAL_PROC:-0}
LOCAL_PROC=$(echo "$LOCAL_PROC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$LOCAL_PROC" ]] && LOCAL_PROC=0

REMOTE_PROC=$(ssh "${REMOTE_SSH_HOST}" 'pgrep -c skrouterd 2>/dev/null || true')
REMOTE_PROC=${REMOTE_PROC:-0}
REMOTE_PROC=$(echo "$REMOTE_PROC" | tr -d '\n' | tr -cd '0-9')
[[ -z "$REMOTE_PROC" ]] && REMOTE_PROC=0

REMOTE_MODELS=$(ssh "${REMOTE_SSH_HOST}" 'podman ps --filter name=model- --filter status=running --format "{{.Names}}" 2>/dev/null' || true)

echo "localhost:      skrouterd processes=${LOCAL_PROC}"
echo "${REMOTE_SSH_HOST}: skrouterd processes=${REMOTE_PROC}"
if [[ -n "$REMOTE_MODELS" ]]; then
  echo "${REMOTE_SSH_HOST}: running models=${REMOTE_MODELS}"
else
  echo "${REMOTE_SSH_HOST}: running models=none"
fi

if [[ "$LOCAL_PROC" == "0" && "$REMOTE_PROC" == "0" && -z "$REMOTE_MODELS" ]]; then
  echo ""
  echo "✅ Skupper Model Provider is DOWN — all resources stopped"
else
  echo ""
  echo "⚠️  Some resources may still be active"
fi
