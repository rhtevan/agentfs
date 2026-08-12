#!/usr/bin/env bash
# up.sh — Start Skupper VAN infrastructure (controllers + routers)
# Usage: bash up.sh [HOST]       — start VAN for specific host (or all)
# Model containers are managed separately via hosted-model-ctl.

source "$(dirname "$0")/common.sh"

TARGET_HOST="${1:-all}"

# Determine which remote hosts to start
if [[ "$TARGET_HOST" == "all" ]]; then
  HOSTS=(rhel-ai rhtevan-work)
else
  # Resolve model alias to host if needed
  if alias_to_host "$TARGET_HOST" &>/dev/null; then
    HOSTS=($(alias_to_host "$TARGET_HOST"))
  else
    HOSTS=("$TARGET_HOST")
  fi
fi

echo "=== Skupper VAN — UP ==="
echo "  Hosts: ${HOSTS[*]}"
echo

FAILED=0

# ── Phase 1: Check prerequisites ──────────────────────────────
echo "Phase 1: Prerequisites"

# Check setup has been done
LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
if [[ ! -d "${LOCAL_NS_DIR}/runtime/resources" ]]; then
  echo "  ❌ Setup not done. Run: bash setup.sh"
  exit 1
fi
echo "  ✅ Setup detected"

for host in "${HOSTS[@]}"; do
  if ! host_reachable "$host"; then
    echo "  ❌ $host unreachable"
    FAILED=1
  else
    echo "  ✅ $host reachable"
  fi
done

if [[ "$FAILED" -ne 0 ]]; then
  echo
  echo "❌ Prerequisites failed. Fix connectivity before proceeding."
  exit 1
fi
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

# Remote controllers
for host in "${HOSTS[@]}"; do
  REMOTE_CTL=$(check_controller_status "$host")
  if [[ "$REMOTE_CTL" == *"Up"* ]]; then
    echo "  ✅ $host controller running"
  else
    run_on_host "$host" "systemctl --user start skupper-controller.service 2>/dev/null" || true
    sleep 2
    echo "  ✅ $host controller started"
  fi
done
echo

# ── Phase 3: Start routers ────────────────────────────────────
echo "Phase 3: Start routers"

# Remote routers
for host in "${HOSTS[@]}"; do
  REMOTE_ROUTER=$(check_router_status "$host")
  if [[ "$REMOTE_ROUTER" == *"Up"* ]]; then
    echo "  ✅ $host router running"
  else
    if needs_tmpfs_workaround "$host"; then
      echo "  → Starting $host router (with tmpfs workaround)..."
      recreate_router_with_tmpfs "$host"
    else
      run_on_host "$host" "systemctl --user start skupper-${NAMESPACE}.service 2>/dev/null" || true
    fi
    sleep 5
    echo "  ✅ $host router started"
  fi
done

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

# ── Phase 4: Verify VAN connectivity ──────────────────────────
echo "Phase 4: Verify VAN"

for host in "${HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT}" || true)
  LISTENING=${LISTENING:-0}
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ✅ localhost:${MODEL_PORT} listening ($host route)"
  else
    echo "  ⚠️  localhost:${MODEL_PORT} not listening yet ($host route)"
  fi
done
echo

echo "✅ Skupper VAN infrastructure UP."
echo "   Model containers are managed via hosted-model-ctl."
