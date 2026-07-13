---
name: crc-ovn-frr-metallb-config
description: >
  Set up OVN-Kubernetes FRR shared BGP backend and MetalLB Operator
  integration on an OpenShift Local (CRC) cluster. This skill
  re-establishes the full OVN-FRR and MetalLB integration after a
  `crc delete && crc start` cycle.
metadata:
  tags: [openshift, crc, networking, ovn, bgp, metallb]
---

# CRC OVN-K FRR + MetalLB Integration Configuration

Set up OVN-Kubernetes FRR shared BGP backend and MetalLB Operator integration on an OpenShift Local (CRC) cluster. This skill re-establishes the full OVN-FRR and MetalLB integration after a `crc delete && crc start` cycle.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  CRC Node                                                       │
│                                                                 │
│  ┌──────────────────────┐    ┌───────────────────────────────┐  │
│  │  metallb-system       │    │  openshift-frr-k8s            │  │
│  │                       │    │                               │  │
│  │  controller (2/2)     │    │  frr-k8s (7/7) ◄─── CNO      │  │
│  │  speaker    (2/2) ────┼───►│    controller                 │  │
│  │  operator-ctrl-mgr    │    │    frr                        │  │
│  │  operator-webhook     │    │    frr-metrics                │  │
│  │                       │    │    frr-status                 │  │
│  │  NO frr-k8s DS here   │    │    kube-rbac-proxy (×2)       │  │
│  │  NO statuscleaner     │    │    reloader                   │  │
│  │                       │    │  statuscleaner (1/1)          │  │
│  └──────────────────────┘    └───────────────────────────────┘  │
│                                                                 │
│  Network.operator ─── additionalRoutingCapabilities: [FRR]      │
│  MetalLB CR ────────── spec: {}  (auto frr-k8s-external mode)   │
└─────────────────────────────────────────────────────────────────┘
```

### How the Integration Works

- The **Cluster Network Operator (CNO)** deploys and manages the `frr-k8s` DaemonSet in the `openshift-frr-k8s` namespace when `additionalRoutingCapabilities.providers: [FRR]` is set on the Network operator CR.
- The **MetalLB Operator** detects env vars `DEPLOY_FRRK8S_FROM_CNO=true` and `FRRK8S_EXTERNAL_NAMESPACE=openshift-frr-k8s` (injected by OLM/CNO) and auto-selects `frr-k8s-external` BGP backend mode.
- In `frr-k8s-external` mode, the MetalLB operator does **not** deploy its own frr-k8s DaemonSet or statuscleaner — it uses the CNO-managed instance. This avoids duplicate DaemonSets and hostNetwork port conflicts.
- The MetalLB CR should use `spec: {}` (empty spec) to let the operator auto-detect the correct mode. Setting `bgpBackend: frr-k8s-external` explicitly also works but is not documented in official Red Hat docs — the field is described as "reserved for internal use."

### Key BGP Backend Modes (reference)

| `bgpBackend` value | Description |
|---------------------|-------------|
| `frr` | MetalLB deploys embedded FRR sidecar in speaker (legacy) |
| `frr-k8s` | MetalLB operator deploys its own frr-k8s DaemonSet in metallb-system |
| `frr-k8s-external` | MetalLB uses an externally-managed frr-k8s (e.g., CNO-managed in openshift-frr-k8s) — **auto-selected when `DEPLOY_FRRK8S_FROM_CNO=true`** |
| `native` | Native BGP (not supported on OpenShift) |

## Prerequisites

- CRC cluster is started and reachable (`crc status` shows Running)
- `oc` CLI available (`eval $(crc oc-env)`)
- Logged in as kubeadmin (`oc login -u kubeadmin -p kubeadmin https://api.crc.testing:6443`)
- Cluster monitoring is enabled (see skill `crc-post-setup-config`)

## Steps

### Part 1 — Enable OVN-K FRR Shared BGP Backend

This tells the Cluster Network Operator to deploy the shared frr-k8s DaemonSet that both OVN-Kubernetes and MetalLB will use for BGP.

1. **Patch the Network operator CR to enable FRR routing capabilities**

   ```bash
   oc patch network.operator.openshift.io cluster --type=merge \
     -p '{"spec":{"additionalRoutingCapabilities":{"providers":["FRR"]}}}'
   ```

