#!/usr/bin/env bash
# up.sh — Idempotent bring-up of Skupper VAN + remote model runtime
# Usage: bash up.sh <NAMESPACE> <REMOTE_SSH_HOST> <LOCAL_SITE_NAME> <REMOTE_SITE_NAME> <MODEL_ALIAS>
#
# Architecture: Local=edge (outbound, no firewall needed)
#               Remote=interior/hub (accepts inbound links, runs model)
set -euo pipefail

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <NAMESPACE> <REMOTE_SSH_HOST> <LOCAL_SITE_NAME> <REMOTE_SITE_NAME> <MODEL_ALIAS>" >&2
  exit 2
fi

NAMESPACE="$1"
REMOTE_SSH_HOST="$2"
LOCAL_SITE_NAME="$3"
REMOTE_SITE_NAME="$4"
MODEL_ALIAS="$5"

ROUTING_KEY="model-api"
MODEL_PORT=8000

FAILED=0

# ============================================================
# Phase 1: Verify Prerequisites
# ============================================================
echo "══════════════════════════════════════════════════════════"
echo "Phase 1: Verify Prerequisites"
echo "══════════════════════════════════════════════════════════"

for cmd in skrouterd skupper; do
  if command -v $cmd &>/dev/null; then
    echo "✅ localhost: $cmd found"
  else
    echo "❌ localhost: $cmd not found"; FAILED=1
  fi
  RVER=$(ssh "${REMOTE_SSH_HOST}" "command -v $cmd &>/dev/null && echo found || echo missing" 2>/dev/null)
  if [[ "$RVER" == "found" ]]; then
    echo "✅ ${REMOTE_SSH_HOST}: $cmd found"
  else
    echo "❌ ${REMOTE_SSH_HOST}: $cmd not found"; FAILED=1
  fi
done

# Check model container exists on remote
MODEL_CONTAINER="model-${MODEL_ALIAS}"
REMOTE_CONTAINER_EXISTS=$(ssh "${REMOTE_SSH_HOST}" "podman ps -a --filter name=${MODEL_CONTAINER} --format '{{.Names}}' 2>/dev/null" || true)
if [[ -z "$REMOTE_CONTAINER_EXISTS" ]]; then
  echo "❌ Model container '${MODEL_CONTAINER}' does not exist on ${REMOTE_SSH_HOST}"
  echo "   Run 'model setup ${MODEL_ALIAS} on ${REMOTE_SSH_HOST}' first."
  FAILED=1
else
  echo "✅ Model container '${MODEL_CONTAINER}' exists on ${REMOTE_SSH_HOST}"
fi

if [[ $FAILED -ne 0 ]]; then
  echo ""
  echo "❌ Prerequisites check failed. Aborting."
  exit 1
fi

# ============================================================
# Phase 2: Create Sites (Idempotent)
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 2: Create / Verify Skupper Sites"
echo "══════════════════════════════════════════════════════════"

# --- Remote (Interior/Hub) site ---
REMOTE_SVC_STATUS=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null || echo inactive")
if [[ "$REMOTE_SVC_STATUS" == "active" ]]; then
  echo "✅ Remote interior site already running (skupper-${NAMESPACE}.service)"
else
  echo "→ Creating interior site '${REMOTE_SITE_NAME}' on ${REMOTE_SSH_HOST}..."
  REMOTE_SITE_YAML=$(mktemp /tmp/site-remote-XXXXXX.yaml)
  cat > "$REMOTE_SITE_YAML" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${REMOTE_SITE_NAME}
spec:
  linkAccess: default
EOF
  scp -q "$REMOTE_SITE_YAML" "${REMOTE_SSH_HOST}:/tmp/site-remote.yaml"
  ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux apply -f /tmp/site-remote.yaml"
  ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux start"
  rm -f "$REMOTE_SITE_YAML"
  sleep 3
  REMOTE_SVC_STATUS=$(ssh "${REMOTE_SSH_HOST}" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null || echo inactive")
  if [[ "$REMOTE_SVC_STATUS" == "active" ]]; then
    echo "✅ Remote interior site started"
  else
    echo "❌ Failed to start remote interior site"; exit 1
  fi
fi

# Check ports on remote (interior)
REMOTE_PORT_CHECK=$(ssh "${REMOTE_SSH_HOST}" 'ss -tlnp | grep -q 45671 && echo yes || echo no' 2>/dev/null)
if [[ "$REMOTE_PORT_CHECK" == "yes" ]]; then
  echo "✅ Interior port 45671 listening on ${REMOTE_SSH_HOST}"
else
  echo "⚠️  Port 45671 not listening on ${REMOTE_SSH_HOST}"
fi

# --- Local (Edge) site ---
LOCAL_SVC_STATUS=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || echo "inactive")
if [[ "$LOCAL_SVC_STATUS" == "active" ]]; then
  echo "✅ Local edge site already running (skupper-${NAMESPACE}.service)"
