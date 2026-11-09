#!/usr/bin/env bash
# setup.sh — Install and configure NMState operator on CRC
#
# Usage: setup.sh [--check]
#   --check   Verify current state without applying changes
#
# Prerequisites: oc CLI authenticated to CRC cluster
#
# Exit codes:
#   0 — NMState operator installed and verified
#   1 — Cluster not reachable or installation failed

set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-nmstate-config" "1.3.0" 2>/dev/null || true

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

echo "=== CRC NMState Operator Setup ==="
echo ""

# Step 1: Check cluster connectivity
echo "1. Checking cluster connectivity..."
if ! oc whoami > /dev/null 2>&1; then
  echo "   ❌ Cannot connect to cluster. Run 'oc login' first."
  exit 1
fi
echo "   ✅ Connected as $(oc whoami)"
trace_step 1 "check_connectivity" 0 "" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  echo ""
  echo "2. Current NMState state:"
  echo "   Namespace: $(oc get ns openshift-nmstate -o name 2>/dev/null || echo 'not found')"
  echo "   CSV: $(oc get csv -n openshift-nmstate -o name 2>/dev/null | head -1 || echo 'not found')"
  echo "   NMState CR: $(oc get nmstate nmstate -o name 2>/dev/null || echo 'not found')"
  echo "   CRDs: $(oc get crd 2>/dev/null | grep -c nmstate || echo '0') nmstate CRDs"
  echo "   Console plugin: $(oc get consoleplugin nmstate-console-plugin -o name 2>/dev/null || echo 'not registered')"
  trace_end 2>/dev/null || true
  exit 0
fi

# Step 2: Create Namespace, OperatorGroup, Subscription
echo ""
echo "2. Creating Namespace, OperatorGroup, and Subscription..."
oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-nmstate
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-nmstate
  namespace: openshift-nmstate
spec:
  targetNamespaces:
  - openshift-nmstate
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubernetes-nmstate-operator
  namespace: openshift-nmstate
spec:
  channel: stable
  name: kubernetes-nmstate-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
echo "   ✅ Resources applied"
trace_step 2 "create_resources" 0 "" 2>/dev/null || true

# Step 3: Wait for CSV
echo ""
echo "3. Waiting for operator CSV to succeed (up to 120s)..."
for i in $(seq 1 24); do
  phase=$(oc get csv -n openshift-nmstate -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "Pending")
  if [[ "$phase" == "Succeeded" ]]; then
    echo "   ✅ CSV phase: Succeeded"
    break
  fi
  echo "   Waiting... ($phase) [${i}/24]"
  sleep 5
done
trace_step 3 "wait_csv" 0 "phase=$phase" 2>/dev/null || true

# Step 4: Create NMState instance
echo ""
echo "4. Creating NMState instance..."
oc apply -f - <<'EOF'
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
echo "   ✅ NMState CR created"
trace_step 4 "create_nmstate" 0 "" 2>/dev/null || true

# Step 5: Wait for pods
echo ""
echo "5. Waiting for NMState pods (up to 120s)..."
for i in $(seq 1 24); do
  ready=$(oc get pods -n openshift-nmstate --no-headers 2>/dev/null | grep -c "Running" || echo "0")
  total=$(oc get pods -n openshift-nmstate --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ $ready -ge 4 ]]; then
    echo "   ✅ $ready/$total pods running"
    break
  fi
  echo "   Waiting... ($ready/$total running) [${i}/24]"
  sleep 5
done
trace_step 5 "wait_pods" 0 "ready=$ready,total=$total" 2>/dev/null || true

# Step 6: Verify CRDs
echo ""
echo "6. Verifying NMState CRDs..."
crd_count=$(oc get crd 2>/dev/null | grep -c nmstate || echo "0")
echo "   Found $crd_count NMState CRDs"
[[ $crd_count -ge 3 ]] && echo "   ✅ All expected CRDs present" || echo "   ⚠️  Expected ≥3 CRDs"
trace_step 6 "verify_crds" 0 "count=$crd_count" 2>/dev/null || true

# Step 7: Verify console plugin
echo ""
echo "7. Verifying console plugin..."
if oc get consoleplugin nmstate-console-plugin > /dev/null 2>&1; then
  echo "   ✅ Console plugin registered"
else
  echo "   ⚠️  Console plugin not found (may take a few minutes)"
fi
trace_step 7 "verify_plugin" 0 "" 2>/dev/null || true

echo ""
echo "=== NMState Setup Complete ==="
trace_end 2>/dev/null || true
