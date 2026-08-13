#!/usr/bin/env bash
# teardown.sh — Remove Skupper VAN infrastructure from all hosts
# Usage: bash teardown.sh
# Stops all sites, removes namespaces, removes systemd patches.
# Does NOT remove model containers (managed by hosted-model-ctl).

source "$(dirname "$0")/common.sh"

echo "=== Skupper Model Provider — TEARDOWN ==="
if [[ "$CRC_ENABLED" == "true" ]]; then
  echo "  This will remove Skupper infrastructure from all 3 podman hosts + CRC."
else
  echo "  This will remove Skupper infrastructure from all 3 podman hosts."
fi
echo "  Model containers will NOT be affected."
echo

# ── Phase 1: Stop local site ─────────────────────────────────
echo "Phase 1: Stop local site"

systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
skupper --platform podman system stop -n "${NAMESPACE}" 2>/dev/null || true
echo "  ✅ Local site stopped"
echo

# ── Phase 2: Stop remote sites ────────────────────────────────
echo "Phase 2: Stop remote sites"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null; skupper --platform podman system stop -n ${NAMESPACE} 2>/dev/null" || true
    echo "  ✅ $host site stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 3: Stop controllers ─────────────────────────────────
echo "Phase 3: Stop controllers"

# Local
systemctl --user stop skupper-controller.service 2>/dev/null || true
echo "  ✅ Local controller stopped"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
    echo "  ✅ $host controller stopped"
  else
    echo "  ⚠️  $host unreachable — skip"
  fi
done
echo

# ── Phase 4: Remove auto-restart patches ──────────────────────
echo "Phase 4: Remove auto-restart patches"

# Restore original systemd units by removing patched ones
# (skupper system start will regenerate them on next setup)
for host in rhel-ai rhtevan-work localhost; do
  if [[ "$host" == "localhost" ]] || host_reachable "$host"; then
    run_on_host "$host" "
      rm -f ~/.local/share/skupper/system-controller/internal/scripts/start-watch.sh 2>/dev/null
      rm -f ~/.local/share/skupper/namespaces/${NAMESPACE}/internal/scripts/start-watch.sh 2>/dev/null
      systemctl --user daemon-reload 2>/dev/null
    " || true
    echo "  ✅ $host patches removed"
  fi
done
echo

# ── Phase 5: Verify ───────────────────────────────────────────
echo "Phase 5: Verify"

# Check no skupper containers running
LOCAL_CONTAINERS=$(podman ps --filter label=application=skupper-v2 --format '{{.Names}}' 2>/dev/null | wc -l || echo "0")
echo "  Local skupper containers: $LOCAL_CONTAINERS"

for host in rhel-ai rhtevan-work; do
  if host_reachable "$host"; then
    REMOTE_CONTAINERS=$(run_on_host "$host" "podman ps --filter label=application=skupper-v2 --format '{{.Names}}' 2>/dev/null | wc -l" || echo "?")
    echo "  $host skupper containers: $REMOTE_CONTAINERS"
  fi
done

# ── Phase 6: CRC teardown ──────────────────────────────────────
if [[ "$CRC_ENABLED" == "true" ]]; then
  echo "Phase 6: CRC site teardown"

  if crc_reachable; then
    # Delete Skupper resources
    oc_crc delete listener model-listener-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
    oc_crc delete link link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
    oc_crc delete secret link-hub-"${CRC_LINK_TARGET}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
    oc_crc delete site "${CRC_SITE_NAME}" -n "${CRC_NAMESPACE}" 2>/dev/null || true
    echo "  ✅ CRC Skupper resources deleted"

    # Delete Network Observer (if installed)
    if [[ "$CRC_OBSERVER_ENABLED" == "true" ]]; then
      oc_crc delete networkobserver skupper-network-observer -n "${CRC_NAMESPACE}" 2>/dev/null || true
      CRC_OBS_NS="openshift-operators"
      oc_crc delete subscription skupper-netobs-operator -n "${CRC_OBS_NS}" 2>/dev/null || true
      crc_obs_csv=$(oc_crc get csv -n "${CRC_OBS_NS}" -o name 2>/dev/null | grep netobs || true)
      if [[ -n "$crc_obs_csv" ]]; then
        oc_crc delete "$crc_obs_csv" -n "${CRC_OBS_NS}" 2>/dev/null || true
      fi
      echo "  ✅ Network Observer removed"
    fi

    # Delete operator (installed in openshift-operators with AllNamespaces scope)
    CRC_OPERATOR_NS="openshift-operators"
    oc_crc delete subscription skupper-operator -n "${CRC_OPERATOR_NS}" 2>/dev/null || true
    # Delete CSV (all skupper CSVs)
    crc_csv=$(oc_crc get csv -n "${CRC_OPERATOR_NS}" -o name 2>/dev/null | grep skupper || true)
    if [[ -n "$crc_csv" ]]; then
      oc_crc delete "$crc_csv" -n "${CRC_OPERATOR_NS}" 2>/dev/null || true
    fi
    # Note: global-operators OperatorGroup is shared — do NOT delete it
    echo "  ✅ CRC Skupper operator removed"

    # Delete namespace
    oc_crc delete namespace "${CRC_NAMESPACE}" 2>/dev/null || true
    echo "  → Waiting for namespace ${CRC_NAMESPACE} to terminate..."
    ns_attempts=0
    while [[ $ns_attempts -lt 30 ]]; do
      if ! oc_crc get namespace "${CRC_NAMESPACE}" &>/dev/null; then break; fi
      sleep 3
      ((ns_attempts++)) || true
    done
    if ! oc_crc get namespace "${CRC_NAMESPACE}" &>/dev/null; then
      echo "  ✅ Namespace ${CRC_NAMESPACE} deleted"
    else
      echo "  ⚠️  Namespace ${CRC_NAMESPACE} still terminating"
    fi
  else
    echo "  ⚠️  CRC unreachable — skipping CRC teardown"
  fi
  echo
else
  echo "Phase 6: CRC site — skipped (CRC_ENABLED=false)"
  echo
fi

echo "✅ Teardown complete."
echo "   To fully remove all data: skupper --platform podman system uninstall -f"
echo "   To re-setup: bash setup.sh"