2. **Wait for the `openshift-frr-k8s` namespace to appear and become active**

   ```bash
   oc wait --for=jsonpath='{.status.phase}'=Active namespace/openshift-frr-k8s --timeout=120s
   ```

3. **Wait for the frr-k8s DaemonSet to roll out**

   ```bash
   oc rollout status ds/frr-k8s -n openshift-frr-k8s --timeout=300s
   ```

4. **Verify the frr-k8s pod is fully ready (all 7 containers)**

   ```bash
   oc wait --for=condition=Ready pod -l app=frr-k8s -n openshift-frr-k8s --timeout=300s
   oc get pods -n openshift-frr-k8s
   ```

   Expected: `frr-k8s-XXXXX` pod shows `7/7 Running` and `frr-k8s-statuscleaner-XXXXX` shows `1/1 Running`.

   The 7 containers in the frr-k8s pod are:
   - `controller` — main frr-k8s controller reconciling FRRConfiguration CRs
   - `frr` — FRRouting daemon (bgpd, zebra, etc.)
   - `frr-metrics` — exports FRR metrics for Prometheus
   - `frr-status` — syncs BGPSessionState CRs with live FRR state
   - `kube-rbac-proxy` — secures the metrics endpoint
   - `kube-rbac-proxy-frr` — secures the FRR metrics endpoint
   - `reloader` — watches for FRR config changes and triggers reload

5. **Verify the BGPSessionState CRD exists**

   ```bash
   oc get crd bgpsessionstates.frrk8s.metallb.io
   ```

   If missing (unlikely with current OCP versions, but was an issue historically), apply from upstream:
   ```bash
   oc apply -f https://raw.githubusercontent.com/metallb/frr-k8s/main/config/crd/bases/frrk8s.metallb.io_bgpsessionstates.yaml
   ```

6. **Verify the Network operator is not degraded**

   ```bash
   oc get co network
   ```

   Expected: `AVAILABLE=True`, `DEGRADED=False`.

### Part 2 — Install MetalLB Operator

7. **Create the `metallb-system` namespace**

   ```bash
   cat <<EOF | oc apply -f -
   apiVersion: v1
   kind: Namespace
   metadata:
     name: metallb-system
     labels:
       openshift.io/cluster-monitoring: "true"
   EOF
   ```

8. **Create the OperatorGroup**

   ```bash
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1
   kind: OperatorGroup
   metadata:
     name: metallb-system
     namespace: metallb-system
   EOF
   ```

   Note: Use an all-namespace OperatorGroup (no `spec.targetNamespaces`). This is required for the MetalLB operator to watch cluster-scoped resources.

9. **Create the Subscription**

   ```bash
   cat <<EOF | oc apply -f -
   apiVersion: operators.coreos.com/v1alpha1
   kind: Subscription
   metadata:
     name: metallb-operator
     namespace: metallb-system
   spec:
     channel: stable
     name: metallb-operator
     source: redhat-operators
     sourceNamespace: openshift-marketplace
     installPlanApproval: Automatic
   EOF
   ```

10. **Wait for the operator CSV to succeed**

    ```bash
    # Wait for the CSV to appear (name changes with each release)
    sleep 30
    CSV=$(oc get csv -n metallb-system -o name | grep metallb)
    oc wait --for=jsonpath='{.status.phase}'=Succeeded "$CSV" -n metallb-system --timeout=300s
    ```

11. **Wait for operator pods to be ready**

    ```bash
    oc wait --for=condition=Ready pod -l control-plane=controller-manager -n metallb-system --timeout=120s
    oc wait --for=condition=Ready pod -l component=webhook-server -n metallb-system --timeout=120s
    ```

### Part 3 — Create MetalLB Instance (with Shared FRR Backend)

