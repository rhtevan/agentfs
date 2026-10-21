#!/usr/bin/env bash
# up.sh — Start Skupper VAN infrastructure + model containers
# Usage:
#   bash up.sh                              — start ALL sites + default DPs per provider
#   bash up.sh HOST                          — start HOST + local + default DP for HOST
#   bash up.sh HOST --profile PROFILE        — start HOST + local + specific DP
#   bash up.sh localhost                     — start only local router + controller
#   bash up.sh all                           — same as no args
#   bash up.sh --list-sites                  — print valid site names, exit
#
# Model containers are started via hosted-model-ctl after VAN is up.
# Without --profile, the default profile for each provider host is used.
#
# Partial availability: unreachable hosts are skipped with warnings.
# Exit code: 0 = full or partial success; 1 = all failed or setup missing.

source "$(dirname "$0")/common.sh"

# ── Parse arguments ───────────────────────────────────────────
TARGET_HOST=""
EXPLICIT_PROFILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) EXPLICIT_PROFILE="$2"; shift 2 ;;
    --list-sites) echo "${VALID_HOSTS[*]}"; exit 0 ;;
    *) TARGET_HOST="$1"; shift ;;
  esac
done
TARGET_HOST="${TARGET_HOST:-all}"

# Validate host name
if [[ "$TARGET_HOST" != "all" && "$TARGET_HOST" != "localhost" && "$TARGET_HOST" != "local" && "$TARGET_HOST" != "crc" ]]; then
  validate_host "$TARGET_HOST" || exit 1
fi

# Validate profile if given
if [[ -n "$EXPLICIT_PROFILE" ]]; then
  validate_profile "$EXPLICIT_PROFILE" || exit 1
fi
ALL_REMOTE_HOSTS=(rhel-ai rhtevan-work)
CRC_TARGET=false
LOCAL_ONLY=false

# Determine which remote hosts to start
if [[ "$TARGET_HOST" == "all" ]]; then
  HOSTS=("${ALL_REMOTE_HOSTS[@]}")
  SCOPED=false
  [[ "$CRC_ENABLED" == "true" ]] && CRC_TARGET=true
elif [[ "$TARGET_HOST" == "localhost" || "$TARGET_HOST" == "local" ]]; then
  HOSTS=()
  SCOPED=true
  LOCAL_ONLY=true
elif [[ "$TARGET_HOST" == "crc" ]]; then
  HOSTS=()
  SCOPED=true
  CRC_TARGET=true
else
  # Resolve profile name or host name
  if resolve_host "$TARGET_HOST" &>/dev/null; then
    HOSTS=($(resolve_host "$TARGET_HOST"))
  else
    HOSTS=("$TARGET_HOST")
  fi
  SCOPED=true
fi

echo "=== Skupper VAN — UP ==="
if [[ "$LOCAL_ONLY" == "true" ]]; then
  echo "  Target: localhost only (providers untouched)"
