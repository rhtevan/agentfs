#!/bin/bash
# install-coo.sh
# Install the Cluster Observability Operator on CRC via OLM.
# Safe to run repeatedly — oc apply is idempotent.

set -euo pipefail

echo "Creating OperatorGroup and Subscription for COO..."

cat <<'EOF' | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-observability-operator
  namespace: openshift-cluster-observability-operator
spec:
  channel: stable
  name: cluster-observability-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

echo ""
echo "✅ OperatorGroup and Subscription created"
echo ""
echo "Waiting for the COO InstallPlan to be created..."
sleep 10

# Wait for the CSV to appear and succeed
echo "Waiting for COO CSV to reach Succeeded phase (up to 5 minutes)..."
for i in $(seq 1 30); do
  CSV_PHASE=$(oc get csv -n openshift-cluster-observability-operator \
    -o jsonpath='{.items[?(@.metadata.name contains "cluster-observability-operator")].status.phase}' 2>/dev/null || true)
  if echo "$CSV_PHASE" | grep -q "Succeeded"; then
    echo "✅ COO CSV phase: Succeeded"
    break
  fi
  echo "  Waiting... (attempt $i/30, current phase: ${CSV_PHASE:-pending})"
  sleep 10
done

echo ""
echo "COO operator pods:"
oc get pods -n openshift-cluster-observability-operator
echo ""
echo "Installed CRDs:"
oc get crd | grep -E 'perses|uiplugin|monitoringstack' || true
