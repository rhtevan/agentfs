#!/usr/bin/env bash
# setup.sh — CRC post-setup configuration (orchestrates the skill's helper scripts)
#
# Parts:
#   1 monitoring — crc config flag, drop ClusterVersion monitoring overrides,
#                  retention config (../apply-monitoring-config.sh), wait for rollout
#   2 kubelet    — system-reserved MachineConfig (../apply-system-reserved.sh), then wait for the
#                  MachineConfigPool (the MCD reboots the node itself)
#   3 alerts     — dev-irrelevant silences (../silence-alerts.sh; needs Part 1)
#   4 banner     — delete the "OpenShift Local … DON'T use it for production" console banner
#
# Usage: setup.sh [--part N] [--check|--dry-run]
#   --part N            Run only part N (1-4)
#   --check, --dry-run  Report per-part state, print DRY_RUN_RESULT=CONVERGED|PENDING, change nothing
#
# Prerequisites: oc logged in to the CRC cluster (eval $(crc oc-env))
# Exit: 0 ok · 1 cluster unreachable or a part failed · 2 usage
set -uo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-post-setup-config" "1.4.0" 2>/dev/null || true

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PART=""; CHECK=false; FAIL=0; PENDING=0
BANNER="security-notice"
MC="99-z-crc-system-reserved-override"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --part) PART="${2:-}"; shift 2 ;;
    --check|--dry-run) CHECK=true; shift ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "Usage: setup.sh [--part N] [--check|--dry-run]" >&2; exit 2 ;;
  esac
done
[[ -z "$PART" || "$PART" =~ ^[1-4]$ ]] || { echo "Unknown part: $PART (use 1-4)" >&2; exit 2; }

command -v crc >/dev/null 2>&1 || [[ ! -x "$HOME/.local/bin/crc" ]] || export PATH="$HOME/.local/bin:$PATH"
if ! command -v oc >/dev/null 2>&1 && command -v crc >/dev/null 2>&1; then eval "$(crc oc-env 2>/dev/null)"; fi

echo "=== CRC Post-Setup Configuration ==="
if ! oc whoami >/dev/null 2>&1; then
  echo "❌ Cannot connect to the cluster. Run: eval \$(crc oc-env); oc login -u kubeadmin https://api.crc.testing:6443"
  trace_step 1 "check_connectivity" 1 "" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi
echo "✅ Connected as $(oc whoami) — $(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)"
trace_step 1 "check_connectivity" 0 "" 2>/dev/null || true

state() { if [[ "$1" == ok ]]; then echo "   ✅ $2"; else echo "   ⏳ $2"; PENDING=1; fi; }

# ── state probes (read-only) ───────────────────────────────────────────
monitoring_overrides() {   # prints the overrides list without the two monitoring entries, or NONE
  oc get clusterversion version -o json 2>/dev/null | python3 -c '
import sys, json
ov = json.load(sys.stdin).get("spec", {}).get("overrides", []) or []
kept = [o for o in ov if not (o.get("name") == "cluster-monitoring-operator"
        or (o.get("kind") == "ClusterOperator" and o.get("name") == "monitoring"))]
print(json.dumps(kept) if len(kept) < len(ov) else "NONE")' 2>/dev/null || echo NONE
}
flag_on()       { crc config get enable-cluster-monitoring 2>/dev/null | grep -qx 'true\|.*: true'; }
retention_set() { oc get cm cluster-monitoring-config -n openshift-monitoring -o jsonpath='{.data.config\.yaml}' 2>/dev/null | grep -q 'retention: 24h'; }
mc_set()        { oc get mc "$MC" >/dev/null 2>&1; }
silenced()      {
  oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- curl -s 'http://localhost:9093/api/v2/silences' 2>/dev/null \
    | python3 -c 'import json,sys; sys.exit(0 if any(s["status"]["state"]=="active" and any(m["name"]=="alertname" and m["value"]=="AlertmanagerReceiversNotConfigured" for m in s["matchers"]) for s in json.load(sys.stdin)) else 1)' 2>/dev/null
}
banner_present() { oc get consolenotification "$BANNER" >/dev/null 2>&1; }

# wait_mcp — the MCD applies a new MachineConfig by rebooting the node itself (verified on OCP 5.0).
# First wait until the pool's target config contains our MC, then until the node runs it.
# The API is down during the reboot, so failed oc calls just mean "keep waiting".
wait_mcp() {
  local i spec st upd
  for i in $(seq 1 24); do
    oc get mcp master -o jsonpath='{.spec.configuration.source[*].name}' --request-timeout=10s 2>/dev/null | grep -qw "$MC" && break
    sleep 5
  done
  echo "   ⏳ waiting for MachineConfigPool master (the MCD reboots the node by itself; do NOT crcstop now; up to 20 min)…"
  for i in $(seq 1 240); do
    spec=$(oc get mcp master -o jsonpath='{.spec.configuration.name}' --request-timeout=10s 2>/dev/null)
    st=$(oc get mcp master -o jsonpath='{.status.configuration.name}' --request-timeout=10s 2>/dev/null)
    upd=$(oc get mcp master -o jsonpath='{.status.conditions[?(@.type=="Updated")].status}' --request-timeout=10s 2>/dev/null)
    if [[ -n "$spec" && "$spec" == "$st" && "$upd" == True ]]; then echo "   ✅ MachineConfigPool master updated ($st)"; return 0; fi
    sleep 5
  done
  echo "   ❌ MachineConfigPool master not updated after 20 min (oc get mcp master; oc get node)"; FAIL=1
}

