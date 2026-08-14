#!/usr/bin/env bash
# up.sh — Start Skupper VAN infrastructure (controllers + routers)
# Usage:
#   bash up.sh              — start ALL controllers + routers (all hosts + local)
#   bash up.sh HOST          — start only HOST + local (if not already running)
#   bash up.sh all           — same as no args: start everything
# Model containers are managed separately via hosted-model-ctl.
#
# Partial availability: unreachable hosts are skipped with warnings.
# Exit code: 0 = full or partial success; 1 = all failed or setup missing.

source "$(dirname "$0")/common.sh"

TARGET_HOST="${1:-all}"
ALL_REMOTE_HOSTS=(rhel-ai rhtevan-work)
CRC_TARGET=false

# Determine which remote hosts to start
if [[ "$TARGET_HOST" == "all" ]]; then
  HOSTS=("${ALL_REMOTE_HOSTS[@]}")
  SCOPED=false
  [[ "$CRC_ENABLED" == "true" ]] && CRC_TARGET=true
elif [[ "$TARGET_HOST" == "crc" ]]; then
  HOSTS=()
  SCOPED=true
  CRC_TARGET=true
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
if [[ ${#HOSTS[@]} -gt 0 ]]; then
  echo "  Hosts: ${HOSTS[*]}"
fi
[[ "$CRC_TARGET" == "true" ]] && echo "  CRC:   ${CRC_SITE_NAME}"
[[ "$SCOPED" == "true" ]] && echo "  Mode:  scoped"
echo

# ── Phase 1: Check prerequisites ──────────────────────────────
echo "Phase 1: Prerequisites"

# Check setup has been done
LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
if [[ ! -d "${LOCAL_NS_DIR}/runtime/resources" ]]; then
  echo "  ❌ Setup not done. Run: bash setup.sh"
  exit 1
fi
echo "  ✅ Setup detected"

# Collect reachable vs unreachable hosts
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

# Check CRC reachability early
CRC_SKIPPED=false
if [[ "$CRC_TARGET" == "true" ]]; then
  if crc_reachable; then
    echo "  ✅ CRC reachable"
  else
    echo "  ⚠️  CRC context (${CRC_OC_CONTEXT}) not authenticated — will be skipped"
    CRC_SKIPPED=true
  fi
fi

# If ALL remote hosts are unreachable and CRC is also skipped (or not targeted),
# there's nothing to start
if [[ ${#REACHABLE_HOSTS[@]} -eq 0 && "$CRC_SKIPPED" != "false" ]] && [[ "$CRC_TARGET" == "true" ]]; then
  echo
  echo "❌ All targets unreachable. Nothing to start."
  exit 1
fi
if [[ ${#REACHABLE_HOSTS[@]} -eq 0 && ${#HOSTS[@]} -gt 0 && "$CRC_TARGET" != "true" ]]; then
  echo
  echo "❌ All targets unreachable. Nothing to start."
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

# Remote controllers (only reachable hosts)
for host in "${REACHABLE_HOSTS[@]}"; do
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

# Remote routers (only reachable hosts)
# All hosts use the same systemd start path. The tmpfs workaround
# (rhel-ai) is applied at setup time only — the container retains
# its flags across stop/start cycles.
for host in "${REACHABLE_HOSTS[@]}"; do
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

# Verify reachable host ports are listening
for host in "${REACHABLE_HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
  LISTENING=${LISTENING:-0}
  if [[ "$LISTENING" -gt 0 ]]; then
    echo "  ✅ localhost:${MODEL_PORT} listening ($host route)"
  else
    echo "  ⚠️  localhost:${MODEL_PORT} not listening yet ($host route)"
  fi
done

# Report skipped host ports
for host in "${SKIPPED_HOSTS[@]}"; do
  IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
  echo "  ⏭️  localhost:${MODEL_PORT} skipped ($host unreachable)"
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

# ── Phase 5: CRC site ──────────────────────────────────────────
if [[ "$CRC_TARGET" == "true" ]]; then
  echo "Phase 5: CRC site"

  if [[ "$CRC_SKIPPED" == "true" ]]; then
    echo "  ⏭️  CRC skipped (not authenticated)"
  else
    # Verify Site is Ready
    local_site_status=$(crc_site_status)
    if [[ "$local_site_status" == "Ready" ]]; then
      echo "  ✅ Site ${CRC_SITE_NAME}: Ready"
    else
      echo "  ❌ Site ${CRC_SITE_NAME}: ${local_site_status}"
      echo "     Run: bash setup.sh to create the CRC site"
    fi

    # Recreate Link if missing
    crc_link_name="link-hub-${CRC_LINK_TARGET}"
    link_status=""
    link_status=$(crc_link_status)
    if [[ "$link_status" == "Ready" ]]; then
      echo "  ✅ Link ${crc_link_name}: Connected"
    elif [[ "$link_status" == "not found" ]]; then
      echo "  → Recreating link ${crc_link_name}..."
      crc_hub_host=""
      crc_hub_port=""
      IFS='|' read -r crc_hub_port _ _ _ crc_hub_host <<< "${SITE_PROFILES[$CRC_LINK_TARGET]}"
      cat << LINKEOF | sed "s/PLACEHOLDER_NS/${CRC_NAMESPACE}/g" | oc_crc apply -f -
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: ${crc_link_name}
  namespace: PLACEHOLDER_NS
spec:
  cost: 1
  endpoints:
    - name: inter-router
      host: ${crc_hub_host}
      port: "${crc_hub_port}"
  tlsCredentials: ${crc_link_name}
LINKEOF

      # Restart router pod so it mounts the TLS secret for the new link
      oc_crc delete pod -n "${CRC_NAMESPACE}" -l skupper.io/component=router 2>/dev/null || true
      sleep 15

      # Wait for link
      crc_link_attempts=0
      while [[ $crc_link_attempts -lt 20 ]]; do
        link_status=$(crc_link_status)
        if [[ "$link_status" == "Ready" ]]; then break; fi
        sleep 3
        ((crc_link_attempts++)) || true
      done
      link_status=$(crc_link_status)
      if [[ "$link_status" == "Ready" ]]; then
        echo "  ✅ Link ${crc_link_name}: Connected"
      else
        echo "  ⚠️  Link ${crc_link_name}: ${link_status} (may need time)"
      fi
    else
      echo "  ⚠️  Link ${crc_link_name}: ${link_status}"
    fi

    # Verify Listener
    list_status=""
    list_status=$(crc_listener_status)
    if [[ "$list_status" == "Ready" ]]; then
      echo "  ✅ Listener model-listener-${CRC_LINK_TARGET}: Matched"
    else
      echo "  ⚠️  Listener model-listener-${CRC_LINK_TARGET}: ${list_status}"
    fi
  fi
  echo
fi

# ── Summary ────────────────────────────────────────────────────
echo "=== Skupper VAN — START SUMMARY ==="

# Collect UP sites
UP_SITES=("localhost")
for host in "${REACHABLE_HOSTS[@]}"; do
  UP_SITES+=("$host")
done
[[ "$CRC_TARGET" == "true" && "$CRC_SKIPPED" != "true" ]] && UP_SITES+=("crc")

# Collect SKIPPED sites
SKIPPED_SUMMARY=()
for i in "${!SKIPPED_HOSTS[@]}"; do
  SKIPPED_SUMMARY+=("${SKIPPED_HOSTS[$i]} (${SKIPPED_REASONS[$i]})")
done
[[ "$CRC_TARGET" == "true" && "$CRC_SKIPPED" == "true" ]] && SKIPPED_SUMMARY+=("crc (not authenticated)")

echo "  ✅ Up:      ${UP_SITES[*]}"
if [[ ${#SKIPPED_SUMMARY[@]} -gt 0 ]]; then
  echo "  ⏭️  Skipped: ${SKIPPED_SUMMARY[*]}"
  echo
  echo "⚠️  PARTIAL UP — Model containers should be started only on reachable provider hosts."
  echo "   Reachable providers: $(printf '%s ' "${REACHABLE_HOSTS[@]}")"
else
  echo
  echo "✅ FULL UP — All targeted sites are running."
fi
echo "   Model containers are managed via hosted-model-ctl."
