#!/usr/bin/env bash
# down.sh — Stop Skupper VAN infrastructure (routers + controllers)
# Usage:
#   bash down.sh [HOST]        — stop VAN for specific host (or all)
#   bash down.sh all            — stop all routers + controllers
# Model containers are managed separately via hosted-model-ctl.

source "$(dirname "$0")/common.sh"

TARGET="${1:-all}"

# Determine which remote hosts to stop
if [[ "$TARGET" == "all" ]]; then
  HOSTS=(rhel-ai rhtevan-work)
else
  # Resolve model alias to host if needed
  if alias_to_host "$TARGET" &>/dev/null; then
    HOSTS=($(alias_to_host "$TARGET"))
  else
    HOSTS=("$TARGET")
  fi
fi

echo "=== Skupper VAN — DOWN ==="
echo "  Hosts: ${HOSTS[*]}"
echo

# ── Phase 1: Stop local router ────────────────────────────────
echo "Phase 1: Stop local router"
systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
echo "  ✅ Local router stopped"
echo

# ── Phase 2: Stop remote routers ──────────────────────────────
echo "Phase 2: Stop remote routers"
for host in "${HOSTS[@]}"; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null" || true
    echo "  ✅ $host router stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 3: Stop controllers ─────────────────────────────────
echo "Phase 3: Stop controllers"
systemctl --user stop skupper-controller.service 2>/dev/null || true
echo "  ✅ Local controller stopped"
for host in "${HOSTS[@]}"; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
    echo "  ✅ $host controller stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 4: Verify ───────────────────────────────────────────
echo "Phase 4: Verify"
for host in "${HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT}" || true)
  echo "  localhost:${MODEL_PORT} — ${LISTENING:-0} listeners"
done
echo

echo "✅ Skupper VAN infrastructure stopped."
echo "   Model containers are managed via hosted-model-ctl."
