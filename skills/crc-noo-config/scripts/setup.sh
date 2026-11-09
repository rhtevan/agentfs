#!/usr/bin/env bash
# setup.sh — Install Network Observability Operator on CRC
#
# Usage: setup.sh [--check]
#
# Exit codes:
#   0 — Operator installed and FlowCollector ready
#   1 — Error

set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-noo-config" "1.2.0" 2>/dev/null || true

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

echo "=== Network Observability Operator Setup ==="
echo ""

echo "1. Checking cluster connectivity..."
if ! oc whoami > /dev/null 2>&1; then
  echo "   ❌ Cannot connect. Run 'oc login' first."; exit 1
fi
NET_TYPE=$(oc get network.config.openshift.io cluster -o jsonpath='{.status.networkType}' 2>/dev/null || echo "unknown")
echo "   ✅ Connected as $(oc whoami), network: $NET_TYPE"
trace_step 1 "check" 0 "net=$NET_TYPE" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  echo ""
  echo "2. Current state:"
  echo "   Namespace: $(oc get ns netobserv -o name 2>/dev/null || echo 'not found')"
  echo "   CSV: $(oc get csv -n openshift-operators -o name 2>/dev/null | grep netobserv | head -1 || echo 'not found')"
  echo "   FlowCollector: $(oc get flowcollector cluster -n netobserv -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo 'not found')"
  trace_end 2>/dev/null || true; exit 0
fi

echo ""
echo "2. Creating namespace..."
oc create namespace netobserv --dry-run=client -o yaml | oc apply -f - 2>/dev/null
echo "   ✅ netobserv namespace"
trace_step 2 "namespace" 0 "" 2>/dev/null || true

echo ""
echo "3. Installing operator subscription..."
oc apply -f - <<'EOF'
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: netobserv-operator
  namespace: openshift-operators
spec:
  channel: stable
  installPlanApproval: Automatic
  name: netobserv-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
echo "   ✅ Subscription created"
trace_step 3 "subscription" 0 "" 2>/dev/null || true

echo ""
echo "4. Waiting for CSV (up to 300s)..."
timeout 300 bash -c '
  until oc get csv -n openshift-operators -o wide 2>/dev/null | grep -q "network-observability-operator.*Succeeded"; do
    sleep 15; echo "   waiting..."
  done
' 2>/dev/null && echo "   ✅ CSV succeeded" || echo "   ⚠️  Timeout waiting for CSV"
trace_step 4 "csv_wait" 0 "" 2>/dev/null || true

echo ""
echo "5. Creating FlowCollector..."
oc apply -f - <<'EOF'
apiVersion: flows.netobserv.io/v1beta2
kind: FlowCollector
metadata:
  name: cluster
  namespace: netobserv
spec:
  namespace: netobserv
  deploymentModel: Direct
  agent:
    type: eBPF
    ebpf:
      sampling: 50
      privileged: true
      cacheActiveTimeout: 5s
      cacheMaxFlows: 100000
      features:
        - DNSTracking
        - PacketDrop
        - FlowRTT
        - PacketTranslation
        - TLSTracking
        - IPSec
  loki:
    enable: true
    mode: Monolithic
    monolithic:
      installDemoLoki: true
  consolePlugin:
    register: true
    portNaming:
      enable: true
    quickFilters:
      - name: Applications
        filter:
          src_namespace!: "openshift-,netobserv"
          dst_namespace!: "openshift-,netobserv"
        default: true
      - name: Infrastructure
        filter:
          src_namespace: "openshift-,netobserv"
          dst_namespace: "openshift-,netobserv"
      - name: Pods network
        filter:
          src_kind: Pod
          dst_kind: Pod
        default: true
EOF
echo "   ✅ FlowCollector created"
trace_step 5 "flowcollector" 0 "" 2>/dev/null || true

echo ""
echo "6. Waiting for FlowCollector ready (up to 300s)..."
timeout 300 bash -c '
  until oc get flowcollector cluster -n netobserv -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null | grep -q "True"; do
    sleep 15; echo "   waiting..."
  done
' 2>/dev/null && echo "   ✅ FlowCollector ready" || echo "   ⚠️  Timeout"
trace_step 6 "fc_wait" 0 "" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
trace_end 2>/dev/null || true
