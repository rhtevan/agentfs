#!/bin/bash
# verify.sh — Verify OVN-K FRR + MetalLB integration on CRC
# Exit on first failure for scripted use; prints summary at end for interactive use.

set -uo pipefail

PASS=0
FAIL=0
WARN=0
RESULTS=()

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    RESULTS+=("✅ PASS: $label")
    ((PASS++))
  else
    RESULTS+=("❌ FAIL: $label")
    ((FAIL++))
  fi
}

warn_check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    RESULTS+=("✅ PASS: $label")
    ((PASS++))
  else
    RESULTS+=("⚠️  WARN: $label")
    ((WARN++))
  fi
}

echo "============================================="
echo " OVN-K FRR + MetalLB Integration Verification"
echo "============================================="
echo ""

# --- Cluster connectivity ---
check "Cluster reachable" oc whoami

# --- Network operator ---
check "additionalRoutingCapabilities has FRR" \
  bash -c '[[ "$(oc get network.operator.openshift.io cluster -o jsonpath="{.spec.additionalRoutingCapabilities.providers}")" == *"FRR"* ]]'

check "Network operator Available" \
  bash -c '[[ "$(oc get co network -o jsonpath="{.status.conditions[?(@.type==\"Available\")].status}")" == "True" ]]'

check "Network operator not Degraded" \
  bash -c '[[ "$(oc get co network -o jsonpath="{.status.conditions[?(@.type==\"Degraded\")].status}")" == "False" ]]'

# --- openshift-frr-k8s namespace ---
check "openshift-frr-k8s namespace exists" \
  oc get namespace openshift-frr-k8s

check "frr-k8s DaemonSet exists in openshift-frr-k8s" \
  oc get ds frr-k8s -n openshift-frr-k8s

check "frr-k8s DaemonSet fully ready" \
  bash -c '[[ "$(oc get ds frr-k8s -n openshift-frr-k8s -o jsonpath="{.status.numberReady}")" -ge 1 ]]'

check "frr-k8s pod 7/7 Ready" \
  bash -c '
    POD=$(oc get pods -n openshift-frr-k8s -l app=frr-k8s -o name | head -1)
    [[ -n "$POD" ]] && \
    READY=$(oc get "$POD" -n openshift-frr-k8s -o jsonpath="{.status.containerStatuses[*].ready}" | tr " " "\n" | grep -c "true")
    [[ "$READY" -eq 7 ]]
  '

check "frr-k8s-statuscleaner Running" \
  bash -c '[[ "$(oc get pods -n openshift-frr-k8s -l component=frr-k8s-statuscleaner -o jsonpath="{.items[0].status.phase}")" == "Running" ]]'

# --- CRDs ---
check "BGPSessionState CRD exists" \
  oc get crd bgpsessionstates.frrk8s.metallb.io

check "FRRConfiguration CRD exists" \
  oc get crd frrconfigurations.frrk8s.metallb.io

check "MetalLB CRD exists" \
  oc get crd metallbs.metallb.io

# --- MetalLB Operator ---
check "MetalLB CSV Succeeded" \
  bash -c 'oc get csv -n metallb-system -o jsonpath="{.items[*].status.phase}" | grep -q Succeeded'

check "MetalLB operator pod Running" \
  bash -c '[[ "$(oc get pods -n metallb-system -l control-plane=controller-manager -o jsonpath="{.items[0].status.phase}")" == "Running" ]]'

check "MetalLB webhook pod Running" \
  bash -c '[[ "$(oc get pods -n metallb-system -l component=webhook-server -o jsonpath="{.items[0].status.phase}")" == "Running" ]]'

check "DEPLOY_FRRK8S_FROM_CNO=true in operator env" \
  bash -c '
    oc get deployment metallb-operator-controller-manager -n metallb-system \
      -o jsonpath="{.spec.template.spec.containers[0].env}" | grep -q "DEPLOY_FRRK8S_FROM_CNO"
  '

check "FRRK8S_EXTERNAL_NAMESPACE=openshift-frr-k8s in operator env" \
  bash -c '
    VAL=$(oc get deployment metallb-operator-controller-manager -n metallb-system \
      -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"FRRK8S_EXTERNAL_NAMESPACE\")].value}")
    [[ "$VAL" == "openshift-frr-k8s" ]]
  '

# --- MetalLB CR ---
check "MetalLB CR exists" \
  oc get metallb metallb -n metallb-system

check "MetalLB CR spec is empty (auto frr-k8s-external)" \
  bash -c '[[ "$(oc get metallb metallb -n metallb-system -o jsonpath="{.spec}")" == "{}" ]]'

check "MetalLB Available" \
  bash -c '[[ "$(oc get metallb metallb -n metallb-system -o jsonpath="{.status.conditions[?(@.type==\"Available\")].status}")" == "True" ]]'

check "MetalLB not Degraded" \
  bash -c '[[ "$(oc get metallb metallb -n metallb-system -o jsonpath="{.status.conditions[?(@.type==\"Degraded\")].status}")" == "False" ]]'

# --- MetalLB workloads ---
check "controller pod 2/2 Running" \
  bash -c '
    POD=$(oc get pods -n metallb-system -l component=controller -o name | head -1)
    [[ -n "$POD" ]] && \
    READY=$(oc get "$POD" -n metallb-system -o jsonpath="{.status.containerStatuses[*].ready}" | tr " " "\n" | grep -c "true")
    [[ "$READY" -eq 2 ]]
  '

check "speaker pod 2/2 Running" \
  bash -c '
    POD=$(oc get pods -n metallb-system -l component=speaker -o name | head -1)
    [[ -n "$POD" ]] && \
    READY=$(oc get "$POD" -n metallb-system -o jsonpath="{.status.containerStatuses[*].ready}" | tr " " "\n" | grep -c "true")
    [[ "$READY" -eq 2 ]]
  '

# --- No duplicate resources in metallb-system ---
check "No frr-k8s DaemonSet in metallb-system" \
  bash -c '! oc get ds frr-k8s -n metallb-system 2>/dev/null'

check "No statuscleaner Deployment in metallb-system" \
  bash -c '! oc get deploy frr-k8s-statuscleaner -n metallb-system 2>/dev/null'

check "Only speaker DaemonSet in metallb-system" \
  bash -c '
    DS_COUNT=$(oc get ds -n metallb-system -o name | wc -l)
    [[ "$DS_COUNT" -eq 1 ]] && oc get ds speaker -n metallb-system
  '

# --- Print summary ---
echo ""
echo "============================================="
echo " Results"
echo "============================================="
for r in "${RESULTS[@]}"; do
  echo "  $r"
done
echo ""
echo "---------------------------------------------"
echo "  Total: $((PASS + FAIL + WARN))  |  ✅ Pass: $PASS  |  ❌ Fail: $FAIL  |  ⚠️  Warn: $WARN"
echo "---------------------------------------------"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "Some checks FAILED. Review the items above."
  exit 1
else
  echo ""
  echo "All checks passed!"
  exit 0
fi
