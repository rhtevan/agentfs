#!/usr/bin/env bash
# up.sh — Bring up Skupper VAN and start a model
# Usage: bash up.sh MODEL_ALIAS
# Idempotent: skips already-running components.

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:?Usage: up.sh MODEL_ALIAS (g350m|g1b|g8b|g8b-128k|g30b-96k)}"

# Resolve model → host
REMOTE_HOST=$(alias_to_host "$MODEL_ALIAS") || exit 1
LOCAL_PORT=$(alias_to_local_port "$MODEL_ALIAS")
ROUTING_KEY=$(alias_to_routing_key "$MODEL_ALIAS")
MODEL_CONTAINER=$(alias_to_container "$MODEL_ALIAS")

IFS='|' read -r _ INTER_ROUTER_PORT EDGE_PORT _ MODEL_PORT <<< "${SITE_PROFILES[$REMOTE_HOST]}"

echo "=== Skupper Model Provider — UP ==="
echo "  Model alias:    $MODEL_ALIAS"
echo "  Remote host:    $REMOTE_HOST"
echo "  Container:      $MODEL_CONTAINER"
echo "  Routing key:    $ROUTING_KEY"
echo "  Remote model port: $MODEL_PORT"
echo "  Local listener: localhost:$LOCAL_PORT"
echo "  Link port:      $INTER_ROUTER_PORT"
echo

FAILED=0

# ── Phase 1: Prerequisites ────────────────────────────────────
echo "Phase 1: Prerequisites"

# Check remote host
if ! host_reachable "$REMOTE_HOST"; then
  echo "❌ Remote host $REMOTE_HOST is unreachable"
  exit 1
fi
echo "  ✅ $REMOTE_HOST reachable"

# Check skupper CLI
if ! command -v skupper &>/dev/null; then
  echo "❌ skupper CLI not found"
  exit 1
fi
echo "  ✅ skupper CLI available"

# Check model container exists on remote
CONTAINER_STATUS=$(run_on_host "$REMOTE_HOST" "podman ps -a --filter name=${MODEL_CONTAINER} --format '{{.Status}}'" || echo "")
if [[ -z "$CONTAINER_STATUS" ]]; then
  echo "❌ Model container $MODEL_CONTAINER not found on $REMOTE_HOST"
  echo "   Run: bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh $MODEL_ALIAS"
  exit 1
fi
echo "  ✅ Container $MODEL_CONTAINER exists ($CONTAINER_STATUS)"
echo

# ── Phase 2: Remote Hub Site ──────────────────────────────────
echo "Phase 2: Remote hub site ($REMOTE_HOST)"

HUB_ROUTER=$(check_router_status "$REMOTE_HOST")
if [[ "$HUB_ROUTER" == *"Up"* ]]; then
  echo "  ✅ Hub router already running"
else
  echo "  → Creating hub site..."
  
  # Check if namespace exists
  HAS_NS=$(run_on_host "$REMOTE_HOST" "test -d ~/.local/share/skupper/namespaces/${NAMESPACE} && echo yes || echo no")
  
  if [[ "$HAS_NS" != "yes" ]]; then
    echo "  → Applying site resources..."
    run_on_host "$REMOTE_HOST" "skupper system apply -n ${NAMESPACE} -p ${PLATFORM} << 'SITEEOF'
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: hub
  namespace: ${NAMESPACE}
spec:
  linkAccess: default
SITEEOF"
    
    # Apply RouterAccess with custom ports
    run_on_host "$REMOTE_HOST" "skupper system apply -n ${NAMESPACE} -p ${PLATFORM} << 'RAEOF'
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: hub
  namespace: ${NAMESPACE}
spec:
  roles:
  - name: inter-router
    port: ${INTER_ROUTER_PORT}
  - name: edge
    port: ${EDGE_PORT}
  subjectAlternativeNames:
  - ${REMOTE_HOST}
RAEOF"
    
    # Apply Connector
    run_on_host "$REMOTE_HOST" "skupper system apply -n ${NAMESPACE} -p ${PLATFORM} << 'CONNEOF'
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: model-connector
  namespace: ${NAMESPACE}
spec:
  routingKey: ${ROUTING_KEY}
  port: ${MODEL_PORT}
  host: host.containers.internal
