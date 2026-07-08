---
name: crc-coo-config
description: Install and configure the Cluster Observability Operator (COO) on OpenShift Local (CRC) with Perses dashboards and incident detection enabled
---

# Install and Configure COO on CRC

Install the Red Hat OpenShift Cluster Observability Operator (COO) on an OpenShift Local (CRC) cluster and enable Perses dashboards and incident detection via the monitoring UIPlugin.

## Prerequisites

- The CRC cluster is running and you are logged in as `kubeadmin`.
- **Cluster monitoring must be enabled.** If it is not, use the `crc-cluster-monitoring` skill first — COO and incident detection depend on the monitoring stack being active.

## Steps

1. **Verify cluster monitoring is running**
   Confirm that the monitoring stack is available before proceeding:
   ```bash
   oc get co monitoring
   ```
   The output must show `Available=True` and `Degraded=False`. If the `monitoring` ClusterOperator does not exist or is degraded, stop and enable cluster monitoring first.

2. **Create the COO namespace with the cluster-monitoring label**
   The `openshift.io/cluster-monitoring: "true"` label is required for incident detection to work:
   ```bash
   cat <<'EOF' | oc apply -f -
   apiVersion: v1
   kind: Namespace
   metadata:
     name: openshift-cluster-observability-operator
     labels:
       openshift.io/cluster-monitoring: "true"
   EOF
   ```

3. **Create the OperatorGroup and Subscription**
   Use the supporting script to install COO from the `redhat-operators` catalog:
   ```bash
   bash <skill-dir>/install-coo.sh
   ```

4. **Wait for the COO operator to be ready**
   Wait for the CSV to reach `Succeeded` and the operator pods to start:
   ```bash
   oc wait --for=jsonpath='{.status.phase}'=Succeeded \
     csv -l operators.coreos.com/cluster-observability-operator.openshift-cluster-observability-operator \
     -n openshift-cluster-observability-operator --timeout=300s
   ```
   Then confirm the pods are running:
   ```bash
   oc get pods -n openshift-cluster-observability-operator
   ```
   You should see at least the following pods running:
   - `observability-operator-*`
   - `obo-prometheus-operator-*`
   - `obo-prometheus-operator-admission-webhook-*` (2 replicas)
   - `perses-operator-*`

5. **Create the UIPlugin CR with Perses and incident detection**
   Apply the UIPlugin custom resource to enable both features:
   ```bash
   cat <<'EOF' | oc apply -f -
   apiVersion: observability.openshift.io/v1alpha1
   kind: UIPlugin
   metadata:
     name: monitoring
   spec:
     type: Monitoring
     monitoring:
       perses:
         enabled: true
       clusterHealthAnalyzer:
         enabled: true
   EOF
   ```

6. **Wait for the UIPlugin to reconcile**
   ```bash
   oc wait --for=jsonpath='{.status.conditions[0].reason}'=UIPluginReconciled \
     uiplugin monitoring --timeout=120s
   ```

## Verification

- [ ] `oc get csv -n openshift-cluster-observability-operator` shows the COO CSV in `Succeeded` phase
- [ ] `oc get pods -n openshift-cluster-observability-operator` shows all pods Running (including `perses-operator`, `perses-0`, and `cluster-health-analyzer`)
- [ ] `oc get crd | grep perses` returns all 4 Perses CRDs (`perses`, `persesdashboards`, `persesdatasources`, `persesglobaldatasources`)
- [ ] `oc get uiplugin monitoring -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'` returns `True`
- [ ] `oc get uiplugin monitoring -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}'` returns `False`
- [ ] `oc get consoleplugin` lists `monitoring-console-plugin`
- [ ] The OpenShift web console shows **Observe → Incidents** (may take ~5 minutes for timeline data to appear)
- [ ] The OpenShift web console shows **Observe → Dashboards** for Perses

## Notes

- After the UIPlugin is created, the web console may **reload automatically**. If the new menu items do not appear, refresh the browser.
- Incident detection takes approximately **5 minutes** to begin correlating alerts after enablement. Only alerts firing after enablement are analyzed.
- The Perses Operator is installed automatically with COO. You do not need to install it separately. The UIPlugin CR creates the Perses server instance and registers the console plugin.
- To use Perses dashboards with cluster metrics, you will need to create a **PersesGlobalDatasource** pointing to the platform Thanos Querier.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 18:24 | v1.0 — Initial skill |