elif [[ ${#HOSTS[@]} -gt 0 ]]; then
  echo "  Hosts: ${HOSTS[*]}"
fi
[[ "$CRC_TARGET" == "true" ]] && echo "  CRC:   ${CRC_SITE_NAME}"
[[ "$SCOPED" == "true" ]] && echo "  Mode:  scoped"
echo

# ── LOCAL-ONLY fast path ──────────────────────────────────────
if [[ "$LOCAL_ONLY" == "true" ]]; then
  LOCAL_NS_DIR="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
  if [[ ! -d "${LOCAL_NS_DIR}/runtime/resources" ]]; then
    echo "  ❌ Setup not done. Run: bash setup.sh"
    exit 1
  fi

  echo "Phase 1: Start local controller"
  LOCAL_CTL=$(check_controller_status localhost)
  if [[ "$LOCAL_CTL" == *"Up"* ]]; then
    echo "  ✅ Local controller already running"
  else
    systemctl --user start skupper-controller.service 2>/dev/null || true
    sleep 2
    echo "  ✅ Local controller started"
  fi
  echo

  echo "Phase 2: Start local router"
  LOCAL_ROUTER=$(check_router_status localhost)
  if [[ "$LOCAL_ROUTER" == *"Up"* ]]; then
    echo "  ✅ Local router already running"
  else
    systemctl --user start "skupper-${NAMESPACE}.service" 2>/dev/null || true
    sleep 5
    echo "  ✅ Local router started"
  fi
  echo

  echo "Phase 3: Verify links + listeners"
  # Wait for links to reconverge (AMQP reconnection with backoff)
  MAX_WAIT=30
  WAITED=0
  LINKS_UP=0
  EXPECTED_LINKS=0

  for host in "${ALL_REMOTE_HOSTS[@]}"; do
    if host_reachable "$host"; then
      remote_router=$(check_router_status "$host")
      [[ "$remote_router" == *"Up"* ]] && ((EXPECTED_LINKS++)) || true
    fi
  done

  if [[ "$EXPECTED_LINKS" -gt 0 ]]; then
    echo "  Waiting for ${EXPECTED_LINKS} link(s) to reconverge..."
    while [[ "$WAITED" -lt "$MAX_WAIT" ]]; do
      LINKS_UP=0
      for host in "${ALL_REMOTE_HOSTS[@]}"; do
        IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
        LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
        LISTENING=${LISTENING:-0}
        [[ "$LISTENING" -gt 0 ]] && ((LINKS_UP++)) || true
      done
      [[ "$LINKS_UP" -ge "$EXPECTED_LINKS" ]] && break
      sleep 2
      ((WAITED+=2)) || true
    done
  fi

  # Report listener status for all hosts
  for host in "${ALL_REMOTE_HOSTS[@]}"; do
    IFS='|' read -r _ _ _ MODEL_PORT _ <<< "${SITE_PROFILES[$host]}"
    LISTENING=$(ss -tlnp 2>/dev/null | grep -c ":${MODEL_PORT} " || true)
    LISTENING=${LISTENING:-0}
    if [[ "$LISTENING" -gt 0 ]]; then
      echo "  ✅ localhost:${MODEL_PORT} listening ($host route)"
    else
      # Check if the remote router is even up
      if host_reachable "$host"; then
        remote_router=$(check_router_status "$host")
        if [[ "$remote_router" == *"Up"* ]]; then
          echo "  ⚠️  localhost:${MODEL_PORT} not listening ($host route — link may need more time)"
        else
          echo "  ℹ️  localhost:${MODEL_PORT} not listening ($host — remote router down)"
        fi
      else
        echo "  ℹ️  localhost:${MODEL_PORT} not listening ($host — unreachable)"
      fi
    fi
  done
  echo

  echo "=== Skupper VAN — START SUMMARY ==="
  echo "  ✅ Up:      localhost"
  echo "  ✅ Kept:    remote providers (untouched)"
  if [[ "$LINKS_UP" -ge "$EXPECTED_LINKS" && "$EXPECTED_LINKS" -gt 0 ]]; then
    echo
    echo "✅ LOCAL UP — Local infrastructure started. All ${EXPECTED_LINKS} link(s) reconverged."
  elif [[ "$EXPECTED_LINKS" -eq 0 ]]; then
    echo
    echo "✅ LOCAL UP — Local infrastructure started. No remote routers detected."
  else
    echo
    echo "⚠️  LOCAL UP — Local infrastructure started. ${LINKS_UP}/${EXPECTED_LINKS} link(s) reconverged (others may need more time)."
  fi
  echo "   Model containers are managed via hosted-model-ctl."
  exit 0
fi

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

    # ── Guard: Inter-router listener + cert SANs ────────────
    # Controller may have overwritten config on restart.
    if [[ -n "${LOCAL_INTER_ROUTER_PORT}" && -n "${CRC_LINK_LOCAL_TARGET}" ]]; then
      echo "  → Checking inter-router listener guard..."
      inject_inter_router_listener
      regenerate_local_server_cert
    fi

    # ── CRC Link 1: hub link (rhel-ai) ─────────────────────────
    crc_link_name="${LINK_NAMES[crc-rhel-ai]}"
    link_status=""
    link_status=$(crc_link_status)
    NEED_POD_RESTART=false

    if [[ "$link_status" == "Ready" ]]; then
      echo "  ✅ Link ${crc_link_name}: Connected"
    elif [[ "$link_status" == "Pending" ]]; then
      # Staleness detection: compare CA fingerprints
      local_link_ra="${LINK_NAMES[local-rhel-ai]}"
      cert_dir="${HOME}/.local/share/skupper/namespaces/${NAMESPACE}/runtime/certs/${local_link_ra}-profile"
      staleness=$(check_crc_link_staleness "${crc_link_name}" "${cert_dir}")
      if [[ "$staleness" == stale:* ]]; then
        echo "  ⚠️  Link ${crc_link_name}: Pending (stale secret — ${staleness})"
        echo "  → Refreshing CRC secret with current certs..."
        oc_crc delete secret "${crc_link_name}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
        oc_crc create secret tls "${crc_link_name}" \
          -n "${CRC_NAMESPACE}" \
          --cert="${cert_dir}/tls.crt" \
          --key="${cert_dir}/tls.key"
        oc_crc patch secret "${crc_link_name}" -n "${CRC_NAMESPACE}" \
          --type=merge -p "{\"data\":{\"ca.crt\":\"$(base64 -w0 "${cert_dir}/ca.crt")\"}}"
        NEED_POD_RESTART=true
        echo "  ✅ Secret ${crc_link_name} refreshed"
      else
        echo "  ⚠️  Link ${crc_link_name}: Pending (secret is fresh — may need time)"
      fi
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
      NEED_POD_RESTART=true
    else
      echo "  ⚠️  Link ${crc_link_name}: ${link_status}"
    fi

    # ── CRC Link 2: local link (CRC → local-ezhang relay) ─────
    if [[ -n "${CRC_LINK_LOCAL_TARGET}" ]]; then
      crc_local_link="${LINK_NAMES[crc-local]}"
      local_link_status=""
      local_link_status=$(crc_local_link_status)
      if [[ "$local_link_status" == "Ready" ]]; then
        echo "  ✅ Link ${crc_local_link}: Connected"
      elif [[ "$local_link_status" == "Pending" ]]; then
        # Staleness detection for local link
        local_ra_cert_dir="${HOME}/.local/share/skupper/namespaces/${NAMESPACE}/runtime/certs/client-${LOCAL_RA_NAME}"
        staleness=$(check_crc_link_staleness "${crc_local_link}" "${local_ra_cert_dir}")
        if [[ "$staleness" == stale:* ]]; then
          echo "  ⚠️  Link ${crc_local_link}: Pending (stale secret — ${staleness})"
          echo "  → Refreshing CRC secret with current certs..."
          oc_crc delete secret "${crc_local_link}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
          oc_crc create secret tls "${crc_local_link}" \
            -n "${CRC_NAMESPACE}" \
            --cert="${local_ra_cert_dir}/tls.crt" \
            --key="${local_ra_cert_dir}/tls.key"
          oc_crc patch secret "${crc_local_link}" -n "${CRC_NAMESPACE}" \
            --type=merge -p "{\"data\":{\"ca.crt\":\"$(base64 -w0 "${local_ra_cert_dir}/ca.crt")\"}}"
          NEED_POD_RESTART=true
          echo "  ✅ Secret ${crc_local_link} refreshed"
        else
          echo "  ⚠️  Link ${crc_local_link}: Pending (secret is fresh — may need time)"
        fi
      elif [[ "$local_link_status" == "not found" ]]; then
        echo "  → Recreating link ${crc_local_link}..."
        cat << LINKEOF | sed "s/PLACEHOLDER_NS/${CRC_NAMESPACE}/g" | oc_crc apply -f -
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: ${crc_local_link}
  namespace: PLACEHOLDER_NS
spec:
  cost: 1
  endpoints:
    - name: inter-router
      host: host.crc.testing
      port: "${LOCAL_INTER_ROUTER_PORT}"
  tlsCredentials: ${crc_local_link}
LINKEOF
        NEED_POD_RESTART=true
      else
        echo "  ⚠️  Link ${crc_local_link}: ${local_link_status}"
      fi
    fi

    # Restart router pod if any links were recreated/refreshed
    if [[ "$NEED_POD_RESTART" == "true" ]]; then
      oc_crc delete pod -n "${CRC_NAMESPACE}" -l skupper.io/component=router 2>/dev/null || true
      sleep 15

      # Wait for hub link
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

      # Wait for local link
      if [[ -n "${CRC_LINK_LOCAL_TARGET}" ]]; then
        crc_local_link_attempts=0
        while [[ $crc_local_link_attempts -lt 20 ]]; do
          local_link_status=$(crc_local_link_status)
          if [[ "$local_link_status" == "Ready" ]]; then break; fi
          sleep 3
          ((crc_local_link_attempts++)) || true
        done
        local_link_status=$(crc_local_link_status)
        if [[ "$local_link_status" == "Ready" ]]; then
          echo "  ✅ Link ${crc_local_link}: Connected"
        else
          echo "  ⚠️  Link ${crc_local_link}: ${local_link_status} (may need time)"
        fi
      fi
    fi

    # ── Verify Listeners ──────────────────────────────────────
    list_status=""
    list_status=$(crc_listener_status)
    if [[ "$list_status" == "Ready" ]]; then
      echo "  ✅ Listener model-listener-${CRC_LINK_TARGET}: Matched"
    else
      echo "  ⚠️  Listener model-listener-${CRC_LINK_TARGET}: ${list_status}"
    fi

    if [[ -n "${CRC_LINK_LOCAL_TARGET}" ]]; then
      rhtevan_list_status=""
      rhtevan_list_status=$(crc_rhtevan_listener_status)
      if [[ "$rhtevan_list_status" == "Ready" ]]; then
        echo "  ✅ Listener model-listener-rhtevan-work: Matched"
      else
        echo "  ⚠️  Listener model-listener-rhtevan-work: ${rhtevan_list_status}"
      fi
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

# ── Model delegation ─────────────────────────────────────────
# Start model containers on reachable provider hosts.
HMC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../hosted-model-ctl/scripts"
if [[ -f "$HMC_DIR/common.sh" ]]; then
  source "$HMC_DIR/common.sh"
  echo ""
  echo "=== Model Containers ==="
  for host in "${REACHABLE_HOSTS[@]}"; do
    # Skip consumer-only hosts
    [[ "$host" == "localhost" || "$host" == "crc" ]] && continue

    if [[ -n "$EXPLICIT_PROFILE" ]]; then
      profile="$EXPLICIT_PROFILE"
    else
      profile=$(get_default_profile "$host")
    fi

    if [[ -z "$profile" ]]; then
      echo "  ⚠️  No default profile for $host — skipping model start"
      continue
    fi

    echo "  Starting profile '$profile' on $host..."
    bash "$HMC_DIR/start.sh" "$profile" || {
      echo "  ⚠️  Failed to start '$profile' on $host"
    }
  done
else
  echo "   hosted-model-ctl not found — model containers not managed."
fi
