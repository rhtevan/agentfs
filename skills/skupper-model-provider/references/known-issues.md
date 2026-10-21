# Known Issues & Workarounds

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `/tmp` not writable (rhel-ai) | podman 4.9.4 rootless uid mapping on bootc | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| Cert files not readable | Files created 640, container runs as uid 10000 | `chmod -R o+r` on certs dir after each `system start` |
| `SSL_PROFILE_BASE_PATH` missing | env var not set on manual container | `-e SSL_PROFILE_BASE_PATH=/etc/skupper-router` |
| No auto-restart on crash | systemd `RemainAfterExit=yes` fire-and-forget | `start-watch.sh` + `Restart=on-failure` + `SuccessExitStatus=SIGTERM` |
| `link generate` returns "no tokens" | CLI bug on podman platform | Build link YAML manually from client certs |
| rhel-ai port 55671 not publicly accessible | AWS security group | Use port 8000 via `rhel-ai-public` RouterAccess |
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
