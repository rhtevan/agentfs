#!/usr/bin/env bash
# down.sh — Stop Skupper VAN infrastructure (routers + controllers)
# Usage:
#   bash down.sh              — stop ALL routers + controllers (all hosts + local)
#   bash down.sh HOST          — stop only HOST; preserve local if other hosts still active
#   bash down.sh all           — same as no args: stop everything
# Model containers are managed separately via hosted-model-ctl.

source "$(dirname "$0")/common.sh"

TARGET="${1:-all}"
ALL_REMOTE_HOSTS=(rhel-ai rhtevan-work)

# Determine which remote hosts to stop
if [[ "$TARGET" == "all" ]]; then
  HOSTS=("${ALL_REMOTE_HOSTS[@]}")
  SCOPED=false
else
  # Resolve model alias to host if needed
  if alias_to_host "$TARGET" &>/dev/null; then
    HOSTS=($(alias_to_host "$TARGET"))
  else
    HOSTS=("$TARGET")
  fi
  SCOPED=true
fi

echo "=== Skupper VAN — DOWN ==="
echo "  Hosts: ${HOSTS[*]}"
[[ "$SCOPED" == "true" ]] && echo "  Mode:  scoped (preserving other routes)"
echo

# ── Phase 1: Stop remote routers ──────────────────────────────
echo "Phase 1: Stop remote routers"
for host in "${HOSTS[@]}"; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null" || true
    # On tmpfs-workaround hosts (rhel-ai), the router container is created
    # by `podman run` outside systemd control. systemctl stop may not reach it.
    # Explicitly `podman stop` (NOT rm) as a safety net.
    if needs_tmpfs_workaround "$host"; then
      run_on_host "$host" "podman stop ${ROUTER_CONTAINER} 2>/dev/null" || true
    fi
    echo "  ✅ $host router stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 2: Stop remote controllers ──────────────────────────
echo "Phase 2: Stop remote controllers"
for host in "${HOSTS[@]}"; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
    echo "  ✅ $host controller stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 3: Conditionally stop local router + controller ─────
# In scoped mode, check if any OTHER remote host still has a
# running router. If yes, local must stay up to serve those routes.
echo "Phase 3: Local infrastructure"

STOP_LOCAL=true

if [[ "$SCOPED" == "true" ]]; then
  for other_host in "${ALL_REMOTE_HOSTS[@]}"; do
    # Skip the host(s) we just stopped
    is_stopped=false
    for stopped_host in "${HOSTS[@]}"; do
      [[ "$other_host" == "$stopped_host" ]] && is_stopped=true && break
    done
    [[ "$is_stopped" == "true" ]] && continue

    # Check if this other host's router is still running
    if host_reachable "$other_host"; then
      other_router=$(check_router_status "$other_host")
      if [[ "$other_router" == *"Up"* ]]; then
        echo "  ℹ️  $other_host router still active — keeping local infrastructure up"
        STOP_LOCAL=false
        break
      fi
    fi
  done
fi

if [[ "$STOP_LOCAL" == "true" ]]; then
  systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
  echo "  ✅ Local router stopped"
  systemctl --user stop skupper-controller.service 2>/dev/null || true
  echo "  ✅ Local controller stopped"
else
  echo "  ✅ Local router kept running (other routes active)"
  echo "  ✅ Local controller kept running"
fi
echo

# ── Phase 4: Verify ───────────────────────────────────────────
echo "Phase 4: Verify"

# Check stopped host ports are no longer listening
for host in "${HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
  LISTENING=${LISTENING:-0}
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ⚠️  localhost:${MODEL_PORT} ($host route) — still listening"
  else
    echo "  ✅ localhost:${MODEL_PORT} ($host route) — stopped"
  fi
done

# In scoped mode, verify other routes are preserved
if [[ "$SCOPED" == "true" && "$STOP_LOCAL" == "false" ]]; then
  for other_host in "${ALL_REMOTE_HOSTS[@]}"; do
    is_stopped=false
    for stopped_host in "${HOSTS[@]}"; do
      [[ "$other_host" == "$stopped_host" ]] && is_stopped=true && break
    done
    [[ "$is_stopped" == "true" ]] && continue

    IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$other_host]}"
    LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
    LISTENING=${LISTENING:-0}
    if [[ "$LISTENING" -gt 0 ]]; then
      echo "  ✅ localhost:${MODEL_PORT} ($other_host route) — preserved"
    else
      echo "  ❌ localhost:${MODEL_PORT} ($other_host route) — LOST (unexpected)"
    fi
  done
fi
echo

echo "✅ Skupper VAN infrastructure stopped."
echo "   Model containers are managed via hosted-model-ctl."
