#!/usr/bin/env bash
# status.sh — Check Skupper VAN infrastructure status
# Usage: bash status.sh
# Model container status is handled by hosted-model-ctl (agent orchestration).

source "$(dirname "$0")/common.sh"

echo "=== Skupper VAN — STATUS ==="
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

echo "=== VAN status complete ==="
echo "    For model container status, use: hosted-model-ctl status"
