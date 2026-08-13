#!/usr/bin/env bash
# status.sh — Check Skupper VAN infrastructure status
# Usage: bash status.sh
# Model container status is handled by hosted-model-ctl (agent orchestration).
#
# Shows two status columns:
#   Last-Known  — persisted in Skupper's runtime YAML (may be stale)
#   Live        — derived from actual container/systemd/port checks

source "$(dirname "$0")/common.sh"

echo "=== Skupper VAN — STATUS ==="
echo

# ── Helper: get last-known site status from YAML ──────────────
get_last_known_site_status() {
  local host="$1"
  local site_name="$2"
  local ns_dir yaml_path status_val message_val

  if [[ "$host" == "localhost" ]]; then
    ns_dir="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
    yaml_path="${ns_dir}/runtime/resources/Site-${site_name}.yaml"
    if [[ -f "$yaml_path" ]]; then
      status_val=$(grep '^  status:' "$yaml_path" | tail -1 | awk '{print $2}')
      message_val=$(grep '^  message:' "$yaml_path" | tail -1 | sed 's/^  message: //')
    fi
  else
    if host_reachable "$host"; then
      ns_dir=$(skupper_ns_dir "$host")
      local raw
      raw=$(run_on_host "$host" "grep -E '^  (status|message):' ${ns_dir}/runtime/resources/Site-${site_name}.yaml 2>/dev/null | tail -2" || echo "")
      status_val=$(echo "$raw" | grep '^  status:' | tail -1 | awk '{print $2}')
      message_val=$(echo "$raw" | grep '^  message:' | tail -1 | sed 's/^  message: //')
    fi
  fi

  echo "${status_val:-Unknown}|${message_val:-}"
}

# ── Helper: get last-known link status from local YAML ────────
get_last_known_link_status() {
  local link_name="$1"
  local ns_dir="$HOME/.local/share/skupper/namespaces/${NAMESPACE}"
  local yaml_path="${ns_dir}/runtime/resources/Link-${link_name}.yaml"
  local status_val message_val

  if [[ -f "$yaml_path" ]]; then
    status_val=$(grep '^  status:' "$yaml_path" | tail -1 | awk '{print $2}')
    message_val=$(grep '^  message:' "$yaml_path" | tail -1 | sed 's/^  message: //')
  fi

  echo "${status_val:-Unknown}|${message_val:-}"
}

# ── Helper: TCP port reachability check ───────────────────────
check_port_open() {
  local host="$1"
  local port="$2"
  local timeout="${3:-3}"
  timeout "$timeout" bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null
}

# ── Helper: check if local port is listening ──────────────────
check_local_port_listening() {
  local port="$1"
  ss -tlnp 2>/dev/null | grep -q ":${port} "
}

# ── Helper: format status icon ────────────────────────────────
status_icon() {
  case "$1" in
    Ready|Active|Up|running|active|listening|open) echo "✅" ;;
    Pending|Degraded)   echo "⏳" ;;
    unreachable)        echo "⚠️ " ;;
    *)                  echo "🔴" ;;
  esac
}

# ── Helper: detect staleness ─────────────────────────────────
stale_marker() {
  local last_known="$1"
  local live="$2"
  # Stale if last-known says Ready but live says otherwise
  if [[ "$last_known" == "Ready" && "$live" != "Up" && "$live" != "running" && "$live" != "active" ]]; then
    echo " (STALE)"
  else
    echo ""
  fi
}

# ══════════════════════════════════════════════════════════════
# 1. SITES — Last-Known vs Live
# ══════════════════════════════════════════════════════════════
echo "Sites:"
printf "  %-20s %-12s %-5s  %-12s %-5s  %s\n" "HOST" "LAST-KNOWN" "" "LIVE" "" "DETAIL"
printf "  %-20s %-12s %-5s  %-12s %-5s  %s\n" "────────────────────" "────────────" "" "────────────" "" "──────────────────────────────────────"

