---
name: crc-post-setup-config
description: Post-setup configuration for OpenShift Local (CRC) — enables cluster monitoring with disk-safe Prometheus retention, tunes kubelet system-reserved resources to prevent the SystemMemoryExceedsReservation alert, and silences noisy dev-irrelevant alerts
metadata:
  tags: [openshift, crc, monitoring, configuration, alerts]
---

# CRC Post-Setup Configuration

Apply post-setup configuration to an OpenShift Local (CRC) cluster. This skill combines all one-time tuning that must be re-applied after every `crc delete && crc start` cycle.

## What It Configures

| Area | What | Why |
|------|------|-----|
| **Cluster Monitoring** | Enables the monitoring stack with aggressive Prometheus retention (`24h` / `4GB`) | CRC disables monitoring by default; without retention limits Prometheus fills the VM disk |
| **System Reserved Resources** | Overrides kubelet `--system-reserved` to `memory=1Gi, cpu=500m, ephemeral-storage=1Gi` via a MachineConfig | CRC's default reservation (350Mi memory) is too low and triggers the `SystemMemoryExceedsReservation` alert |
| **Alert Silences** | Silences `AlertmanagerReceiversNotConfigured` for 1 year | Expected on a dev cluster with no external notification receivers configured |

## Steps

### Part 1 — Enable Cluster Monitoring

1. **Verify the cluster is reachable**
   ```bash
   oc whoami
   oc cluster-info
   ```

2. **Set the CRC config flag**
   This persists across `crc delete` + `crc start`, so a fresh cluster will also enable monitoring:
   ```bash
   crc config set enable-cluster-monitoring true
   ```

3. **Remove the monitoring overrides from ClusterVersion**
   CRC disables monitoring by adding `unmanaged: true` overrides to the ClusterVersion resource for the `cluster-monitoring-operator` Deployment and the `monitoring` ClusterOperator. Remove **only** these two entries while keeping all other overrides intact.

   - Fetch the current overrides:
     ```bash
     oc get clusterversion version -o jsonpath='{.spec.overrides}' | python3 -m json.tool
     ```
   - Build a new overrides list that excludes the two monitoring entries:
     - `{"kind":"Deployment","name":"cluster-monitoring-operator","namespace":"openshift-monitoring"}`
     - `{"kind":"ClusterOperator","name":"monitoring"}`
   - Patch the ClusterVersion with the filtered list:
     ```bash
     oc patch clusterversion version --type=json \
       -p '[{"op":"replace","path":"/spec/overrides","value": <filtered list> }]'
     ```
   - If the overrides array is already free of monitoring entries, skip this step.

4. **Wait for the openshift-monitoring namespace to become active**
   ```bash
   oc wait --for=jsonpath='{.status.phase}'=Active namespace/openshift-monitoring --timeout=300s
   ```

5. **Apply the cluster-monitoring-config ConfigMap with retention tuning**
   ```bash
   bash <skill-dir>/apply-monitoring-config.sh
   ```
   This applies:
   - `retention: 24h` — keep only 24 hours of metrics (default is 15 days)
   - `retentionSize: "4GB"` — hard cap on TSDB disk usage
   - Reduced CPU/memory requests for Prometheus and Alertmanager to fit CRC

6. **Wait for the monitoring stack to roll out**
   ```bash
   oc rollout status deployment/cluster-monitoring-operator -n openshift-monitoring --timeout=300s
   oc wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus -n openshift-monitoring --timeout=600s
   ```

### Part 2 — Tune Kubelet System-Reserved Resources

7. **Apply the system-reserved override MachineConfig**
   ```bash
   bash <skill-dir>/apply-system-reserved.sh
   ```
   The script creates a MachineConfig (`99-z-crc-system-reserved-override`) that overrides
   `/etc/node-sizing-enabled.env` with higher values. It sorts after CRC's built-in
   `99-node-sizing-for-crc` MC so the override wins during rendering.
   - `SYSTEM_RESERVED_MEMORY=1Gi` (default: 350Mi — too low, triggers alert)
   - `SYSTEM_RESERVED_CPU=500m` (default: 200m)
   - `SYSTEM_RESERVED_ES=1Gi` (default: 350Mi)

   After the next CRC restart (`crc stop && crc start`), the kubelet picks up the new values
   and the `SystemMemoryExceedsReservation` alert will not fire.

### Part 3 — Silence Dev-Irrelevant Alerts

8. **Silence noisy alerts that are expected on a CRC dev cluster**
   ```bash
   bash <skill-dir>/silence-alerts.sh
   ```
   The script:
   - Silences `AlertmanagerReceiversNotConfigured` for 1 year (no receivers needed on a dev cluster)
   - Skips alerts that are already silenced (safe to re-run)
   - To add more alerts to silence, edit the `SILENCES` array in the script

## Verification

- [ ] `crc config view | grep enable-cluster-monitoring` shows `true`
- [ ] `oc get co monitoring` shows `Available=True` and `Degraded=False`
- [ ] `oc get pods -n openshift-monitoring` shows all pods Running/Ready
- [ ] `oc get prometheus k8s -n openshift-monitoring -o jsonpath='{.spec.retention}'` returns `24h`
- [ ] `oc get prometheus k8s -n openshift-monitoring -o jsonpath='{.spec.retentionSize}'` returns `4GB`
- [ ] `SystemMemoryExceedsReservation` alert is `inactive` (after a CRC restart to pick up the new MachineConfig)
- [ ] `AlertmanagerReceiversNotConfigured` alert is silenced:
      Active silence visible via `oc exec -n openshift-monitoring alertmanager-main-0 -c alertmanager -- curl -s 'http://localhost:9093/api/v2/silences'`

## Supporting Files

Skill directory: ~/.agents/skills/crc-post-setup-config

- apply-monitoring-config.sh → load_skill(name: "crc-post-setup-config/apply-monitoring-config.sh")
- apply-system-reserved.sh → load_skill(name: "crc-post-setup-config/apply-system-reserved.sh")
- silence-alerts.sh → load_skill(name: "crc-post-setup-config/silence-alerts.sh")

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 19:41 | v1.0 — Initial skill |
