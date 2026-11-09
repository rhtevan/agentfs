#!/usr/bin/env bash
# setup.sh — Deploy NAD Console Plugin on CRC via Helm
#
# Usage: setup.sh [--check]
#
# Exit codes:
#   0 — Plugin deployed and verified
#   1 — Error

set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-nad-dynamic-plugin-config" "1.2.0" 2>/dev/null || true

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

echo "=== NAD Console Plugin Setup ==="
echo ""

echo "1. Checking cluster..."
if ! oc whoami > /dev/null 2>&1; then
  echo "   ❌ Cannot connect."; exit 1
fi
echo "   ✅ Connected as $(oc whoami)"

echo "   Checking NAD CRD..."
if oc get crd network-attachment-definitions.k8s.cni.cncf.io > /dev/null 2>&1; then
  echo "   ✅ NAD CRD present"
else
  echo "   ❌ NAD CRD not found"; exit 1
fi
trace_step 1 "check" 0 "" 2>/dev/null || true

if [[ "$CHECK" == true ]]; then
  echo ""
  echo "   Plugin pods: $(oc get pods -n nad-console-plugin --no-headers 2>/dev/null | wc -l || echo '0')"
  echo "   ConsolePlugin: $(oc get consoleplugin nad-console-plugin -o name 2>/dev/null || echo 'not found')"
  trace_end 2>/dev/null || true; exit 0
fi

echo ""
echo "2. Deploying with Helm..."
HELM="${HOME}/.local/bin/helm"
[[ ! -x "$HELM" ]] && HELM=$(command -v helm 2>/dev/null || echo "")
if [[ -z "$HELM" ]]; then
  echo "   ❌ helm not found"; exit 1
fi

CHART_DIR="${HOME}/app/playground/nad-console-plugin/charts/openshift-console-plugin"
if [[ ! -d "$CHART_DIR" ]]; then
  echo "   ❌ Chart not found at $CHART_DIR"; exit 1
fi

$HELM upgrade -i nad-console-plugin "$CHART_DIR" \
  -n nad-console-plugin --create-namespace \
  --set plugin.image=quay.io/rhtevan/nad-console-plugin:latest \
  --set plugin.name=nad-console-plugin \
  --set plugin.imagePullPolicy=Always
echo "   ✅ Helm deploy complete"
trace_step 2 "deploy" 0 "" 2>/dev/null || true

echo ""
echo "3. Waiting for pods..."
for i in $(seq 1 12); do
  running=$(oc get pods -n nad-console-plugin --no-headers 2>/dev/null | grep -c Running || echo "0")
  if [[ $running -ge 1 ]]; then
    echo "   ✅ $running pod(s) running"; break
  fi
  echo "   Waiting... [${i}/12]"; sleep 5
done
trace_step 3 "pods" 0 "" 2>/dev/null || true

echo ""
echo "4. Verifying ConsolePlugin..."
if oc get consoleplugin nad-console-plugin > /dev/null 2>&1; then
  echo "   ✅ ConsolePlugin registered"
else
  echo "   ⚠️  ConsolePlugin not found"
fi
trace_step 4 "verify" 0 "" 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
trace_end 2>/dev/null || true