else
  echo "→ Creating edge site '${LOCAL_SITE_NAME}' in namespace '${NAMESPACE}'..."
  LOCAL_SITE_YAML=$(mktemp /tmp/site-local-XXXXXX.yaml)
  cat > "$LOCAL_SITE_YAML" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: ${LOCAL_SITE_NAME}
spec:
  edge: true
EOF
  skupper system -n "${NAMESPACE}" -p linux apply -f "$LOCAL_SITE_YAML"
  skupper system -n "${NAMESPACE}" -p linux start
  rm -f "$LOCAL_SITE_YAML"
  sleep 3
  LOCAL_SVC_STATUS=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || echo "inactive")
  if [[ "$LOCAL_SVC_STATUS" == "active" ]]; then
    echo "✅ Local edge site started"
  else
    echo "❌ Failed to start local edge site"; exit 1
  fi
fi

# ============================================================
# Phase 3: Firewall Check (Interior Site — Remote Host)
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 3: Firewall Check (${REMOTE_SSH_HOST})"
echo "══════════════════════════════════════════════════════════"

# Check firewall on remote host
REMOTE_FW_OPEN=$(ssh "${REMOTE_SSH_HOST}" 'for zone in $(firewall-cmd --get-active-zones 2>/dev/null | grep -v "^ " | tr -d ":"); do if firewall-cmd --zone="$zone" --query-port=45671/tcp &>/dev/null; then echo open; exit 0; fi; done; echo closed' 2>/dev/null || echo "unknown")

if [[ "$REMOTE_FW_OPEN" == "open" ]]; then
  echo "✅ Firewall port 45671/tcp open on ${REMOTE_SSH_HOST}"
else
  echo "⚠️  Port 45671/tcp not open on ${REMOTE_SSH_HOST}."
  echo "   The edge site (localhost) cannot connect without this. Run on ${REMOTE_SSH_HOST}:"
  echo "   sudo firewall-cmd --zone=<ZONE> --add-port=45671/tcp --permanent && sudo firewall-cmd --reload"
  echo ""
  echo "   Aborting — fix firewall on remote host and re-run."
  exit 1
fi

# ============================================================
# Phase 4: Link Sites (Idempotent)
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 4: Link Sites"
echo "══════════════════════════════════════════════════════════"

# Check if link already established (edge connects outbound to remote:45671)
LINK_ESTAB=$(ss -tnp 2>/dev/null | { grep 45671 || true; } | { grep ESTAB || true; } | wc -l)
if [[ "$LINK_ESTAB" -gt 0 ]]; then
  echo "✅ Inter-site link already established (${LINK_ESTAB} ESTAB connections on 45671)"
else
  # Get remote host's reachable IP
  REMOTE_IP=$(ssh "${REMOTE_SSH_HOST}" "hostname -I | awk '{print \$1}'")
  echo "→ Interior site IP: ${REMOTE_IP}"

  echo "→ Generating link token on interior site (${REMOTE_SSH_HOST})..."
  TOKEN_FILE=$(mktemp /tmp/link-token-XXXXXX.yaml)
  ssh "${REMOTE_SSH_HOST}" "skupper link generate -n ${NAMESPACE} -p linux --host ${REMOTE_IP}" > "${TOKEN_FILE}"

  echo "→ Verifying localhost can reach ${REMOTE_IP}:45671..."
  nc -zv "${REMOTE_IP}" 45671 -w 5 2>&1 || {
    echo "❌ Cannot reach ${REMOTE_IP}:45671 — check firewall on ${REMOTE_SSH_HOST}"
    rm -f "${TOKEN_FILE}"
    exit 1
  }

  echo "→ Applying link token on edge site (localhost)..."
  skupper system -n "${NAMESPACE}" -p linux apply -f "${TOKEN_FILE}"
  skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | { grep -v 'WARN certificate' || true; }
  rm -f "${TOKEN_FILE}"

  echo "→ Waiting for link to establish..."
  sleep 10

  LINK_ESTAB=$(ss -tnp 2>/dev/null | { grep 45671 || true; } | { grep ESTAB || true; } | wc -l)
  if [[ "$LINK_ESTAB" -gt 0 ]]; then
    echo "✅ Inter-site link established"
  else
    echo "⚠️  No ESTAB connection on 45671 yet — may still be connecting"
  fi
fi

# ============================================================
# Phase 5: Start Model on Remote
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 5: Start Model Runtime (${MODEL_ALIAS}) on ${REMOTE_SSH_HOST}"
echo "══════════════════════════════════════════════════════════"

