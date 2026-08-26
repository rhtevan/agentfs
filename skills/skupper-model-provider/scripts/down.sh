#!/usr/bin/env bash
# down.sh — Stop Skupper VAN infrastructure (routers + controllers)
# Usage:
#   bash down.sh              — stop ALL routers + controllers (all hosts + local)
#   bash down.sh HOST          — stop only HOST; preserve local if other hosts still active
#   bash down.sh all           — same as no args: stop everything
# Model containers are managed separately via hosted-model-ctl.
#
# Partial availability: unreachable hosts are skipped with warnings.
# Exit code: 0 = full or partial success; 1 = all failed.

source "$(dirname "$0")/common.sh"

TARGET="${1:-all}"
ALL_REMOTE_HOSTS=(rhel-ai rhtevan-work)
CRC_TARGET=false

# Determine which remote hosts to stop
if [[ "$TARGET" == "all" ]]; then
  HOSTS=("${ALL_REMOTE_HOSTS[@]}")
  SCOPED=false
  [[ "$CRC_ENABLED" == "true" ]] && CRC_TARGET=true
elif [[ "$TARGET" == "crc" ]]; then
  HOSTS=()
  SCOPED=true
  CRC_TARGET=true
else
  # Resolve profile name or host name
  if resolve_host "$TARGET" &>/dev/null; then
    HOSTS=($(resolve_host "$TARGET"))
  else
    HOSTS=("$TARGET")
  fi
  SCOPED=true
fi

