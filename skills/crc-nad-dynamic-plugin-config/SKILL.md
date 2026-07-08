---
name: crc-nad-dynamic-plugin-config
description: Deploy the pre-built nad-console-plugin from quay.io to OpenShift Local (CRC) using Helm, and verify the plugin loads correctly and the NetworkAttachmentDefinitions menu item appears in the OpenShift Console Networking section.
---

# CRC NAD Console Plugin Deployment

Deploy the `nad-console-plugin` — a pre-built OpenShift Console Dynamic Plugin that sets the `KUBEVIRT_DYNAMIC` flag when the `NetworkAttachmentDefinition` CRD exists, causing the built-in `networking-console-plugin` to show the NAD nav item natively.

## Background

The `networking-console-plugin` (built into OCP 4.21+) already has a full NAD UI (list, create, details) but gates it behind two flags:
- `NET_ATTACH_DEF` — always `true` (hardcoded in networking-console-plugin)
- `KUBEVIRT_DYNAMIC` — normally set by the KubeVirt plugin, absent in CRC

This plugin sets `KUBEVIRT_DYNAMIC=true` via a `console.flag/model` extension (7 lines of JSON, no custom JS code) whenever the `NetworkAttachmentDefinition` CRD is present in the cluster.

## Prerequisites

- CRC cluster is running (`crc status` shows Running)
- `oc` is logged in as `kubeadmin`
- Helm v3 is available — use `/home/ezhang/.local/bin/helm` (v3.21.0)
  - Verify: `/home/ezhang/.local/bin/helm version`
- The `nad-console-plugin` project is at `/home/ezhang/app/playground/nad-console-plugin/`
- Pre-built image: `quay.io/rhtevan/nad-console-plugin:latest`

## Step 1: Verify the NAD CRD Is Present

The plugin only activates its flag when this CRD exists. Confirm it's in the cluster:

```bash
oc get crd network-attachment-definitions.k8s.cni.cncf.io
```

Expected: The CRD is present (it's part of CRC's default Multus CNI setup).

## Step 2: Deploy with Helm

```bash
/home/ezhang/.local/bin/helm upgrade -i nad-console-plugin \
  /home/ezhang/app/playground/nad-console-plugin/charts/openshift-console-plugin \
  -n nad-console-plugin \
  --create-namespace \
  --set plugin.image=quay.io/rhtevan/nad-console-plugin:latest \
  --set plugin.name=nad-console-plugin \
  --set plugin.imagePullPolicy=Always
```

`imagePullPolicy=Always` ensures Kubernetes always pulls the latest image rather than using a cached version.

## Step 3: Verify Pods Are Running

```bash
oc get pods -n nad-console-plugin
```

Expected: At least one pod in `Running` state serving the plugin.

```bash
# Also check the service and route/ingress
oc get svc,consoleplugin -n nad-console-plugin
```

## Step 4: Verify the ConsolePlugin Is Registered

```bash
oc get consoleplugin nad-console-plugin
```

Expected output:
```
NAME                 AGE
nad-console-plugin   ...
```

Check it is enabled in the console operator:

```bash
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}' | tr ',' '\n'
```

Expected: `nad-console-plugin` appears in the list alongside `networking-console-plugin`.

## Step 5: Restart the Console Pod (If Needed)

If the plugin was deployed before or the console has a stale state, force a console pod restart:

```bash
# Trigger console operator reconcile to pick up the new plugin
oc patch consoles.operator.openshift.io cluster --type=merge \
  -p '{"spec":{"logLevel":"Debug"}}'

# Wait for console pods to restart
oc rollout status deployment console -n openshift-console
```

Then restore log level:
```bash
oc patch consoles.operator.openshift.io cluster --type=merge \
  -p '{"spec":{"logLevel":"Normal"}}'
```

## Step 6: Verify the NAD Menu Item in the Console

1. Open the OpenShift Console (`crc console --url`)
2. Log in as `kubeadmin`
3. Hard refresh the browser (Ctrl+Shift+R) to clear any cached plugin state
4. Navigate to **Networking** in the left sidebar
5. Confirm **NetworkAttachmentDefinitions** appears as a menu item

> **Note:** The NAD menu item is rendered by the built-in `networking-console-plugin`, not by this plugin directly. Our plugin only sets the `KUBEVIRT_DYNAMIC` flag that unlocks it.

## Verification Checklist

- [ ] `oc get crd network-attachment-definitions.k8s.cni.cncf.io` — CRD present
- [ ] `oc get pods -n nad-console-plugin` — pod(s) Running
- [ ] `oc get consoleplugin nad-console-plugin` — resource exists
- [ ] `nad-console-plugin` appears in `consoles.operator.openshift.io/cluster` spec.plugins
- [ ] `networking-console-plugin` also appears in spec.plugins (required for the NAD UI)
- [ ] **NetworkAttachmentDefinitions** menu item visible in Console → Networking

## Persistence After CRC Restart

The Helm release and ConsolePlugin resource persist across CRC restarts. After a `crc stop` / `crc start` cycle, wait for the `nad-console-plugin` pod to reach Running state, then verify the menu item is still present.

## Troubleshooting

**Plugin listed but JS never loads / menu item not appearing:**

The most common cause is a callback name mismatch between the SDK and the OCP console version.
The pre-built image already has the fix (`loadPluginEntry` patched in). If you rebuild the image,
ensure the Dockerfile includes:
```dockerfile
sed -i 's/__load_plugin_entry__/loadPluginEntry/g' dist/plugin-entry.*.min.js
```

**Plugin not in spec.plugins after Helm deploy:**

The Helm chart's post-install Job patches the console operator automatically. If it failed:
```bash
oc get jobs -n nad-console-plugin
oc logs job/<patcher-job-name> -n nad-console-plugin
```

Manually add the plugin if needed:
```bash
oc patch consoles.operator.openshift.io cluster --type=json \
  -p='[{"op":"add","path":"/spec/plugins/-","value":"nad-console-plugin"}]'
```

**Browser shows stale "failed" plugin state:**

The browser caches plugin load failures. A hard refresh (Ctrl+Shift+R) is required — a normal refresh is not sufficient. Also ensure the console pod restarted after the plugin was correctly deployed.

**`networking-console-plugin` not present:**

The NAD UI is served by `networking-console-plugin`. Verify it is enabled:
```bash
oc get consoles.operator.openshift.io cluster -o jsonpath='{.spec.plugins}'
```
It should be present by default in OCP 4.21+. If missing, contact cluster admin.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 19:23 | v1.0 — Initial skill |