REMOTE_MODEL_RUNNING=$(ssh "${REMOTE_SSH_HOST}" "podman ps --filter name=${MODEL_CONTAINER} --filter status=running --format '{{.Names}}' 2>/dev/null" || true)
if [[ -n "$REMOTE_MODEL_RUNNING" ]]; then
  echo "✅ Model '${MODEL_CONTAINER}' already running on ${REMOTE_SSH_HOST}"
else
  echo "→ Stopping any other model containers on port 8000..."
  ssh "${REMOTE_SSH_HOST}" 'podman stop model-g350m 2>/dev/null; podman stop model-g1b 2>/dev/null; podman stop model-g8b 2>/dev/null' || true
  echo "→ Starting '${MODEL_CONTAINER}'..."
  ssh "${REMOTE_SSH_HOST}" "podman start ${MODEL_CONTAINER}"

  # Wait for model to be ready
  echo "→ Waiting for model API to become ready..."
  READY=0
  for i in $(seq 1 60); do
    if ssh "${REMOTE_SSH_HOST}" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${MODEL_PORT}/v1/models" 2>/dev/null | grep -q '200'; then
      READY=1
      break
    fi
    printf '.'
    sleep 5
  done
  echo ""

  if [[ $READY -eq 1 ]]; then
    echo "✅ Model '${MODEL_CONTAINER}' is ready on ${REMOTE_SSH_HOST}"
  else
    echo "❌ Model did not become ready within 5 minutes"
    echo "   Check logs: ssh ${REMOTE_SSH_HOST} podman logs ${MODEL_CONTAINER}"
    exit 1
  fi
fi

# ============================================================
# Phase 6: Create Connector + Listener (Idempotent)
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Phase 6: Create Skupper Connector + Listener"
echo "══════════════════════════════════════════════════════════"

# --- Connector on remote (interior site — points to local model runtime) ---
CONNECTOR_YAML=$(mktemp /tmp/connector-XXXXXX.yaml)
cat > "${CONNECTOR_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: model-connector
spec:
  routingKey: ${ROUTING_KEY}
  port: ${MODEL_PORT}
  host: localhost
EOF

echo "→ Applying Connector on ${REMOTE_SSH_HOST}..."
scp -q "${CONNECTOR_YAML}" "${REMOTE_SSH_HOST}:/tmp/model-connector.yaml"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux apply -f /tmp/model-connector.yaml"
ssh "${REMOTE_SSH_HOST}" "skupper system -n ${NAMESPACE} -p linux reload" 2>&1 | { grep -v 'WARN certificate' || true; }
rm -f "${CONNECTOR_YAML}"
echo "✅ Connector applied"

# --- Listener on localhost (edge site — exposes model API locally) ---
LISTENER_YAML=$(mktemp /tmp/listener-XXXXXX.yaml)
cat > "${LISTENER_YAML}" <<EOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: model-listener
spec:
  routingKey: ${ROUTING_KEY}
  host: localhost
  port: ${MODEL_PORT}
EOF

echo "→ Applying Listener on localhost..."
skupper system -n "${NAMESPACE}" -p linux apply -f "${LISTENER_YAML}"
skupper system -n "${NAMESPACE}" -p linux reload 2>&1 | { grep -v 'WARN certificate' || true; }
rm -f "${LISTENER_YAML}"
echo "✅ Listener applied"

# Wait for skrouterd to bind the port
LISTENER_READY=0
for i in $(seq 1 10); do
  if ss -tlnp | grep -q ":${MODEL_PORT} "; then
    LISTENER_READY=1
    break
  fi
  sleep 2
done

if [[ $LISTENER_READY -eq 1 ]]; then
  echo "✅ Port ${MODEL_PORT} listening on localhost (via skrouterd)"
else
  echo "⚠️  Port ${MODEL_PORT} not yet listening — may take a moment"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "══════════════════════════════════════════════════════════"
echo "Summary"
echo "══════════════════════════════════════════════════════════"
echo "Skupper VAN:    ${LOCAL_SITE_NAME} (edge) ←→ ${REMOTE_SITE_NAME} (interior)"
echo "Namespace:      ${NAMESPACE}"
echo "Model:          ${MODEL_ALIAS} (container: ${MODEL_CONTAINER})"
echo "Remote runtime: ${REMOTE_SSH_HOST}:${MODEL_PORT}"
echo "Local endpoint: http://localhost:${MODEL_PORT}/v1/..."
echo ""
echo "Test with:"
echo "  curl -s http://localhost:${MODEL_PORT}/v1/models | python3 -m json.tool"
echo ""
echo "✅ Skupper Model Provider is UP"
