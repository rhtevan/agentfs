# Known Issues & Workarounds

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `/tmp` not writable (rhel-ai) | podman 4.9.4 rootless uid mapping on bootc | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| Cert files not readable | Files created 640, container runs as uid 10000 | `chmod -R o+r` on certs dir after each `system start` |
| `SSL_PROFILE_BASE_PATH` missing | env var not set on manual container | `-e SSL_PROFILE_BASE_PATH=/etc/skupper-router` |
| No auto-restart on crash | systemd `RemainAfterExit=yes` fire-and-forget | `start-watch.sh` + `Restart=on-failure` + `SuccessExitStatus=SIGTERM` |
| `link generate` returns "no tokens" | CLI bug on podman platform | Build link YAML manually from client certs |
| rhel-ai port 55671 not publicly accessible | AWS security group | Use port 8000 via `ra-rhel-ai` RouterAccess |
| Cert verify failed on link | No SANs on server cert | Add `subjectAlternativeNames` to RouterAccess |
| No CLI to stop controller | By design | `systemctl --user stop skupper-controller.service` |
| Services auto-start on reboot | `skupper system start` creates symlinks + `Linger=yes` | `systemctl --user disable` in unit files (no `[Install]` section) |
| system-controller doesn't restart crashed router | Podman platform limitation | Auto-restart via systemd patch |
| Scoped `down.sh HOST` killed all routes | Local infra is shared; v7.1.0 stopped it unconditionally | v7.2.0: check if other hosts still active before stopping local |
| rhel-ai router survives `systemctl stop` | tmpfs-workaround container created outside systemd lifecycle | v7.2.0: explicit `podman stop` safety net |
| `up.sh` broke auto-restart on rhel-ai | `recreate_router_with_tmpfs()` bypassed systemd | v7.3.0: `systemctl --user start` for ALL hosts; tmpfs is setup-only |
| `systemctl stop` marked service `failed` (exit 143) | bash SIGTERM trap reports 128+15=143 | v7.4.0: `SuccessExitStatus=SIGTERM` in systemd unit |
| CRC operator only supports AllNamespaces | `installModes` has `OwnNamespace: false` | Install in `openshift-operators` |
| CRC secret must be `kubernetes.io/tls` type | kube-adaptor only auto-mounts TLS-type secrets | `oc create secret tls` + patch for `ca.crt` |
| CRC router pod restart after link recreation | kube-adaptor doesn't dynamically mount new secrets | Delete router pod after link recreation |
| CRC TCP precheck fails during fresh setup | Hub routers not up yet during CRC precheck | Downgraded to warning |
| `((var++))` exits with code 1 in bash | `((0++))` is falsy, triggers `set -e` | `\|\| true` on all `((var++))` |
| OLS duplicate volume mount with shared secret | Same `credentialsSecretRef` causes K8s error | Each provider uses a separate secret |
| Local listener unreachable from containers | `host: localhost` binds to 127.0.0.1 only | `LOCAL_LISTENER_HOST="0.0.0.0"` in `topology.env` |
| llama.cpp incompatible with OLS tool-use | llama-server fails parsing `json_schema` | `introspectionEnabled: false` in OLSConfig |
| OLS provider naming for Skupper models | Single name ambiguous with multiple hosts | `skupper-model-rhel` / `skupper-model-rhtevan` convention |
| User services killed on last SSH logout | `Linger=no` tears down user slice on session end | `loginctl enable-linger <user>` (applied in `setup.sh` Phase 5) |
| Orphaned Skupper namespace on localhost | CLI without `-n` creates `default` namespace | `status.sh` scans and flags; clean with `skupper system stop --namespace <name>` |
| Controller ignores `inter-router` role in RouterAccess | v2.2.1 non-kube controller limitation | **Fixed in v2.2.3** — controller now creates inter-router listeners from RouterAccess input |
| Controller ignores `subjectAlternativeNames` | v2.2.1 non-kube controller limitation | **Fixed in v2.2.3** — controller now honors SANs in RouterAccess input |
| Controller overwrites certs/config on restart | By design — reconciles from input resources | Guard in `up.sh`: verify and re-apply after restart |
| `normal` role invalid in RouterAccess input | Controller rejects; only `inter-router` and `edge` valid | Never include `normal` in input resources |
| `skupper system stop` removes entire namespace dir | By design — destructive cleanup | Never use for restart; use `systemctl --user stop/start` |
| CRC link secrets stale after hub cert rotation | `up.sh` only checks `not found`, not `Pending` with stale CA | Compare CA fingerprints; refresh on mismatch |
| Network Observer loses non-k8s sites after router restarts | Observer caches AMQP flow state in memory; router restarts break connections and stale state shows only CRC site | Restart observer pod: `oc delete pod -n model-provider-crc -l app.kubernetes.io/name=network-observer`, then generate traffic |
| Network Observer metrics need traffic to populate | Prometheus has data but UI shows blank until enough flow records are collected | Generate traffic through all VAN paths; allow 30s for Prometheus scrape interval |
| rhel-ai connector status permanently `Not Matched` | tmpfs workaround on rhel-ai (bootc, podman 4.9.4) causes router to not write `ConfigMap-skupper-network-status.yaml`. Without this file, the controller's `NetworkStatusHandler` never re-evaluates connector matching after bootstrap. See [Connector Status Report](#connector-status-not-matched-on-rhel-ai) below. | Verify connectivity directly: `ss -tnp \| grep ESTAB`, `curl localhost:{port}/v1/models`. Do not trust `skupper connector status` on rhel-ai. |