# ── parts ──────────────────────────────────────────────────────────────
run_part1() {
  echo; echo "=== Part 1: Enable Cluster Monitoring ==="
  if $CHECK; then
    flag_on && state ok "crc config enable-cluster-monitoring=true" || state no "crc config enable-cluster-monitoring not true"
    [[ "$(monitoring_overrides)" == NONE ]] && state ok "no ClusterVersion monitoring overrides" || state no "ClusterVersion still has the monitoring overrides (unmanaged)"
    retention_set && state ok "cluster-monitoring-config retention 24h" || state no "cluster-monitoring-config missing or without retention"
    return 0
  fi
  crc config set enable-cluster-monitoring true >/dev/null && echo "   ✅ crc config enable-cluster-monitoring=true" || { echo "   ❌ crc config set failed"; FAIL=1; }
  local kept; kept="$(monitoring_overrides)"
  if [[ "$kept" != NONE ]]; then
    oc patch clusterversion version --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/overrides\",\"value\":$kept}]" >/dev/null \
      && echo "   ✅ monitoring overrides removed" || { echo "   ❌ ClusterVersion patch failed"; FAIL=1; return 0; }
  else
    echo "   ✅ no monitoring overrides to remove"
  fi
  oc wait --for=jsonpath='{.status.phase}'=Active namespace/openshift-monitoring --timeout=300s >/dev/null || { echo "   ❌ openshift-monitoring not Active"; FAIL=1; return 0; }
  bash "$SKILL_DIR/apply-monitoring-config.sh" | sed 's/^/   /' || { echo "   ❌ apply-monitoring-config.sh failed"; FAIL=1; return 0; }
  echo "   ⏳ waiting for the monitoring stack (up to 15 min)…"
  for _ in $(seq 1 60); do oc get deploy/cluster-monitoring-operator -n openshift-monitoring >/dev/null 2>&1 && break; sleep 5; done
  oc rollout status deployment/cluster-monitoring-operator -n openshift-monitoring --timeout=300s >/dev/null 2>&1 \
    && echo "   ✅ cluster-monitoring-operator rolled out" || { echo "   ❌ cluster-monitoring-operator not ready"; FAIL=1; return 0; }
  for _ in $(seq 1 60); do oc get pod -l app.kubernetes.io/name=prometheus -n openshift-monitoring -o name 2>/dev/null | grep -q . && break; sleep 10; done
  oc wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus -n openshift-monitoring --timeout=600s >/dev/null 2>&1 \
    && echo "   ✅ prometheus Ready" || { echo "   ❌ prometheus pods not Ready"; FAIL=1; }
  for _ in $(seq 1 60); do oc get pod alertmanager-main-0 -n openshift-monitoring >/dev/null 2>&1 && break; sleep 10; done
  oc wait --for=condition=Ready pod/alertmanager-main-0 -n openshift-monitoring --timeout=300s >/dev/null 2>&1 \
    && echo "   ✅ alertmanager-main-0 Ready" || { echo "   ❌ alertmanager-main-0 not Ready"; FAIL=1; }
  trace_step 2 "enable_monitoring" "$FAIL" "" 2>/dev/null || true
}

run_part2() {
  echo; echo "=== Part 2: Tune Kubelet System-Reserved ==="
  if $CHECK; then
    mc_set && state ok "MachineConfig $MC present" || state no "MachineConfig $MC missing (memory 1Gi, cpu 500m, ephemeral-storage 1Gi)"
    return 0
  fi
  bash "$SKILL_DIR/apply-system-reserved.sh" | sed 's/^/   /' || { echo "   ❌ apply-system-reserved.sh failed"; FAIL=1; return 0; }
  wait_mcp
  trace_step 3 "tune_kubelet" "$FAIL" "" 2>/dev/null || true
}

run_part3() {
  echo; echo "=== Part 3: Silence Dev-Irrelevant Alerts ==="
  if $CHECK; then
    silenced && state ok "AlertmanagerReceiversNotConfigured silenced" || state no "AlertmanagerReceiversNotConfigured not silenced (needs Part 1)"
    return 0
  fi
  if ! oc get pod alertmanager-main-0 -n openshift-monitoring >/dev/null 2>&1; then
    echo "   ❌ alertmanager-main-0 not found — run Part 1 first"; FAIL=1; return 0
  fi
  bash "$SKILL_DIR/silence-alerts.sh" | sed 's/^/   /' || { echo "   ❌ silence-alerts.sh failed"; FAIL=1; }
  trace_step 4 "silence_alerts" "$FAIL" "" 2>/dev/null || true
}

run_part4() {
  echo; echo "=== Part 4: Remove Console Banner ==="
  if $CHECK; then
    banner_present && state no "consolenotification $BANNER present (would delete)" || state ok "no $BANNER banner"
    return 0
  fi
  if banner_present; then
    oc delete consolenotification "$BANNER" >/dev/null && echo "   ✅ consolenotification $BANNER deleted" || { echo "   ❌ delete failed"; FAIL=1; }
  else
    echo "   ✅ no $BANNER banner"
  fi
  trace_step 5 "remove_banner" "$FAIL" "" 2>/dev/null || true
}

if [[ -z "$PART" ]]; then run_part1; run_part2; run_part3; run_part4; else "run_part$PART"; fi

echo
if $CHECK; then
  [[ $PENDING -eq 0 ]] && echo "DRY_RUN_RESULT=CONVERGED" || echo "DRY_RUN_RESULT=PENDING"
else
  if [[ $FAIL -eq 0 ]]; then
    echo "✅ Done. No manual restart needed (the MCD rebooted the node for Part 2 if it changed)."
  else
    echo "❌ One or more parts failed (see above). Re-run is safe."
  fi
fi
trace_end 2>/dev/null || true
exit "$FAIL"