for host in localhost rhel-ai rhtevan-work; do
  # Determine site name
  if [[ "$host" == "localhost" ]]; then
    site_name="${LOCAL_SITE_NAME}"
  else
    site_name="${SITE_NAMES[$host]}"
  fi

  # Last-Known from YAML
  IFS='|' read -r lk_status lk_message <<< "$(get_last_known_site_status "$host" "$site_name")"
  lk_icon=$(status_icon "$lk_status")

  # Live status from actual checks
  if [[ "$host" != "localhost" ]] && ! host_reachable "$host"; then
    live_status="unreachable"
    live_detail="SSH not reachable"
  else
    ctl_status=$(check_controller_status "$host")
    rtr_status=$(check_router_status "$host")

    # Derive systemd states
    if [[ "$host" == "localhost" ]]; then
      ctl_svc=$(systemctl --user is-active skupper-controller.service 2>/dev/null || true)
      rtr_svc=$(systemctl --user is-active "skupper-${NAMESPACE}.service" 2>/dev/null || true)
    else
      ctl_svc=$(run_on_host "$host" "systemctl --user is-active skupper-controller.service 2>/dev/null || true")
      rtr_svc=$(run_on_host "$host" "systemctl --user is-active skupper-${NAMESPACE}.service 2>/dev/null || true")
    fi
    ctl_svc="${ctl_svc:-unknown}"
    rtr_svc="${rtr_svc:-unknown}"

    # Determine live status
    if [[ "$ctl_status" == *"Up"* && "$rtr_status" == *"Up"* ]]; then
      live_status="Up"
      # Check router mode
      if [[ "$host" == "localhost" ]]; then
        mode=$(podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1 2>/dev/null || echo "?")
      else
        mode=$(run_on_host "$host" "podman logs ${ROUTER_CONTAINER} 2>&1 | grep -o 'Interior\|Standalone' | tail -1" 2>/dev/null || echo "?")
      fi
      live_detail="controller=up, router=up ($mode)"
    elif [[ "$ctl_status" == *"Up"* ]]; then
      live_status="Degraded"
      live_detail="controller=up, router=${rtr_svc}"
    elif [[ "$rtr_status" == *"Up"* ]]; then
      live_status="Degraded"
      live_detail="controller=${ctl_svc}, router=up"
    else
      live_status="Down"
      live_detail="controller=${ctl_svc}, router=${rtr_svc}"
    fi
  fi

  live_icon=$(status_icon "$live_status")
  stale=$(stale_marker "$lk_status" "$live_status")

  printf "  %-20s %s %-11s  %s %-11s  %s%s\n" \
    "$host" "$lk_icon" "$lk_status" "$live_icon" "$live_status" "$live_detail" "$stale"
done
echo

# ══════════════════════════════════════════════════════════════
# 2. LINKS — Last-Known vs Live (TCP probe)
# ══════════════════════════════════════════════════════════════
echo "Links:"
printf "  %-26s %-12s %-5s  %-14s %-5s  %s\n" "LINK" "LAST-KNOWN" "" "LIVE" "" "REMOTE ENDPOINT"
printf "  %-26s %-12s %-5s  %-14s %-5s  %s\n" "──────────────────────────" "────────────" "" "──────────────" "" "─────────────────────────"

for host in rhel-ai rhtevan-work; do
  site_name="${SITE_NAMES[$host]}"
  link_name="link-${site_name}"

  # Last-Known from YAML
  IFS='|' read -r lk_status lk_message <<< "$(get_last_known_link_status "$link_name")"
  lk_icon=$(status_icon "$lk_status")

  # Remote endpoint info
  IFS='|' read -r ir_port _ _ _ pub_host <<< "${SITE_PROFILES[$host]}"
  endpoint="${pub_host}:${ir_port}"

  # Live: TCP probe to remote inter-router port
  if check_port_open "$pub_host" "$ir_port" 3; then
    live_status="Reachable"
    live_icon="✅"
  else
    live_status="Unreachable"
    live_icon="🔴"
  fi

  stale=$(stale_marker "$lk_status" "$live_status")

  printf "  %-26s %s %-11s  %s %-13s  %s%s\n" \
    "$link_name" "$lk_icon" "$lk_status" "$live_icon" "$live_status" "$endpoint" "$stale"
done
echo

# ══════════════════════════════════════════════════════════════
# 3. LISTENERS — Last-Known vs Live (local port check)
# ══════════════════════════════════════════════════════════════
echo "Listeners:"
printf "  %-22s %-6s %-12s %-5s  %-14s %-5s  %s\n" "NAME" "PORT" "LAST-KNOWN" "" "LIVE" "" "ROUTING-KEY"
printf "  %-22s %-6s %-12s %-5s  %-14s %-5s  %s\n" "──────────────────────" "──────" "────────────" "" "──────────────" "" "─────────────────────────"

for host in rhel-ai rhtevan-work; do
  IFS='|' read -r _ _ routing_key model_port _ <<< "${SITE_PROFILES[$host]}"
  listener_name="model-${host}"

  # Last-Known from skupper CLI (fast, local only)
  lk_line=$(skupper --platform podman listener status -n "${NAMESPACE}" 2>&1 | grep "$listener_name" || echo "")
  if [[ -n "$lk_line" ]]; then
    lk_status=$(echo "$lk_line" | awk '{print $2}')
  else
    lk_status="Unknown"
  fi
  lk_icon=$(status_icon "$lk_status")

  # Live: is the local port actually listening?
  if check_local_port_listening "$model_port"; then
    live_status="Listening"
    live_icon="✅"
  else
    live_status="Not listening"
    live_icon="🔴"
  fi

  printf "  %-22s %-6s %s %-11s  %s %-13s  %s\n" \
    "$listener_name" "$model_port" "$lk_icon" "$lk_status" "$live_icon" "$live_status" "$routing_key"
