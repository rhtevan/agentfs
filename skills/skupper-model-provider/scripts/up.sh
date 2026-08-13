#!/usr/bin/env bash
# up.sh — Start Skupper VAN infrastructure (controllers + routers)
# Usage:
#   bash up.sh              — start ALL controllers + routers (all hosts + local)
#   bash up.sh HOST          — start only HOST + local (if not already running)
#   bash up.sh all           — same as no args: start everything
# Model containers are managed separately via hosted-model-ctl.

source "$(dirname "$0")/common.sh"

TARGET_HOST="${1:-all}"
ALL_REMOTE_HOSTS=(rhel-ai rhtevan-work)

# Determine which remote hosts to start
if [[ "$TARGET_HOST" == "all" ]]; then
  HOSTS=("${ALL_REMOTE_HOSTS[@]}")
  SCOPED=false
else
  # Resolve model alias to host if needed
  if alias_to_host "$TARGET_HOST" &>/dev/null; then
    HOSTS=($(alias_to_host "$TARGET_HOST"))
  else
    HOSTS=("$TARGET_HOST")
  fi
  SCOPED=true
fi

echo "=== Skupper VAN — UP ==="
echo "  Hosts: ${HOSTS[*]}"
[[ "$SCOPED" == "true" ]] && echo "  Mode:  scoped"
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

# Local controller (always needed — serves all routes)
LOCAL_CTL=$(check_controller_status localhost)
if [[ "$LOCAL_CTL" == *"Up"* ]]; then
  echo "  ✅ Local controller running"
else
  systemctl --user start skupper-controller.service 2>/dev/null || true
  sleep 2
  echo "  ✅ Local controller started"
fi

# Remote controllers (only scoped hosts)
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

# Remote routers (only scoped hosts)
# All hosts use the same systemd start path. The tmpfs workaround
# (rhel-ai) is applied at setup time only — the container retains
# its flags across stop/start cycles.
for host in "${HOSTS[@]}"; do
  REMOTE_ROUTER=$(check_router_status "$host")
  if [[ "$REMOTE_ROUTER" == *"Up"* ]]; then
    echo "  ✅ $host router running"
  else
    run_on_host "$host" "systemctl --user start skupper-${NAMESPACE}.service 2>/dev/null" || true
    sleep 5
    echo "  ✅ $host router started"
  fi
done

# Local router (always needed — serves all routes)
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

# Verify scoped host ports are listening
for host in "${HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
  LISTENING=${LISTENING:-0}
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ✅ localhost:${MODEL_PORT} listening ($host route)"
  else
    echo "  ⚠️  localhost:${MODEL_PORT} not listening yet ($host route)"
  fi
done

# In scoped mode, verify other routes are unaffected
if [[ "$SCOPED" == "true" ]]; then
  for other_host in "${ALL_REMOTE_HOSTS[@]}"; do
    is_scoped=false
    for scoped_host in "${HOSTS[@]}"; do
      [[ "$other_host" == "$scoped_host" ]] && is_scoped=true && break
    done
    [[ "$is_scoped" == "true" ]] && continue

    IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$other_host]}"
    LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
    LISTENING=${LISTENING:-0}
    if [[ "$LISTENING" -gt 0 ]]; then
      echo "  ✅ localhost:${MODEL_PORT} listening ($other_host route — preserved)"
    else
      echo "  ℹ️  localhost:${MODEL_PORT} not listening ($other_host route — not started)"
    fi
  done
fi
echo

echo "✅ Skupper VAN infrastructure UP."
echo "   Model containers are managed via hosted-model-ctl."