echo "=== Skupper VAN — DOWN ==="
if [[ ${#HOSTS[@]} -gt 0 ]]; then
  echo "  Hosts: ${HOSTS[*]}"
fi
[[ "$CRC_TARGET" == "true" ]] && echo "  CRC:   ${CRC_SITE_NAME}"
[[ "$SCOPED" == "true" ]] && echo "  Mode:  scoped (preserving other routes)"
echo

# ── Phase 0: Check reachability ───────────────────────────────
echo "Phase 0: Reachability"

REACHABLE_HOSTS=()
SKIPPED_HOSTS=()
SKIPPED_REASONS=()

for host in "${HOSTS[@]}"; do
  if host_reachable "$host"; then
    echo "  ✅ $host reachable"
    REACHABLE_HOSTS+=("$host")
  else
    echo "  ⚠️  $host unreachable — will be skipped"
    SKIPPED_HOSTS+=("$host")
    SKIPPED_REASONS+=("unreachable")
  fi
done

CRC_SKIPPED=false
if [[ "$CRC_TARGET" == "true" ]]; then
  if crc_reachable; then
    echo "  ✅ CRC reachable"
  else
    echo "  ⚠️  CRC context (${CRC_OC_CONTEXT}) not authenticated — will be skipped"
    CRC_SKIPPED=true
  fi
fi
echo

# ── Phase 1: Stop remote routers (+ tmpfs safety net) ─────────
echo "Phase 1: Stop remote routers"
for host in "${REACHABLE_HOSTS[@]}"; do
  run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null" || true
  # On tmpfs-workaround hosts (rhel-ai), the router container is created
  # by `podman run` outside systemd control. systemctl stop may not reach it.
  # Explicitly `podman stop` (NOT rm) as a safety net.
  if needs_tmpfs_workaround "$host"; then
    run_on_host "$host" "podman stop ${ROUTER_CONTAINER} 2>/dev/null" || true
  fi
  echo "  ✅ $host router stopped"
done
for host in "${SKIPPED_HOSTS[@]}"; do
  echo "  ⏭️  $host skipped (unreachable)"
done
echo

# ── Phase 2: Stop remote controllers ──────────────────────────
echo "Phase 2: Stop remote controllers"
for host in "${REACHABLE_HOSTS[@]}"; do
  run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
  echo "  ✅ $host controller stopped"
done
for host in "${SKIPPED_HOSTS[@]}"; do
  echo "  ⏭️  $host skipped (unreachable)"
done
echo

# ── Phase 3: Conditionally stop local router + controller ─────
# In scoped mode, check if any OTHER remote host still has a
# running router. If yes, local must stay up to serve those routes.
echo "Phase 3: Local infrastructure"

STOP_LOCAL=true

if [[ "$SCOPED" == "true" ]]; then
  for other_host in "${ALL_REMOTE_HOSTS[@]}"; do
    # Skip the host(s) we just stopped or tried to stop
    is_targeted=false
    for targeted_host in "${HOSTS[@]}"; do
      [[ "$other_host" == "$targeted_host" ]] && is_targeted=true && break
    done
    [[ "$is_targeted" == "true" ]] && continue

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
for host in "${REACHABLE_HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
  LISTENING=${LISTENING:-0}
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ⚠️  localhost:${MODEL_PORT} ($host route) — still listening"
  else
    echo "  ✅ localhost:${MODEL_PORT} ($host route) — stopped"
  fi
done

# Report skipped host ports
for host in "${SKIPPED_HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  echo "  ⏭️  localhost:${MODEL_PORT} ($host) — skipped (host unreachable)"
done

# In scoped mode, verify other routes are preserved
if [[ "$SCOPED" == "true" && "$STOP_LOCAL" == "false" ]]; then
  for other_host in "${ALL_REMOTE_HOSTS[@]}"; do
    is_targeted=false
    for targeted_host in "${HOSTS[@]}"; do
      [[ "$other_host" == "$targeted_host" ]] && is_targeted=true && break
    done
    [[ "$is_targeted" == "true" ]] && continue

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

# ── Phase 5: CRC site ──────────────────────────────────────────
if [[ "$CRC_TARGET" == "true" ]]; then
  echo "Phase 5: CRC site"

  if [[ "$CRC_SKIPPED" == "true" ]]; then
    echo "  ⏭️  CRC skipped (not authenticated)"
  else
    crc_link_name="link-hub-${CRC_LINK_TARGET}"
    link_status=""
    link_status=$(crc_link_status)

    if [[ "$link_status" == "not found" ]]; then
      echo "  ✅ Link ${crc_link_name} already removed (CRC disconnected)"
    else
      oc_crc delete link "${crc_link_name}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
      echo "  ✅ Link ${crc_link_name} deleted (CRC disconnected)"
    fi

    # Verify Site + Listener preserved
    site_status=""
    site_status=$(crc_site_status)
    echo "  ✅ Site ${CRC_SITE_NAME}: ${site_status} (preserved)"

    list_status=""
    list_status=$(crc_listener_status)
    echo "  ✅ Listener model-listener-${CRC_LINK_TARGET}: ${list_status} (preserved)"
  fi
  echo
fi

# ── Summary ────────────────────────────────────────────────────
echo "=== Skupper VAN — STOP SUMMARY ==="

# Collect STOPPED sites
STOPPED_SITES=()
[[ "$STOP_LOCAL" == "true" ]] && STOPPED_SITES+=("localhost")
for host in "${REACHABLE_HOSTS[@]}"; do
  STOPPED_SITES+=("$host")
done
[[ "$CRC_TARGET" == "true" && "$CRC_SKIPPED" != "true" ]] && STOPPED_SITES+=("crc")

# Collect KEPT sites
KEPT_SITES=()
[[ "$STOP_LOCAL" == "false" ]] && KEPT_SITES+=("localhost (other routes active)")

# Collect SKIPPED sites
SKIPPED_SUMMARY=()
for i in "${!SKIPPED_HOSTS[@]}"; do
  SKIPPED_SUMMARY+=("${SKIPPED_HOSTS[$i]} (${SKIPPED_REASONS[$i]})")
done
[[ "$CRC_TARGET" == "true" && "$CRC_SKIPPED" == "true" ]] && SKIPPED_SUMMARY+=("crc (not authenticated)")

[[ ${#STOPPED_SITES[@]} -gt 0 ]] && echo "  🔴 Stopped: ${STOPPED_SITES[*]}"
[[ ${#KEPT_SITES[@]} -gt 0 ]] && echo "  ✅ Kept:    ${KEPT_SITES[*]}"
if [[ ${#SKIPPED_SUMMARY[@]} -gt 0 ]]; then
  echo "  ⏭️  Skipped: ${SKIPPED_SUMMARY[*]}"
  echo
  echo "⚠️  PARTIAL DOWN — Some hosts were unreachable and could not be stopped."
else
  echo
  echo "✅ FULL DOWN — All targeted sites stopped."
fi
echo "   Model containers are managed via hosted-model-ctl."
