#!/usr/bin/env bash
# status.sh — Check Skupper VAN and model status
# Usage:
#   bash status.sh              — full status of all components
#   bash status.sh MODEL_ALIAS  — status of specific model path

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:-}"

echo "=== Skupper Model Provider — STATUS ==="
echo

# ── Controllers ───────────────────────────────────────────────
echo "Controllers:"
for host in localhost rhel-ai rhtevan-work; do
  CTL_STATUS=$(check_controller_status "$host")
  if [[ "$CTL_STATUS" == *"Up"* ]]; then
    echo "  ✅ $host: $CTL_STATUS"
  elif [[ "$CTL_STATUS" == "unreachable" ]]; then
    echo "  ⚠️  $host: unreachable"
  else
    echo "  ❌ $host: $CTL_STATUS"
  fi
done
echo

# ── Routers ───────────────────────────────────────────────────
echo "Routers:"
for host in localhost rhel-ai rhtevan-work; do
  ROUTER_STATUS=$(check_router_status "$host")
  if [[ "$ROUTER_STATUS" == *"Up"* ]]; then
    # Check mode
    if [[ "$host" == "localhost" ]]; then
      MODE=$(podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1 || echo "?")
    else
      MODE=$(run_on_host "$host" "podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1" || echo "?")
    fi
    echo "  ✅ $host: $ROUTER_STATUS ($MODE)"
  elif [[ "$ROUTER_STATUS" == "unreachable" ]]; then
    echo "  ⚠️  $host: unreachable"
  else
    echo "  ❌ $host: $ROUTER_STATUS"
  fi
done
echo

# ── Sites (CLI) ───────────────────────────────────────────────
echo "Sites:"
skupper --platform podman site status -n "${NAMESPACE}" 2>&1 | grep -v '^$' || echo "  (no local site)"
for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    run_on_host "$host" "skupper --platform podman site status -n ${NAMESPACE} 2>&1" | grep -v '^$' || true
  fi
done
echo

# ── Links ─────────────────────────────────────────────────────
echo "Links:"
skupper --platform podman link status -n "${NAMESPACE}" 2>&1 | grep -v '^$' || echo "  (no links)"
echo

# ── Listeners ─────────────────────────────────────────────────
echo "Listeners:"
skupper --platform podman listener status -n "${NAMESPACE}" 2>&1 | grep -v '^$' || echo "  (no listeners)"
echo

# ── Connectors ────────────────────────────────────────────────
echo "Connectors:"
for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    echo "  $host:"
    run_on_host "$host" "skupper --platform podman connector status -n ${NAMESPACE} 2>&1" | grep -v '^$' | sed 's/^/    /' || true
  fi
done
echo

# ── Model Containers ─────────────────────────────────────────
echo "Model Containers:"
for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    MODELS=$(run_on_host "$host" "podman ps -a --filter 'name=model-' --format '{{.Names}} {{.Status}}'" || echo "")
    if [[ -n "$MODELS" ]]; then
      while IFS= read -r line; do
        echo "  $host: $line"
      done <<< "$MODELS"
    else
      echo "  $host: (none)"
    fi
  fi
done
echo

# ── End-to-End Connectivity ──────────────────────────────────
echo "End-to-End:"
for port in 9000 10000; do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${port}/v1/models" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    MODEL_ID=$(curl -s "http://localhost:${port}/v1/models" | \
      python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "unknown")
    echo "  ✅ localhost:${port} → $MODEL_ID"
  else
    echo "  ❌ localhost:${port} → HTTP $HTTP_CODE"
  fi
done
echo

# ── Systemd Services ─────────────────────────────────────────
echo "Systemd Services:"
for host in localhost rhel-ai rhtevan-work; do
  echo "  $host:"
  if [[ "$host" == "localhost" ]]; then
    CTL_ACTIVE=$(systemctl --user is-active skupper-controller.service 2>/dev/null || echo "unknown")
    RTR_ACTIVE=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || echo "unknown")
  elif host_reachable "$host"; then
    CTL_ACTIVE=$(run_on_host "$host" "systemctl --user is-active skupper-controller.service 2>/dev/null" || echo "unknown")
    RTR_ACTIVE=$(run_on_host "$host" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null" || echo "unknown")
  else
    CTL_ACTIVE="unreachable"
    RTR_ACTIVE="unreachable"
  fi
  echo "    controller: $CTL_ACTIVE"
  echo "    router:     $RTR_ACTIVE"
done
echo

echo "=== Status complete ==="
