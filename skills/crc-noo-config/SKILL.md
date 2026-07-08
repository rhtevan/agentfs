---
name: crc-noo-config
description: Install and configure the Network Observability Operator (NOO) on OpenShift Local (CRC) with demo Loki and all safe eBPF features enabled
---

# Install and Configure Network Observability Operator on CRC

Install the Network Observability Operator on an OpenShift Local (CRC) cluster with demo Loki for full flow log and topology support, and enable all non-Tech-Preview eBPF features.

## Prerequisites

- The CRC cluster is running and you are logged in as `kubeadmin`.
- The cluster must be using **OVN-Kubernetes** as the network plugin (CRC default).
- **No other operators are required.** Loki Operator is NOT needed — this skill uses the built-in demo Loki mode. Cluster Observability Operator is NOT needed.

## Steps

1. **Verify cluster access and network plugin**
   ```bash
   oc whoami
   oc get network.config.openshift.io cluster -o jsonpath='{.status.networkType}'
   ```
   Confirm you are `kubeadmin` and the network type is `OVNKubernetes`.

2. **Create the netobserv namespace**
   ```bash
   oc create namespace netobserv
   ```

3. **Install the Network Observability Operator**
   Create a Subscription in the `openshift-operators` namespace to install from the `redhat-operators` catalog on the `stable` channel:
   ```bash
   cat <<'EOF' | oc apply -f -
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
   ```

4. **Wait for the operator to be ready**
   Wait for the CSV to reach `Succeeded` and the operator pods to start:
   ```bash
   timeout 300 bash -c '
     until oc get csv -n openshift-operators -o wide 2>/dev/null | grep -q "network-observability-operator.*Succeeded"; do
       echo "Waiting for Network Observability Operator CSV to succeed..."
       sleep 15
     done
     echo "CSV succeeded."
   '
   ```
   Then confirm the pods are running:
   ```bash
   oc get pods -n openshift-operators | grep netobserv
   ```
   You should see:
   - `netobserv-controller-manager-*` — Running
   - `netobserv-plugin-static-*` — Running (console plugin)

5. **Create the FlowCollector with demo Loki and all safe features**
   Create the FlowCollector custom resource with:
   - **Demo Loki enabled** (`installDemoLoki: true`) — provides a lightweight Loki instance for flow log storage without needing the Loki Operator or object storage.
   - **Privileged eBPF agent** — required for PacketDrop tracking.
   - **All non-Tech-Preview features enabled**: DNSTracking, PacketDrop, FlowRTT, PacketTranslation, TLSTracking, IPSec.
   ```bash
   cat <<'EOF' | oc apply -f -
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
   ```

6. **Wait for the FlowCollector to become ready**
   ```bash
   timeout 300 bash -c '
     until oc get flowcollector cluster -n netobserv -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].status}" 2>/dev/null | grep -q "True"; do
       echo "Waiting for FlowCollector to become ready..."
       sleep 15
     done
     echo "FlowCollector is ready."
   '
   ```

## Verification

Run all of the following checks to confirm the installation is complete:

- [ ] `oc get csv -n openshift-operators | grep network-observability` shows `Succeeded`
- [ ] `oc get pods -n openshift-operators | grep netobserv` shows controller-manager and plugin-static pods Running
- [ ] `oc get flowcollector cluster -n netobserv -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'` returns `True`
- [ ] `oc get pods -n netobserv` shows flowlogs-pipeline, loki, and console-plugin pods Running
- [ ] `oc get pods -n netobserv-privileged` shows the eBPF agent pod(s) Running
- [ ] `oc get flowcollector cluster -n netobserv -o jsonpath='{.spec.agent.ebpf.features}'` lists all 6 features
- [ ] `oc get flowcollector cluster -n netobserv -o jsonpath='{.spec.loki.monolithic.installDemoLoki}'` returns `true`
- [ ] `oc get consoleplugin` lists `netobserv-plugin`
- [ ] The OpenShift web console shows **Observe → Network Traffic**

## Enabled eBPF Features

| Feature | Description |
|---|---|
| **DNSTracking** | Tracks DNS query/response details in flows |
| **PacketDrop** | Logs packet drops with reasons (requires privileged mode) |
| **FlowRTT** | Extracts TCP round-trip time (sRTT) for latency analysis |
| **PacketTranslation** | Enriches flows with Service NAT translation info |
| **TLSTracking** | Tracks TLS protocol usage in flows |
| **IPSec** | Tracks flows between nodes with IPsec encryption |

## Features NOT Enabled (require Tech Preview feature gate)

The following features are intentionally excluded because they require enabling the `TechPreviewNoUpgrade` feature gate (`OVNObservability`), which is a one-way, non-reversible operation that blocks cluster upgrades:

| Feature | Why excluded |
|---|---|
| **NetworkEvents** | Correlates flows with NetworkPolicy decisions; requires `OVNObservability` feature gate |
| **UDNMapping** | Maps interfaces to User Defined Networks; requires `OVNObservability` feature gate |

To enable these features if desired, you would need to run:
```bash
oc patch --type=merge --patch '{"spec": {"featureSet": "TechPreviewNoUpgrade"}}' featuregate/cluster
```
Then add `NetworkEvents` and/or `UDNMapping` to the FlowCollector features list. **This is not recommended for CRC clusters that may need upgrades.**

## Notes

- **Demo Loki is unsupported for production.** It is a lightweight, single-instance Loki deployment without HA, authentication, or persistent object storage. It is intended for development and demo purposes only.
- **No Loki Operator needed.** The demo Loki is deployed directly by the Network Observability Operator — no Subscription, LokiStack, or object storage bucket is required.
- **No Cluster Observability Operator needed.** COO is a separate, independent operator and is not a prerequisite for Network Observability.
- The console plugin may take a minute to register. If **Observe → Network Traffic** does not appear, refresh the browser.
- The `privileged: true` setting on the eBPF agent is required for PacketDrop to function. Without it, the feature is silently degraded.
- If the cluster has no application traffic, the Network Traffic view may show "No results" with default filters. Click **Clear all filters** to see infrastructure flows.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 20:35 | v1.0 — Initial skill |