CONNEOF"
    
    # Start site to generate certs
    run_on_host "$REMOTE_HOST" "skupper system start -n ${NAMESPACE} -p ${PLATFORM}"
    sleep 3
  fi
  
  # Start router container manually (fixes tmpfs/cert issues)
  start_router_container "$REMOTE_HOST"
  sleep 5
  
  # Verify listening
  LISTENING=$(run_on_host "$REMOTE_HOST" "ss -tlnp | grep -c ${INTER_ROUTER_PORT}" || echo "0")
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ✅ Hub listening on port $INTER_ROUTER_PORT"
  else
    echo "  ❌ Hub not listening on port $INTER_ROUTER_PORT"
    FAILED=1
  fi
fi
echo

# ── Phase 3: Local Interior Site ──────────────────────────────
echo "Phase 3: Local interior site"

LOCAL_ROUTER=$(check_router_status "localhost")
if [[ "$LOCAL_ROUTER" == *"Up"* ]]; then
  echo "  ✅ Local router already running"
else
  echo "  → Creating local interior site..."
  
  LOCAL_HAS_NS=$(test -d "$HOME/.local/share/skupper/namespaces/${NAMESPACE}" && echo yes || echo no)
  
  if [[ "$LOCAL_HAS_NS" != "yes" ]]; then
    skupper system apply -n "${NAMESPACE}" -p "${PLATFORM}" << 'SITEEOF'
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: local
spec: {}
SITEEOF
  fi
  
  # Ensure listener exists for this routing key
  LISTENER_NAME="model-listener-$(echo $REMOTE_HOST | tr '.' '-')"
  LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
  
  if [[ ! -f "${LOCAL_NS_DIR}/input/resources/Listener-${LISTENER_NAME}.yaml" ]]; then
    skupper system apply -n "${NAMESPACE}" -p "${PLATFORM}" << LISTEOF
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: ${LISTENER_NAME}
  namespace: ${NAMESPACE}
spec:
  routingKey: ${ROUTING_KEY}
  port: ${LOCAL_PORT}
  host: 0.0.0.0
LISTEOF
  fi
  
  # Start site
  skupper system start -n "${NAMESPACE}" -p "${PLATFORM}" 2>/dev/null || true
  sleep 2
  
  # Start router container
  start_router_container "localhost"
  sleep 5
fi
echo

# ── Phase 4: Link ─────────────────────────────────────────────
echo "Phase 4: Link to $REMOTE_HOST"

LINK_NAME="link-${REMOTE_HOST}"
LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"

if [[ -f "${LOCAL_NS_DIR}/input/resources/Link-${LINK_NAME}.yaml" ]]; then
  echo "  ✅ Link $LINK_NAME already configured"
else
  echo "  → Generating link token from $REMOTE_HOST..."
  TOKEN_FILE=$(mktemp /tmp/skupper-token-XXXXXX.yaml)
  run_on_host "$REMOTE_HOST" "skupper link generate -n ${NAMESPACE} -p ${PLATFORM}" > "$TOKEN_FILE"
  
  LINES=$(wc -l < "$TOKEN_FILE")
  if [[ "$LINES" -lt 5 ]]; then
    echo "  ❌ Token generation failed ($LINES lines)"
    cat "$TOKEN_FILE"
    rm -f "$TOKEN_FILE"
    FAILED=1
  else
    # Fix host and rename
    sed -i "s/0\.0\.0\.0/${REMOTE_HOST}/g" "$TOKEN_FILE"
    sed -i "s/name: link-hub/name: ${LINK_NAME}/g" "$TOKEN_FILE"
    sed -i "s/tlsCredentials: link-hub/tlsCredentials: ${LINK_NAME}/g" "$TOKEN_FILE"
    
    skupper system apply -n "${NAMESPACE}" -p "${PLATFORM}" -i "$TOKEN_FILE"
    
    # Fix the Link to use only inter-router endpoint
    cat > "${LOCAL_NS_DIR}/input/resources/Link-${LINK_NAME}.yaml" << LINKEOF
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: ${LINK_NAME}
  namespace: ${NAMESPACE}
spec:
  endpoints:
  - name: inter-router
    host: ${REMOTE_HOST}
    port: "${INTER_ROUTER_PORT}"
  tlsCredentials: ${LINK_NAME}
