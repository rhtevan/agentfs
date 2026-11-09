#!/usr/bin/env bash
# setup.sh — CRC post-setup configuration
#
# Applies post-setup tuning to a CRC cluster:
# - Enable cluster monitoring
# - Tune kubelet system-reserved resources
# - Silence dev-irrelevant alerts
#
# Usage: setup.sh [--part N] [--check]
#   --part N   Run only part N (1=monitoring, 2=kubelet, 3=alerts)
#   --check    Dry-run: check current state without applying changes
#
# Prerequisites: oc CLI authenticated to CRC cluster
#
# Exit codes:
#   0 — All parts applied successfully
#   1 — Cluster not reachable or oc command failed

set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-post-setup-config" "1.3.0" 2>/dev/null || true

PART=""
CHECK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --part) PART="$2"; shift 2 ;;
    --check) CHECK=true; shift ;;
    *) echo "Usage: setup.sh [--part N] [--check]" >&2; exit 2 ;;
  esac
done

# Verify cluster connectivity
echo "=== CRC Post-Setup Configuration ==="
echo ""
echo "1. Checking cluster connectivity..."
if ! oc whoami > /dev/null 2>&1; then
  echo "   ❌ Cannot connect to cluster. Run 'oc login' first."
  exit 1
fi
CLUSTER=$(oc cluster-info 2>/dev/null | head -1 || echo "unknown")
echo "   ✅ Connected: $CLUSTER"
trace_step 1 "check_connectivity" 0 "cluster=$CLUSTER" 2>/dev/null || true

run_part1() {
  echo ""
  echo "=== Part 1: Enable Cluster Monitoring ==="
  if [[ "$CHECK" == true ]]; then
    echo "   Current state:"
    crc config get enable-cluster-monitoring 2>/dev/null || echo "   (not set)"
    return
  fi
  crc config set enable-cluster-monitoring true
  echo "   ✅ CRC monitoring config set"

  # Remove monitoring overrides from ClusterVersion
  echo "   Removing monitoring overrides from ClusterVersion..."
  OVERRIDES=$(oc get clusterversion version -o json | python3 -c "
import sys, json
cv = json.load(sys.stdin)
overrides = cv.get('spec', {}).get('overrides', [])
kept = [o for o in overrides
        if not (o.get('name') == 'cluster-monitoring-operator' or
                (o.get('kind') == 'ClusterOperator' and o.get('name') == 'monitoring'))]
if len(kept) < len(overrides):
    print(json.dumps(kept))
else:
    print('NONE')
" 2>/dev/null || echo "NONE")

  if [[ "$OVERRIDES" != "NONE" ]]; then
    oc patch clusterversion version --type=json -p "[
      {\"op\": \"replace\", \"path\": \"/spec/overrides\", \"value\": $OVERRIDES}
    ]" 2>/dev/null && echo "   ✅ Monitoring overrides removed" || echo "   ⚠️  Patch failed"
  else
    echo "   ✅ No monitoring overrides to remove"
  fi
  trace_step 2 "enable_monitoring" 0 "" 2>/dev/null || true
}

run_part2() {
  echo ""
  echo "=== Part 2: Tune Kubelet System-Reserved ==="
  if [[ "$CHECK" == true ]]; then
    echo "   Current KubeletConfig:"
    oc get kubeletconfig crc-system-reserved -o yaml 2>/dev/null || echo "   (not found)"
    return
  fi
  oc apply -f - <<'EOF'
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: crc-system-reserved
spec:
  kubeletConfig:
    systemReserved:
      cpu: "500m"
      memory: "512Mi"
      ephemeral-storage: "1Gi"
EOF
  echo "   ✅ KubeletConfig applied"
  trace_step 3 "tune_kubelet" 0 "" 2>/dev/null || true
}

run_part3() {
  echo ""
  echo "=== Part 3: Silence Dev-Irrelevant Alerts ==="
  if [[ "$CHECK" == true ]]; then
    echo "   Current silences:"
    oc -n openshift-monitoring exec -c alertmanager alertmanager-main-0 -- \
      amtool silence query 2>/dev/null | head -10 || echo "   (none)"
    return
  fi
  # Silence common noisy alerts for dev clusters
  ALERTS="KubeCPUOvercommit KubeMemoryOvercommit etcdMembersDown"
  for alert in $ALERTS; do
    oc -n openshift-monitoring exec -c alertmanager alertmanager-main-0 -- \
      amtool silence add alertname="$alert" \
      --comment="CRC dev cluster — not relevant" \
      --duration="8760h" 2>/dev/null && echo "   ✅ Silenced: $alert" || echo "   ⚠️  Could not silence: $alert"
  done
  trace_step 4 "silence_alerts" 0 "" 2>/dev/null || true
}

# Run requested parts
if [[ -z "$PART" ]]; then
  run_part1
  run_part2
  run_part3
else
  case "$PART" in
    1) run_part1 ;;
    2) run_part2 ;;
    3) run_part3 ;;
    *) echo "Unknown part: $PART (use 1, 2, or 3)" >&2; exit 2 ;;
  esac
fi

echo ""
echo "=== Done ==="
trace_end 2>/dev/null || true
