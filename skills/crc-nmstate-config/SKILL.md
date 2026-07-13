---
name: crc-nmstate-config
description: Install and configure the NMState Operator on OpenShift Local (CRC), verify the nmstate-console-plugin is functioning, and confirm NodeNetworkConfigurationPolicy (NNCP) and NodeNetworkState (NNS) menu items appear in the OpenShift Console Networking section.
metadata:
  tags: [openshift, crc, networking, nmstate, operator]
---

# CRC NMState Operator Configuration

Install the NMState Operator on OpenShift Local (CRC) and verify that the console plugin and networking menu items are working correctly.

## Prerequisites

- CRC cluster is running (`crc status` shows Running)
- `oc` is logged in as `kubeadmin` (`oc whoami` returns `kubeadmin`)
- OpenShift Console is accessible

## Step 1: Create Namespace, OperatorGroup, and Subscription

Apply all three resources in one pass:

```bash
oc apply -f - <<EOF
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
```

## Step 2: Wait for the Operator to Be Ready

Wait for the CSV to reach `Succeeded` phase:

```bash
oc get csv -n openshift-nmstate --watch
```

Expected output eventually shows:
```
kubernetes-nmstate-operator.v...   kubernetes-nmstate-operator   ...   Succeeded
```

## Step 3: Create the NMState Instance

```bash
oc apply -f - <<EOF
apiVersion: nmstate.io/v1
kind: NMState
metadata:
  name: nmstate
EOF
```

## Step 4: Wait for All NMState Pods to Be Running

```bash
oc get pods -n openshift-nmstate --watch
```

Expected running pods:
- `nmstate-console-plugin-*`
- `nmstate-handler-*` (DaemonSet, one per node)
- `nmstate-metrics-*`
- `nmstate-operator-*`
- `nmstate-webhook-*`

## Step 5: Verify CRDs Are Present

```bash
oc get crd | grep nmstate
```

Expected output includes:
```
nodenetworkconfigurationenactments.nmstate.io
nodenetworkconfigurationpolicies.nmstate.io
nodenetworkstates.nmstate.io
```

## Step 6: Verify Console Plugin Is Registered

The NMState operator automatically registers `nmstate-console-plugin` and adds it to the console. Verify:

```bash
# Check ConsolePlugin resource exists
oc get consoleplugin nmstate-console-plugin

# Verify it is listed in the console operator plugins
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' | tr ',' '\n'
```

Expected: `nmstate-console-plugin` appears in the plugins list.

## Step 7: Verify Console Menu Items

1. Open the OpenShift Console in a browser (get URL with `crc console --url`)
2. Log in as `kubeadmin`
3. Navigate to **Networking** in the left sidebar
4. Confirm the following items are present:
   - **NodeNetworkConfigurationPolicy** — under Networking
   - **NodeNetworkState** — under Networking

> **How it works:** The NMState operator's `nmstate-console-plugin` uses a `console.flag/model` extension that sets `NMSTATE_PLUGIN_ENABLED=true` when the `NodeNetworkState` CRD exists. This flag gates the NNCP and NNS nav items in the console.

## Verification Checklist

- [ ] `oc get csv -n openshift-nmstate` shows `Succeeded`
- [ ] `oc get pods -n openshift-nmstate` shows all pods Running
- [ ] `oc get crd | grep nmstate` shows `nodenetworkconfigurationpolicies` and `nodenetworkstates`
- [ ] `oc get consoleplugin nmstate-console-plugin` returns the resource
- [ ] `nmstate-console-plugin` appears in `consoles.operator.openshift.io/cluster` spec.plugins
- [ ] **NodeNetworkConfigurationPolicy** menu item visible in Console → Networking
- [ ] **NodeNetworkState** menu item visible in Console → Networking

## Persistence After CRC Restart

The NMState operator and its console plugin persist across CRC restarts. After a `crc stop` / `crc start` cycle, allow a few minutes for all pods to reach Running state, then verify the menu items are still present.

## Troubleshooting

**CatalogSource not available:**
```bash
oc get catalogsource -n openshift-marketplace
# Ensure redhat-operators is present and READY
```

**Console plugin not showing menu items after install:**
- Hard refresh the browser (Ctrl+Shift+R)
- Check that `nmstate-console-plugin` is in `spec.plugins`:
  ```bash
  oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'
  ```
- If missing, add it manually:
  ```bash
  oc patch consoles.operator.openshift.io cluster --type=json \
    -p='[{"op":"add","path":"/spec/plugins/-","value":"nmstate-console-plugin"}]'
  ```

**Pods stuck Pending:**
```bash
oc describe pod -n openshift-nmstate <pod-name>
# Check for resource constraints or image pull errors
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 19:22 | v1.0 — Initial skill |