LINKEOF
    
    # Rename secret if needed
    if [[ -f "${LOCAL_NS_DIR}/input/resources/Secret-link-hub.yaml" ]]; then
      mv "${LOCAL_NS_DIR}/input/resources/Secret-link-hub.yaml" \
         "${LOCAL_NS_DIR}/input/resources/Secret-${LINK_NAME}.yaml"
      sed -i "s/name: link-hub/name: ${LINK_NAME}/g" \
         "${LOCAL_NS_DIR}/input/resources/Secret-${LINK_NAME}.yaml"
    fi
    
    rm -f "$TOKEN_FILE"
    echo "  ✅ Link $LINK_NAME configured"
  fi
fi

# Reload and restart router
fix_cert_perms "localhost"
# Restart router to pick up any new link/listener config
start_router_container "localhost"
sleep 10

# Verify connection
ESTAB=$(ss -tnp 2>/dev/null | grep "${INTER_ROUTER_PORT}" | grep -c ESTAB 2>/dev/null || echo "0")
if [[ "$ESTAB" -gt 0 ]]; then
  echo "  ✅ Link established ($ESTAB connections)"
else
  echo "  ⚠️  No established connections to $REMOTE_HOST:$INTER_ROUTER_PORT yet"
fi
echo

# ── Phase 5: Start Model ──────────────────────────────────────
echo "Phase 5: Start model $MODEL_ALIAS"

MODEL_STATUS=$(run_on_host "$REMOTE_HOST" "podman ps --filter name=${MODEL_CONTAINER} --format '{{.Status}}'" || echo "")
if [[ "$MODEL_STATUS" == *"Up"* ]]; then
  echo "  ✅ $MODEL_CONTAINER already running"
else
  echo "  → Starting $MODEL_CONTAINER..."
  run_on_host "$REMOTE_HOST" "podman start ${MODEL_CONTAINER}" || {
    echo "  ❌ Failed to start $MODEL_CONTAINER"
    FAILED=1
  }
  
  # Wait for model
  case "$MODEL_ALIAS" in
    g350m|g1b) WAIT=60 ;;
    g8b)       WAIT=30 ;;
    g8b-128k)  WAIT=240 ;;
    g30b-96k)  WAIT=1200 ;;
    *)         WAIT=120 ;;
  esac
  
  echo "  Waiting for model (max ${WAIT}s)..."
  ELAPSED=0
  while (( ELAPSED < WAIT )); do
    CODE=$(run_on_host "$REMOTE_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${MODEL_PORT}/v1/models" || echo "000")
    if [[ "$CODE" == "200" ]]; then
      echo "  ✅ Model ready on ${REMOTE_HOST}:${MODEL_PORT} (${ELAPSED}s)"
      break
    fi
    sleep 15
    ELAPSED=$((ELAPSED + 15))
  done
  
  if [[ "$CODE" != "200" ]]; then
    echo "  ❌ Timeout waiting for model"
    FAILED=1
  fi
fi
echo

# ── Phase 6: Verify Local Endpoint ────────────────────────────
echo "Phase 6: Verify local endpoint"

# Check listener port
LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${LOCAL_PORT}" || echo "0")
if [[ "$LISTENING" -gt 0 ]]; then
  echo "  ✅ localhost:${LOCAL_PORT} listening"
else
  echo "  ⚠️  localhost:${LOCAL_PORT} not listening yet"
  echo "  (May need a few seconds for routing to propagate)"
fi

# Test end-to-end
sleep 5
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${LOCAL_PORT}/v1/models" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  MODEL_ID=$(curl -s "http://localhost:${LOCAL_PORT}/v1/models" | \
    python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "unknown")
  echo "  ✅ End-to-end: localhost:${LOCAL_PORT} → $MODEL_ID"
else
  echo "  ⚠️  End-to-end: HTTP $HTTP_CODE on localhost:${LOCAL_PORT}"
fi
echo

# ── Summary ───────────────────────────────────────────────────
if [[ "$FAILED" -eq 0 ]]; then
  echo "✅ Skupper Model Provider UP: $MODEL_ALIAS → localhost:${LOCAL_PORT}"
else
  echo "⚠️  Skupper Model Provider UP with warnings — check output above"
fi
exit $FAILED
