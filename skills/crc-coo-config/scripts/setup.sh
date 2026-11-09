#!/usr/bin/env bash
# setup.sh — Install Cluster Observability Operator on CRC
#
# Usage: setup.sh [--check]
#
# Exit codes:
#   0 — COO installed and UIPlugin ready
#   1 — Error

set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-coo-config" "1.2.0" 2>/dev/null || true

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

echo "=== Cluster Observability Operator Setup ==="
echo ""

echo "1. Checking cluster..."
if ! oc whoami > /dev/null 2>&1; then
  echo "   ❌ Cannot connect."; exit 1
fi
echo "   ✅ Connected as $(oc whoami)"
MON=$(oc get co monitoring -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "unknown")
echo "   Monitoring available: $MON"
[[ "$MON" != "True" ]] && echo "   ⚠️  Enable cluster monitoring first" && exit 1
trace_step 1 "check" 0 "" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  echo ""
  echo "   COO namespace: $(oc get ns openshift-cluster-observability-operator -o name 2>/dev/null || echo 'not found')"
  echo "   CSV: $(oc get csv -n openshift-cluster-observability-operator -l operators.coreos.com/cluster-observability-operator.openshift-cluster-observability-operator -o name 2>/dev/null | head -1 || echo 'not found')"
  echo "   UIPlugin: $(oc get uiplugin monitoring -o jsonpath='{.status.conditions[0].reason}' 2>/dev/null || echo 'not found')"
  trace_end 2>/dev/null || true; exit 0
fi

echo ""
echo "2. Creating namespace..."
oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cluster-observability-operator
  labels:
    openshift.io/cluster-monitoring: "true"
EOF
echo "   ✅ Namespace created"
trace_step 2 "namespace" 0 "" 2>/dev/null || true

echo ""
echo "3. Creating OperatorGroup and Subscription..."
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  targetNamespaces:
  - openshift-cluster-observability-operator
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: stable
  installPlanApproval: Automatic
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
echo "   ✅ Subscription created"
trace_step 3 "subscription" 0 "" 2>/dev/null || true

echo ""
echo "4. Waiting for CSV (up to 300s)..."
oc wait --for=jsonpath='{.status.phase}'=Succeeded \
  csv -l operators.coreos.com/cluster-observability-operator.openshift-cluster-observability-operator \
  -n openshift-cluster-observability-operator --timeout=300s 2>/dev/null \
  && echo "   ✅ CSV succeeded" || echo "   ⚠️  Timeout"
trace_step 4 "csv_wait" 0 "" 2>/dev/null || true

echo ""
echo "5. Creating UIPlugin..."
oc apply -f - <<'EOF'
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: monitoring
spec:
  type: Monitoring
  monitoring:
    perses:
      enabled: true
    clusterHealthAnalyzer:
      enabled: true
EOF
echo "   ✅ UIPlugin created"
trace_step 5 "uiplugin" 0 "" 2>/dev/null || true

echo ""
echo "6. Waiting for UIPlugin..."
oc wait --for=jsonpath='{.status.conditions[0].reason}'=UIPluginReconciled \
  uiplugin monitoring --timeout=120s 2>/dev/null \
  && echo "   ✅ UIPlugin ready" || echo "   ⚠️  Timeout"
trace_step 6 "uiplugin_wait" 0 "" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
trace_end 2>/dev/null || true
