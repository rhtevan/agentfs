#!/usr/bin/env bash
# up.sh — Start a model and ensure Skupper VAN is running
# Usage: bash up.sh MODEL_ALIAS
# Assumes setup.sh has been run. Starts systemd services + model container.

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:?Usage: up.sh MODEL_ALIAS (g350m|g1b|g8b|g8b-128k|g30b-96k)}"

# Resolve model → host
REMOTE_HOST=$(alias_to_host "$MODEL_ALIAS") || exit 1
LOCAL_PORT=$(alias_to_local_port "$MODEL_ALIAS")
ROUTING_KEY=$(alias_to_routing_key "$MODEL_ALIAS")
MODEL_CONTAINER=$(alias_to_container "$MODEL_ALIAS")

IFS='|' read -r INTER_ROUTER_PORT _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$REMOTE_HOST]}"

echo "=== Skupper Model Provider — UP ==="
echo "  Model alias:    $MODEL_ALIAS"
echo "  Remote host:    $REMOTE_HOST"
echo "  Container:      $MODEL_CONTAINER"
echo "  Local endpoint: localhost:$LOCAL_PORT"
echo

FAILED=0

# ── Phase 1: Check prerequisites ──────────────────────────────
echo "Phase 1: Prerequisites"

if ! host_reachable "$REMOTE_HOST"; then
  echo "  ❌ $REMOTE_HOST unreachable"
  exit 1
fi
echo "  ✅ $REMOTE_HOST reachable"

# Check setup has been done
LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
if [[ ! -d "${LOCAL_NS_DIR}/runtime/resources" ]]; then
  echo "  ❌ Setup not done. Run: bash setup.sh"
  exit 1
fi
echo "  ✅ Setup detected"
echo

# ── Phase 2: Start controllers ────────────────────────────────
echo "Phase 2: Start controllers"

# Local controller
LOCAL_CTL=$(check_controller_status localhost)
if [[ "$LOCAL_CTL" == *"Up"* ]]; then
  echo "  ✅ Local controller running"
else
  systemctl --user start skupper-controller.service 2>/dev/null || true
  sleep 2
  echo "  ✅ Local controller started"
fi

# Remote controller
REMOTE_CTL=$(check_controller_status "$REMOTE_HOST")
if [[ "$REMOTE_CTL" == *"Up"* ]]; then
  echo "  ✅ $REMOTE_HOST controller running"
else
  run_on_host "$REMOTE_HOST" "systemctl --user start skupper-controller.service 2>/dev/null" || true
  sleep 2
  echo "  ✅ $REMOTE_HOST controller started"
fi
echo

# ── Phase 3: Start routers ────────────────────────────────────
echo "Phase 3: Start routers"

# Remote router
REMOTE_ROUTER=$(check_router_status "$REMOTE_HOST")
if [[ "$REMOTE_ROUTER" == *"Up"* ]]; then
  echo "  ✅ $REMOTE_HOST router running"
else
  if needs_tmpfs_workaround "$REMOTE_HOST"; then
    echo "  → Starting $REMOTE_HOST router (with tmpfs workaround)..."
    recreate_router_with_tmpfs "$REMOTE_HOST"
  else
    run_on_host "$REMOTE_HOST" "systemctl --user start skupper-${NAMESPACE}.service 2>/dev/null" || true
  fi
  sleep 5
  echo "  ✅ $REMOTE_HOST router started"
fi

# Local router
LOCAL_ROUTER=$(check_router_status localhost)
if [[ "$LOCAL_ROUTER" == *"Up"* ]]; then
  echo "  ✅ Local router running"
else
  systemctl --user start "skupper-${NAMESPACE}.service" 2>/dev/null || true
  sleep 5
  echo "  ✅ Local router started"
fi
echo

# ── Phase 4: Start model container ────────────────────────────
echo "Phase 4: Start model $MODEL_ALIAS"

MODEL_STATUS=$(run_on_host "$REMOTE_HOST" "podman ps --filter name=${MODEL_CONTAINER} --format '{{.Status}}'" || echo "")
if [[ "$MODEL_STATUS" == *"Up"* ]]; then
  echo "  ✅ $MODEL_CONTAINER already running"
else
  # Check container exists
  EXISTS=$(run_on_host "$REMOTE_HOST" "podman ps -a --filter name=${MODEL_CONTAINER} --format '{{.Names}}'" || echo "")
  if [[ -z "$EXISTS" ]]; then
    echo "  ❌ Container $MODEL_CONTAINER not found on $REMOTE_HOST"
    echo "     Run: bash ~/.agents/skills/hosted-model-ctl/scripts/setup.sh $MODEL_ALIAS"
    exit 1
  fi

  echo "  → Starting $MODEL_CONTAINER..."
  run_on_host "$REMOTE_HOST" "podman start ${MODEL_CONTAINER}" || {
    echo "  ❌ Failed to start $MODEL_CONTAINER"
    FAILED=1
  }

  # Wait for model API
  case "$MODEL_ALIAS" in
    g350m|g1b) WAIT=60 ;;
    g8b)       WAIT=30 ;;
    g8b-128k)  WAIT=240 ;;
    g30b-96k)  WAIT=1200 ;;
    *)         WAIT=120 ;;
  esac

  echo "  Waiting for model API (max ${WAIT}s)..."
  ELAPSED=0
  CODE="000"
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
    echo "  ❌ Timeout waiting for model API"
    FAILED=1
  fi
fi
echo

# ── Phase 5: Verify local endpoint ────────────────────────────
echo "Phase 5: Verify local endpoint"

sleep 5

# Check listener port
LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${LOCAL_PORT}" || true)
LISTENING=${LISTENING:-0}
if [[ "$LISTENING" -gt 0 ]]; then
  echo "  ✅ localhost:${LOCAL_PORT} listening"
else
  echo "  ⚠️  localhost:${LOCAL_PORT} not listening yet (may need a few seconds)"
fi

# Test end-to-end
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