12. **Verify the operator has the CNO integration env vars**

    Before creating the MetalLB CR, confirm the operator knows about the external frr-k8s:

    ```bash
    oc get deployment metallb-operator-controller-manager -n metallb-system \
      -o jsonpath='{.spec.template.spec.containers[0].env}' | python3 -m json.tool \
      | grep -A1 'DEPLOY_FRRK8S_FROM_CNO\|FRRK8S_EXTERNAL_NAMESPACE'
    ```

    Expected output:
    ```
    "name": "DEPLOY_FRRK8S_FROM_CNO",
    "value": "true"
    "name": "FRRK8S_EXTERNAL_NAMESPACE",
    "value": "openshift-frr-k8s"
    ```

    If `DEPLOY_FRRK8S_FROM_CNO` is missing or not `true`, it means the CNO hasn't injected the env vars yet — ensure Part 1 (step 1) was applied and the Network operator has reconciled. The MetalLB operator pod may need to be restarted after the Network CR is patched.

13. **Create the MetalLB CR with empty spec**

    ```bash
    cat <<EOF | oc apply -f -
    apiVersion: metallb.io/v1beta1
    kind: MetalLB
    metadata:
      name: metallb
      namespace: metallb-system
    spec: {}
    EOF
    ```

    **Important:** Use `spec: {}` (empty). The operator auto-selects `frr-k8s-external` mode when `DEPLOY_FRRK8S_FROM_CNO=true`. Do **not** set `bgpBackend: frr-k8s` — that would cause the operator to deploy its own frr-k8s DaemonSet and statuscleaner in `metallb-system`, creating duplicate pods and hostNetwork port conflicts with the CNO-managed frr-k8s.

14. **Wait for MetalLB to become available**

    ```bash
    oc wait --for=jsonpath='{.status.conditions[?(@.type=="Available")].status}'=True \
      metallb/metallb -n metallb-system --timeout=300s
    ```

15. **Wait for controller and speaker pods**

    ```bash
    oc wait --for=condition=Ready pod -l component=controller -n metallb-system --timeout=120s
    oc wait --for=condition=Ready pod -l component=speaker -n metallb-system --timeout=120s
    ```

## Verification

Run all checks to confirm the integration is correct:

```bash
bash <skill-dir>/verify.sh
```

### Manual Verification Checklist

**Network Operator:**
- [ ] `oc get network.operator.openshift.io cluster -o jsonpath='{.spec.additionalRoutingCapabilities}'` returns `{"providers":["FRR"]}`
- [ ] `oc get co network` shows `AVAILABLE=True`, `DEGRADED=False`

**openshift-frr-k8s namespace (CNO-managed):**
- [ ] `oc get ds -n openshift-frr-k8s` shows `frr-k8s` DaemonSet with READY count matching DESIRED
- [ ] `oc get pods -n openshift-frr-k8s` shows `frr-k8s-XXXXX` at `7/7 Running`
- [ ] `oc get pods -n openshift-frr-k8s` shows `frr-k8s-statuscleaner-XXXXX` at `1/1 Running`

**MetalLB Operator:**
- [ ] `oc get csv -n metallb-system` shows metallb-operator CSV in `Succeeded` phase
- [ ] Operator env confirms CNO integration:
      `DEPLOY_FRRK8S_FROM_CNO=true` and `FRRK8S_EXTERNAL_NAMESPACE=openshift-frr-k8s`

**MetalLB CR:**
- [ ] `oc get metallb metallb -n metallb-system -o jsonpath='{.spec}'` returns `{}` (empty)
- [ ] MetalLB status shows `Available=True`, `Degraded=False`

**metallb-system pods:**
- [ ] `controller` pod is `2/2 Running`
- [ ] `speaker` pod is `2/2 Running`
- [ ] `metallb-operator-controller-manager` pod is `1/1 Running`
- [ ] `metallb-operator-webhook-server` pod is `1/1 Running`
- [ ] **No** frr-k8s pods exist in `metallb-system`

**No duplicate resources:**
- [ ] `oc get ds -n metallb-system` shows only `speaker` (no `frr-k8s`)
- [ ] `oc get deploy -n metallb-system` shows only `controller`, `metallb-operator-controller-manager`, `metallb-operator-webhook-server` (no `statuscleaner`)

**CRDs:**
- [ ] `oc get crd bgpsessionstates.frrk8s.metallb.io` exists
- [ ] `oc get crd frrconfigurations.frrk8s.metallb.io` exists
- [ ] `oc get crd metallbs.metallb.io` exists