done
echo

# ══════════════════════════════════════════════════════════════
# 4. CONNECTORS — Remote status
# ══════════════════════════════════════════════════════════════
echo "Connectors:"
for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    echo "  $host:"
    run_on_host "$host" "skupper --platform podman connector status -n ${NAMESPACE} 2>&1" | grep -v '^$' | sed 's/^/    /' || true
  else
    echo "  $host: ⚠️  unreachable"
  fi
done
echo

# ══════════════════════════════════════════════════════════════
# 5. CRC SITE (Kubernetes)
# ══════════════════════════════════════════════════════════════
if [[ "$CRC_ENABLED" == "true" ]]; then
  echo "CRC Site (${CRC_SITE_NAME}):" 
  if crc_reachable; then
    # Site
    crc_s_status=""
    crc_s_status=$(crc_site_status)
    crc_s_icon=""
    [[ "$crc_s_status" == "Ready" ]] && crc_s_icon="✅" || crc_s_icon="🔴"
    echo "  Site:     ${crc_s_icon} ${crc_s_status}"

    # Router pod
    crc_router_status=""
    crc_router_status=$(oc_crc get pods -n "${CRC_NAMESPACE}" -l skupper.io/component=router \
      -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "not found")
    crc_r_icon=""
    [[ "$crc_router_status" == "Running" ]] && crc_r_icon="✅" || crc_r_icon="🔴"
    echo "  Router:   ${crc_r_icon} ${crc_router_status}"

    # Link
    crc_l_status=""
    crc_l_status=$(crc_link_status)
    crc_l_icon=""
    [[ "$crc_l_status" == "Ready" ]] && crc_l_icon="✅" || crc_l_icon="🔴"
    echo "  Link:     ${crc_l_icon} link-hub-${CRC_LINK_TARGET} → ${crc_l_status}"

    # Listener
    crc_li_status=""
    crc_li_status=$(crc_listener_status)
    crc_li_icon=""
    [[ "$crc_li_status" == "Ready" ]] && crc_li_icon="✅" || crc_li_icon="🔴"
    echo "  Listener: ${crc_li_icon} model-listener-${CRC_LINK_TARGET}:${CRC_MODEL_PORT} → ${crc_li_status}"

    # Service
    crc_svc=""
    crc_svc=$(oc_crc get svc "model-listener-${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" \
      -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "not found")
    if [[ "$crc_svc" != "not found" && -n "$crc_svc" ]]; then
      echo "  Service:  ✅ model-listener-${CRC_LINK_TARGET}.${CRC_NAMESPACE}:${CRC_MODEL_PORT} (${crc_svc})"
    else
      echo "  Service:  🔴 not found"
    fi

    # Operator
    crc_csv_status=""
    crc_csv_status=$(oc_crc get csv -n openshift-operators -o jsonpath='{.items[?(@.metadata.name=="skupper-operator.v2.2.1-rh-1")].status.phase}' 2>/dev/null || echo "not found")
    [[ -z "$crc_csv_status" ]] && crc_csv_status="not found"
    crc_csv_icon=""
    [[ "$crc_csv_status" == "Succeeded" ]] && crc_csv_icon="✅" || crc_csv_icon="🔴"
    echo "  Operator: ${crc_csv_icon} ${crc_csv_status}"

    # Network Observer
    if [[ "$CRC_OBSERVER_ENABLED" == "true" ]]; then
      obs_pod_status=""
      obs_pod_status=$(oc_crc get pods -n "${CRC_NAMESPACE}" -l app.kubernetes.io/name=network-observer \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "not found")
      obs_icon=""
      [[ "$obs_pod_status" == "Running" ]] && obs_icon="✅" || obs_icon="🔴"
      echo "  Observer: ${obs_icon} ${obs_pod_status}"

      obs_url=""
      obs_url=$(crc_observer_route_url)
      if [[ "$obs_url" != "not found" && -n "$obs_url" ]]; then
        echo "  Dashboard: ✅ https://${obs_url}"
      else
        echo "  Dashboard: 🔴 Route not found"
      fi
    fi
  else
    echo "  🔴 CRC context (${CRC_OC_CONTEXT}) not authenticated"
  fi
  echo
fi

echo "=== VAN status complete ==="
echo "    For model container status, use: hosted-model-ctl status"
