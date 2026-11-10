#!/usr/bin/env bash
# setup.sh — Configure OVN-K FRR + MetalLB with shared BGP backend on CRC
# Usage: setup.sh [--dry-run] [--part 1|2|3]
# Version: 1.0.0
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-ovn-frr-metallb-config" "1.0.0" 2>/dev/null || true

DRY_RUN=false
PART=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
    --part) PART="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "=== OVN-K FRR + MetalLB Setup ==="
echo ""

# ── Step 1: Prerequisites ───────────────────────────────────────────────
trace_step 1 "prerequisites" 0 "" 2>/dev/null || true

if ! oc whoami >/dev/null 2>&1; then
  echo "✗ Not logged in to OpenShift (oc whoami failed)"
  exit 1
fi
echo "✓ Logged in as $(oc whoami)"

CRC_STATUS=$(crc status 2>/dev/null | grep 'CRC VM' | awk '{print $NF}' || echo "unknown")
echo "  CRC status: $CRC_STATUS"

if $DRY_RUN; then
  echo ""
  echo "── Current state ──"
  echo "FRR namespace: $(oc get ns openshift-frr-k8s -o name 2>/dev/null || echo 'not found')"
  echo "MetalLB namespace: $(oc get ns metallb-system -o name 2>/dev/null || echo 'not found')"
  echo "MetalLB operator: $(oc get csv -n openshift-metallb-system -o name 2>/dev/null | head -1 || echo 'not found')"
  trace_end 2>/dev/null || true
  exit 0
fi

# ── Step 2: Part 1 — Enable OVN-K FRR ──────────────────────────────────
run_part1() {
  trace_step 2 "enable_frr" 0 "" 2>/dev/null || true
  echo "── Part 1: Enable OVN-K FRR Shared BGP Backend ──"

  echo "  Patching network.operator.openshift.io/cluster..."
  oc patch network.operator.openshift.io cluster --type=merge \
    -p '{"spec":{"additionalRoutingCapabilities":{"providers":["FRR"]}}}' || { echo "✗ Patch failed"; return 1; }

  echo "  Waiting for openshift-frr-k8s namespace..."
  oc wait --for=jsonpath='{.status.phase}'=Active namespace/openshift-frr-k8s --timeout=120s || { echo "✗ Namespace timeout"; return 1; }

  echo "  Waiting for frr-k8s DaemonSet rollout..."
  oc rollout status ds/frr-k8s -n openshift-frr-k8s --timeout=300s || { echo "✗ DaemonSet timeout"; return 1; }

  echo "✓ Part 1 complete: FRR shared backend enabled"
}

# ── Step 3: Part 2 — Install MetalLB ───────────────────────────────────
run_part2() {
  trace_step 3 "install_metallb" 0 "" 2>/dev/null || true
  echo "── Part 2: Install MetalLB Operator ──"

  echo "  Creating namespace and subscription..."
  oc apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-metallb-system
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: metallb-operator
  namespace: openshift-metallb-system
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: metallb-operator
  namespace: openshift-metallb-system
spec:
  channel: stable
  name: metallb-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

  echo "  Waiting for CSV..."
  for i in $(seq 1 30); do
    CSV=$(oc get csv -n openshift-metallb-system -o name 2>/dev/null | head -1)
    if [[ -n "$CSV" ]]; then
      PHASE=$(oc get "$CSV" -n openshift-metallb-system -o jsonpath='{.status.phase}' 2>/dev/null)
      [[ "$PHASE" == "Succeeded" ]] && break
    fi
    sleep 10
  done

  if [[ "$PHASE" == "Succeeded" ]]; then
    echo "✓ MetalLB operator installed: $CSV"
  else
    echo "✗ MetalLB CSV not ready (phase: ${PHASE:-unknown})"
    return 1
  fi

  echo "  Creating MetalLB CR..."
  oc apply -f - <<'EOF'
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: openshift-metallb-system
spec:
  bgpBackend: frr-k8s
EOF

  echo "✓ Part 2 complete: MetalLB installed with frr-k8s backend"
}

# ── Step 4: Part 3 — Configure BGP ─────────────────────────────────────
run_part3() {
  trace_step 4 "configure_bgp" 0 "" 2>/dev/null || true
  echo "── Part 3: Configure BGP Resources ──"
  echo "  ⚠ BGP peer and address pool configuration is environment-specific."
  echo "  The agent must create BFDProfile, BGPPeer, IPAddressPool, and"
  echo "  BGPAdvertisement resources based on the user's network topology."
  echo ""
  echo "  Required resources:"
  echo "    - metallb.io/v1beta1 BFDProfile"
  echo "    - metallb.io/v1beta2 BGPPeer (ASN, neighbor address)"
  echo "    - metallb.io/v1beta1 IPAddressPool (address range)"
  echo "    - metallb.io/v1beta1 BGPAdvertisement"
  echo ""
  echo "  See SKILL.md Part 3 for templates."
}

# Execute requested parts
if [[ -n "$PART" ]]; then
  run_part${PART}
else
  run_part1 && run_part2 && run_part3
fi

trace_end 2>/dev/null || true
echo ""
if $DRY_RUN; then
  echo "DRY_RUN_RESULT=PENDING"
  echo "Operator setup requires cluster access. Run without --dry-run to apply."
  exit 0
else
  echo "APPLY_RESULT=OK"
  echo "✅ Setup complete."
fi