## Troubleshooting

### frr-k8s pod not reaching 7/7 Ready

**frr-status container CrashLoopBackOff — RBAC error:**
If the `frr-status` container crashes with `pods "frr-k8s-XXXXX" is forbidden`, the service account is missing RBAC to get pods. Create the missing Role and RoleBinding:
```bash
oc create role frr-k8s-daemon-pods --verb=get,list,watch --resource=pods -n openshift-frr-k8s
oc create rolebinding frr-k8s-daemon-pods --role=frr-k8s-daemon-pods --serviceaccount=openshift-frr-k8s:frr-k8s-daemon -n openshift-frr-k8s
```

**frr-status container CrashLoopBackOff — missing BGPSessionState CRD:**
If `frr-status` crashes with `no matches for kind "BGPSessionState"`, apply the CRD:
```bash
oc apply -f https://raw.githubusercontent.com/metallb/frr-k8s/main/config/crd/bases/frrk8s.metallb.io_bgpsessionstates.yaml
```
Then create RBAC for the frr-k8s service account:
```bash
oc create clusterrole frr-k8s-bgpsessionstates --verb=get,list,watch,create,update,patch,delete --resource=bgpsessionstates,bgpsessionstates/status --resource-name="" 2>/dev/null
oc create clusterrolebinding frr-k8s-bgpsessionstates --clusterrole=frr-k8s-bgpsessionstates --serviceaccount=openshift-frr-k8s:frr-k8s-daemon 2>/dev/null
```

**statuscleaner CreateContainerConfigError:**
If `statuscleaner` has `CreateContainerConfigError` with message about `runAsNonRoot` and non-numeric user, patch:
```bash
oc patch deployment frr-k8s-statuscleaner -n openshift-frr-k8s --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/securityContext/runAsUser","value":65534}]'
```

### Duplicate frr-k8s DaemonSet in metallb-system

This happens if the MetalLB CR was created with `bgpBackend: frr-k8s` instead of empty spec. Fix:
1. Delete the MetalLB CR: `oc delete metallb metallb -n metallb-system`
2. Manually delete the stale DaemonSet: `oc delete ds frr-k8s -n metallb-system`
3. Manually delete the stale Deployment: `oc delete deploy frr-k8s-statuscleaner -n metallb-system` (if present)
4. Recreate the MetalLB CR with `spec: {}`

### MetalLB CR disappears after operator upgrade

OLM auto-upgrades may occasionally lose the MetalLB CR. Simply recreate it:
```bash
cat <<EOF | oc apply -f -
apiVersion: metallb.io/v1beta1
kind: MetalLB
metadata:
  name: metallb
  namespace: metallb-system
spec: {}
EOF
```

### Speaker or controller not starting

Check the MetalLB operator logs:
```bash
oc logs deployment/metallb-operator-controller-manager -n metallb-system | tail -50
```
Common cause: the MetalLB CR does not exist. Verify with `oc get metallb -n metallb-system`.

## Supporting Files

Skill directory: ~/.agents/skills/crc-ovn-frr-metallb-config

- verify.sh → load_skill(name: "crc-ovn-frr-metallb-config/verify.sh")

## Notes

- The `bgpBackend` field is documented in official OpenShift docs as "reserved for internal use" — users should not set it. The `frr-k8s-external` value was introduced in commit `a3972fe18e9f` (2024-07-18, by Federico Paolinelli) and has been present since release-4.17, but remains undocumented.
- The operator auto-detects the correct mode via env vars injected by the CNO/OLM pipeline, so `spec: {}` is the correct and forward-compatible approach.
- The order matters: enable `additionalRoutingCapabilities` on the Network CR **before** installing the MetalLB Operator, so the CNO env vars are present when the operator starts.
- After `crc delete && crc start`, the CatalogSource may take a few minutes to become READY before the MetalLB Subscription can resolve. Wait for `oc get catsrc redhat-operators -n openshift-marketplace -o jsonpath='{.status.connectionState.lastObservedState}'` to return `READY`.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-01 00:00 | v1.1 — Added missing YAML frontmatter (name + description) |
| 2026-06-19 19:04 | v1.0 — Initial skill |