## Connector Status `Not Matched` on rhel-ai

### Summary

`skupper connector status` on rhel-ai permanently reports `Pending / Not Matched / HAS MATCHING LISTENER = false` for all connectors, even though traffic flows correctly through the VAN. This affects **only rhel-ai** — all other sites report correctly.

### Affected Components

- `connector-model-api-rhel-ai` (routing key: `model-api-rhel-ai`, port 9000)
- `connector-decision-api-rhel-ai` (routing key: `decision-api-rhel-ai`, port 9001)

### Root Cause Chain

1. **rhel-ai runs bootc (immutable OS) with podman 4.9.4**, which has a rootless uid mapping bug that makes `/tmp` unwritable inside containers.
2. **`setup.sh` applies a tmpfs workaround**: the router container is recreated with `--tmpfs /tmp:rw,size=10M,mode=1777` outside the normal systemd lifecycle.
3. **The tmpfs-recreated router does not write `ConfigMap-skupper-network-status.yaml`** to `runtime/resources/`. This file contains the aggregated VAN network state (which routing keys have listeners/connectors across all sites).
4. **The controller's `NetworkStatusHandler`** (source: `internal/nonkube/controller/network_status_handler.go`) watches for filesystem changes on this ConfigMap file. When the file is created or updated, it calls `siteState.UpdateStatus(networkStatusInfo)`, which evaluates `HasMatchingPair()` for every connector.
5. **Without the ConfigMap file, `OnUpdate` never fires.** The controller wrote the initial connector status during bootstrap's `resetStatus(true)` — at which point no network status data existed, so all connectors were marked `Not Matched`.
6. **The runtime YAML is never updated again.** The connector status file (`Connector-connector-model-api-rhel-ai.yaml`) has a single write timestamp from bootstrap and is never modified.

### Evidence

| Site | `ConfigMap-skupper-network-status.yaml` | Connector status | Write timestamp |
|------|:---------------------------------------:|:----------------:|:---------------:|
| localhost | ✅ Present | Listeners correct | 12:08 |
| rhtevan-work | ✅ Present | ✅ Ready / Matched | 12:08 |
| rhel-ai | ❌ **Missing** | ❌ Pending / Not Matched | 16:07 (bootstrap only) |

### Why Only rhel-ai?

- **rhtevan-work** runs standard Fedora with podman 5.x — no `/tmp` issue, no tmpfs workaround, router starts normally via systemd and writes the ConfigMap.
- **localhost** runs standard Fedora with podman 5.x — same as rhtevan-work.
- **CRC (K8s)** uses the kube-adaptor which has a completely different reconciliation path via CRD watches.

### Data Plane Impact

**None.** The router routes traffic based on routing keys regardless of what the controller's status YAML says. The `HAS MATCHING LISTENER` field is purely informational — it does not affect routing decisions.

### Verification

Do not rely on `skupper connector status` on rhel-ai. Use direct checks:

```bash
# TCP connections established?
ss -tnp | grep ESTAB | grep skrouterd

# Listener ports open on localhost?
ss -tlnp | grep ':9000\|:10000'

# Model responding?
curl localhost:9000/v1/models
curl localhost:10000/v1/models
```

### Resolution

No fix planned — this is tied to the bootc/podman 4.9.4 platform limitation on rhel-ai. The tmpfs workaround is necessary for the router to run at all. When rhel-ai is upgraded to a newer OS/podman version that resolves the `/tmp` uid mapping issue, the tmpfs workaround can be removed and the ConfigMap should be written normally.

### Related Issues

- Known issue: `/tmp` not writable (rhel-ai) — podman 4.9.4 rootless uid mapping on bootc
- Known issue: rhel-ai router survives `systemctl stop` — tmpfs container created outside systemd
- Known issue: `up.sh` broke auto-restart on rhel-ai — `recreate_router_with_tmpfs()` bypassed systemd (fixed v7.3.0)
- POSTMORTEM Issues 1–3: original tmpfs discovery and workaround
- Upstream: GitHub [#2428](https://github.com/skupperproject/skupper/issues/2428) — related but distinct; that bug was about vanflow purge on K8s, not missing ConfigMap on podman
- Source: `internal/nonkube/controller/network_status_handler.go` — controller watches `ConfigMap-skupper-network-status.yaml` for re-evaluation triggers
- Source: `pkg/nonkube/api/site_state.go:400` — `connector.SetHasMatchingListener(network.HasMatchingPair(...))` evaluation logic
- Source: `internal/network/network.go:264` — `HasMatchingPair()` checks `ListenerCount > 0 && ConnectorCount > 0`
