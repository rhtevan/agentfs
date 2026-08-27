---
name: skupper-model-provider
description: >
  setup skupper, teardown skupper, start skupper, stop skupper,
  skupper status, test skupper, precheck skupper, skupper topology,
  start skupper on crc, stop skupper on crc,
  start skupper on rhel-ai, stop skupper on rhtevan-work,
  start skupper with g8b-fp8-spec-128k
argument-hint: "setup skupper | teardown skupper | start skupper | start skupper on crc | stop skupper on crc | stop skupper | skupper status | skupper precheck"
compatibility: "skupper CLI 2.2+, podman, SSH access to remote GPU hosts"
metadata:
  author: agentfs
  version: "8.8.0"
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite, podman, kubernetes, crc, openshift, interior-mode, rhel-ai, rhtevan-work]
user-invocable: true
disable-model-invocation: false
writes-files: false
---

# Skupper Model Provider

Expose remote GPU-hosted LLM models to localhost via a Skupper V2
Virtual Application Network. Separates one-time infrastructure setup
from daily start/stop operations.

## Architecture

**Interactive diagrams:** [VAN Topology](docs/van-topology.architecture.html) · [Operational Lifecycle](docs/operations.lifecycle.html)

```
LOCAL: LOCAL_SITE_NAME (localhost, podman)
  ├── link → hub-rhel-ai
  │     host:  RHEL_AI_PUBLIC_HOST
  │     port:  RHEL_AI_INTER_ROUTER_PORT (AMQPS)
  │     Listener :RHEL_AI_MODEL_PORT ← RHEL_AI_ROUTING_KEY
  │
  └── link → hub-rhtevan-work
        host:  RHTEVAN_WORK_PUBLIC_HOST
        port:  RHTEVAN_WORK_INTER_ROUTER_PORT (AMQPS)
        Listener :RHTEVAN_WORK_MODEL_PORT ← RHTEVAN_WORK_ROUTING_KEY

CRC: CRC_SITE_NAME (kubernetes, CRC_NAMESPACE)
  ├── link → hub-rhel-ai
  │     host:  RHEL_AI_PUBLIC_HOST
  │     port:  RHEL_AI_INTER_ROUTER_PORT (AMQPS)
  │     Listener :CRC_MODEL_PORT ← CRC_ROUTING_KEY
  │     Service: model-listener-rhel-ai.CRC_NAMESPACE:CRC_MODEL_PORT
  │
  └── link → local-ezhang
        host:  host.crc.testing (192.168.127.254)
        port:  LOCAL_INTER_ROUTER_PORT (AMQPS)
        Listener :CRC_RHTEVAN_MODEL_PORT ← RHTEVAN_WORK_ROUTING_KEY
        Service: model-listener-rhtevan-work.CRC_NAMESPACE:CRC_RHTEVAN_MODEL_PORT
```

All site-specific values (IPs, hostnames, ports, SANs) are read from
`topology.env`. Run `setup.sh --check` to see the full topology
diagram with actual values and validate the configuration.

## Host-Based Routing

Skupper routes by host:port. The active model is determined by
`hosted-model-ctl` (profile-based mutual exclusion), not by Skupper.

| Host | Local Port | Routing Key | Default Profile |
|------|:----------:|-------------|:---------------:|
| rhtevan-work | 10000 | `model-api-rhtevan-work` | `g3b-16k` |
| rhel-ai | 9000 | `model-api-rhel-ai` | `g8b-fp8-spec-128k` |

The `test-model.sh` script and `up.sh`/`down.sh` scoped operations
accept either a host name (`rhel-ai`) or a profile name
(`g8b-fp8-spec-128k`) — profile names are resolved to their host.

## Site Configuration

| Site Name | Host | Platform | Mode | Link Port | Model Port |
|-----------|------|----------|------|:---------:|:----------:|
| **LOCAL_SITE_NAME** | localhost | podman | Interior (outbound + inbound) | LOCAL_INTER_ROUTER_PORT | — |
| **hub-rhtevan-work** | RHTEVAN_WORK_SSH_HOST | podman | Interior hub | RHTEVAN_WORK_INTER_ROUTER_PORT | RHTEVAN_WORK_MODEL_PORT |
| **hub-rhel-ai** | RHEL_AI_SSH_HOST | podman | Interior hub | RHEL_AI_INTER_ROUTER_PORT | RHEL_AI_MODEL_PORT |
| **CRC_SITE_NAME** | CRC cluster | kubernetes | Interior (outbound) | — | CRC_MODEL_PORT, CRC_RHTEVAN_MODEL_PORT |

All values in the table above are defined in `topology.env`.

- **Topology config:** `topology.env` (site-specific IPs, hostnames, SANs, CRC config)
- **Shared config:** `scripts/common.sh` (site profiles, aliases, helper functions)
- **Router image:** `quay.io/skupper/skupper-router:3.5.1`
- **Podman namespace:** `model-provider-podman`
- **CRC namespace:** `model-provider-crc`
- **CRC operator:** Red Hat `skupper-operator` v2.2.1 (`stable-2.2` channel, AllNamespaces mode in `openshift-operators`)
- **System controller:** `--reload-type auto` (cert rotation, config reconciliation)

## Script Separation

| Script | Purpose | When to use |
|--------|---------|-------------|
| `setup.sh` | One-time infrastructure | First time, or after teardown |
| `setup.sh --check` | Precheck only (topology + validation) | Before setup, or to inspect topology |
| `teardown.sh` | Remove infrastructure | Decommissioning |
| `up.sh [HOST]` | Start VAN (controllers + routers) | Daily use (`HOST` = `rhel-ai`, `rhtevan-work`, `crc`, or `all`) |
| `down.sh [HOST]` | Stop VAN (routers + controllers) | End of day (`HOST` = `rhel-ai`, `rhtevan-work`, `crc`, or `all`) |
| `status.sh` | Full health check | Troubleshooting |
| `test-model.sh HOST_OR_PROFILE` | E2E connectivity test | Verification |

## Agent Orchestration

This skill manages **Skupper VAN infrastructure only**. Model container
lifecycle is handled by `hosted-model-ctl` — the agent semantically
triggers that skill (loads and follows its instructions), NOT by
cross-referencing or invoking its scripts directly.

### Site Roles

| Role | Sites | What "start" includes |
|------|-------|----------------------|
| **Model Provider** | rhel-ai, rhtevan-work | VAN infra (controller + router) **+** model containers (via `hosted-model-ctl`) |
| **Model Consumer** | localhost, CRC | VAN infra only (controller + router + listeners/links) |

The agent MUST understand this distinction: `hosted-model-ctl` is only
triggered for **Provider** sites that are up and reachable.

### Signal Routing Rules

"Model" is implied — the skill name already establishes context.
Both short (`start skupper`) and long (`start skupper model`) forms
are accepted.

| Signal pattern | Skupper action | hosted-model-ctl delegation |
|----------------|----------------|-----------------------------|
| `setup skupper` | `setup.sh` (infra) | Trigger → `setup.sh` (default profile per host) |
| `teardown skupper` | `teardown.sh` (remove infra) | Trigger → `stop.sh all` (stop, do NOT remove) |
| `start skupper` | `up.sh` (start VAN) | Trigger → `start.sh` (default profile per host) |
| `stop skupper` | `down.sh` (stop VAN) | Trigger → `stop.sh all` |
| `start skupper with PROFILE` | `up.sh HOST` (scoped) | Trigger → `start.sh PROFILE` |
| `check skupper` / `skupper status` | `status.sh` (VAN status) | Trigger → `status.sh` (model status) |
| `stop skupper on PROVIDER` | `down.sh HOST` (scoped) | Trigger → `stop.sh PROFILE` (resolve HOST → active or default profile first; `hosted-model-ctl` takes profile names, not host names) |
| `start skupper on PROVIDER` | `up.sh HOST` (scoped) | Trigger → `start.sh PROFILE` (resolve HOST → active or default profile first; `hosted-model-ctl` takes profile names, not host names) |
| `start skupper on CONSUMER` | `up.sh HOST` (scoped) | None (consumer — VAN only) |
| `stop skupper on CONSUMER` | `down.sh HOST` (scoped) | None (consumer — VAN only) |

The `on HOST` modifier works for **any** site name — provider or
consumer. When the target is a consumer site (`crc`, `localhost`),
only VAN infrastructure is affected; `hosted-model-ctl` is never
triggered.

### Scoping Rules

- **Without `on HOST`** → action applies to ALL sites (providers + consumers)
- **Without `with PROFILE`** → use default profiles from `hosted-model-ctl`
  (`DEFAULT_PROFILE_RHTEVAN` and `DEFAULT_PROFILE_RHELAI` in its `common.sh`)
- **With `on PROVIDER_HOST`** → scope VAN + model to that provider.
  `hosted-model-ctl` scripts take **profile names, not host names** —
  multiple profiles can share the same host (mutual exclusion on port).
  Resolution order: active profile (`get_active_profile`) → default
  profile (`get_default_profile`) → error.
- **With `on CONSUMER_HOST`** (`crc`, `localhost`) → scope VAN only, no model delegation
- **With `with PROFILE`** → resolve profile to its host, scope accordingly

### Error Handling

When any phase fails, the agent MUST:
1. Present the error output and analysis
2. **STOP** — do not proceed to the next phase
3. **WAIT** for user instructions before continuing

### Partial Availability

`up.sh` and `down.sh` handle unreachable hosts gracefully — skipping
them with warnings instead of aborting entirely. The agent MUST follow
this protocol after the scripts complete:

1. Parse `up.sh` / `down.sh` output for `✅ Up` vs `⏭️ Skipped` hosts
2. Classify skipped hosts by role (Provider vs Consumer)
3. For each **UP Provider** host:
   - Trigger `hosted-model-ctl` → start/stop default or requested model
4. For each **SKIPPED Provider** host:
   - Report: `⏭️ <host> skipped (<reason>) — models not started/stopped`
5. For **SKIPPED Consumer** hosts:
   - Report: `⏭️ <host> skipped (<reason>) — no model action needed`
6. **Do NOT ask** "proceed with available hosts?" — partial success is
   the default. The user said "start" or "stop", so act on what's
   available.
7. Present a **combined status report** at the end (VAN + model status
   for all targeted sites, showing up/skipped/down for each).

### Startup Order

1. Skupper controllers (systemd) — Consumer + Provider sites
2. Skupper routers (systemd) — Consumer + Provider sites
3. Model containers (via `hosted-model-ctl`) — **Provider sites only**

### Shutdown Order (reverse)

1. Model containers (via `hosted-model-ctl`) — **Provider sites only**
2. Skupper routers (systemd) — Consumer + Provider sites
3. Skupper controllers (systemd) — Consumer + Provider sites

## Operations

### Precheck / Show Topology

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh --check
```

Displays the VAN topology diagram with actual values from `topology.env`,
then validates: Podman, Skupper CLI, SSH reachability, DNS resolution,
SAN coverage, and local port availability. Use this before setup or
anytime you want to inspect the current topology configuration.

### First-Time Setup

```bash
# 1. Copy and edit topology config
cp ~/.agents/skills/skupper-model-provider/topology.env.example \
   ~/.agents/skills/skupper-model-provider/topology.env
# Edit topology.env with your actual IPs, hostnames, SANs

# 2. Run setup (includes precheck automatically)
bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh
```

Idempotent 6-phase process (after precheck passes):
1. Build hub-rhel-ai (Site, RouterAccess, Connector, tmpfs workaround)
2. Build hub-rhtevan-work (Site, RouterAccess, Connector)
3. Build local site (Site, Listeners)
4. Establish links (manual cert-based, not `link generate`)
5. Apply auto-restart patches (all 3 hosts, router + controller)
6. Verify all sites Ready

After infrastructure setup, agent semantically triggers `hosted-model-ctl`
to deploy default models on each host.

### Start VAN

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh           # all sites
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh rhel-ai   # specific provider host
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh crc       # CRC consumer site only
```

4-phase process (+ Phase 5 for CRC when targeted):
1. Prerequisites (SSH, setup check)
2. Start controllers (systemd)
3. Start routers (systemd — same path for all hosts)
4. Verify VAN connectivity

Agent then semantically triggers `hosted-model-ctl` to start model containers.

### Stop VAN

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh           # all sites
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh rhel-ai   # specific provider host
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh crc       # CRC consumer site only
```

For provider hosts, the agent first semantically triggers
`hosted-model-ctl` to stop model containers, then runs `down.sh`.
For consumer hosts (`crc`), only VAN infrastructure is affected.

### Status

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh
```

Shows dual-column status for each component:
- **Last-Known** — persisted in Skupper's runtime YAML (may be stale)
- **Live** — derived from actual container, systemd, and port checks

Sites show controller + router systemd state with a `(STALE)` flag
when the YAML claims Ready but the infrastructure is actually down.
Links include a TCP probe to the remote inter-router port. Listeners
check whether the local port is actually bound.

Agent then semantically triggers `hosted-model-ctl` for model
container status and presents a **combined status report** with
these sections (all as Markdown tables):

1. **VAN Infrastructure** — all sites with state and detail
2. **CRC Links** — each link with target and status (if CRC enabled)
3. **Localhost Listeners** — each listener with port, status, routing key
4. **CRC Listeners** — each listener with port, status, service endpoint (if CRC enabled)
5. **Model Containers** — each host with active profile, model, speed, status

### Teardown

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/teardown.sh
```

Agent first semantically triggers `hosted-model-ctl` to stop (not remove)
model containers, then runs `teardown.sh` to remove Skupper infrastructure.
Run `setup.sh` to rebuild.

### Test

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/test-model.sh rhtevan-work
```

6 tests: listener port, API health, model ID, chat completion,
remote host reachable, remote container running.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | One-time VAN setup across 3 hosts | `setup.sh` → all sites Ready |
| S2a | Start ALL VAN infrastructure | `up.sh` → all 4 sites up, both listeners active, CRC link connected |
| S2b | Start scoped VAN (one host) | `up.sh HOST` → HOST up, its listener active, other routes unaffected |
| S3a | Stop ALL VAN infrastructure | `down.sh` → all sites down, local stopped, no listeners |
| S3b | Stop scoped VAN (one host, others active) | `down.sh HOST` → HOST down, its listener stopped, other routes **preserved** |
| S3c | Stop scoped VAN (last host) | `down.sh HOST` (no other active) → HOST + local stopped, no listeners |
| S4 | Full status with all components | `status.sh` → comprehensive report |
| S5 | E2E connectivity test | `test-model.sh HOST_OR_PROFILE` → 6/6 pass (requires model via `hosted-model-ctl`) |
| S6 | Teardown infrastructure | `teardown.sh` → all Skupper containers stopped |
| S7a | Auto-restart on crash (normal hosts) | After VAN up → kill router on rhtevan-work → auto-restart within 10s |
| S7b | Auto-restart on crash (tmpfs-workaround hosts) | After VAN up → kill router on rhel-ai → auto-restart within 10s |
| S8 | Agent orchestration with `hosted-model-ctl` | Signal → VAN + model lifecycle coordinated |
| S9a | Partial start — provider unreachable | `up.sh` with one provider down → other provider + consumers up, models on available provider only |
| S9b | Partial start — consumer unreachable | `up.sh` with CRC down → all providers up with models, localhost up, CRC skipped |
| S9c | Partial stop — provider unreachable | `down.sh` with one provider down → stop reachable hosts, report skipped |
| S10a | Start scoped consumer site (CRC) | `up.sh crc` → CRC link recreated, localhost infra started (if needed), no model delegation |
| S10b | Stop scoped consumer site (CRC) | `down.sh crc` → CRC link deleted, localhost kept if providers still active, no model delegation |

## Tests

| Test | Spec | Precondition | Command | Expected |
|:----:|:----:|-------------|---------|----------|
| T1 | S1 | Clean (post-teardown) | `setup.sh` | All 3 sites Ready, both links connected |
| T2a | S2a | All sites down | `up.sh` | All controllers + routers running, both listener ports active |
| T2b | S2b | Only rhtevan-work up | `up.sh rhel-ai` | rhel-ai starts, :9000 listening, :10000 still listening |
| T2c | S2b | Only rhel-ai up | `up.sh rhtevan-work` | rhtevan-work starts, :10000 listening, :9000 still listening |
| T3a | S3a | All sites up | `down.sh` | All routers + controllers stopped, no listeners |
| T3b | S3b | Both hosts up | `down.sh rhel-ai` | rhel-ai down, :9000 stopped, :10000 **still listening** |
| T3c | S3b | Both hosts up | `down.sh rhtevan-work` | rhtevan-work down, :10000 stopped, :9000 **still listening** |
| T3d | S3c | Only rhtevan-work up | `down.sh rhtevan-work` | rhtevan-work + local stopped, no listeners |
| T3e | S3c | Only rhel-ai up | `down.sh rhel-ai` | rhel-ai + local stopped, no listeners |
| T4 | S4 | Any | `status.sh` | All components reported with correct live state |
| T5 | S5 | VAN + model up | `test-model.sh rhtevan-work` | 6/6 pass (model started via `hosted-model-ctl`) |
| T6 | S6 | Any | `teardown.sh` | All Skupper containers stopped on all hosts |
| T7a | S7a | VAN up (rhtevan-work running) | Kill rhtevan-work router, wait 12s | Router auto-restarted, service active |
| T7b | S7b | VAN up (rhel-ai running) | Kill rhel-ai router, wait 12s | Router auto-restarted, service active |
| T8 | S8 | All down | "start skupper model" signal | Agent: `up.sh` → `hosted-model-ctl start.sh` defaults → e2e ✅ |
| T9a | S9a | rhel-ai unreachable, all down | `up.sh` | rhtevan-work + localhost up, models on rhtevan-work only, rhel-ai skipped |
| T9b | S9b | CRC not authenticated, all down | `up.sh` | All providers up + models, localhost up, CRC skipped |
| T9c | S9c | rhtevan-work unreachable, all up | `down.sh` | rhel-ai + localhost stopped, rhtevan-work skipped |
| T10a | S10a | CRC authenticated, providers may be up or down | `up.sh crc` | CRC link recreated, localhost started, no model containers touched |
| T10b | S10b | CRC authenticated, providers still active | `down.sh crc` | CRC link deleted, localhost kept running, no model containers touched |
| T10c | S10b | CRC authenticated, no providers active | `down.sh crc` | CRC link deleted, localhost stopped (last consumer) |

## Known Issues & Workarounds

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `/tmp` not writable (rhel-ai) | podman 4.9.4 rootless uid mapping on bootc | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| Cert files not readable | Files created 640, container runs as uid 10000 | `chmod -R o+r` on certs dir after each `system start` |
| `SSL_PROFILE_BASE_PATH` missing | env var not set on manual container | `-e SSL_PROFILE_BASE_PATH=/etc/skupper-router` |
| No auto-restart on crash | systemd `RemainAfterExit=yes` fire-and-forget | `start-watch.sh` (6-line: `podman start` + `podman wait` + `exit $RC`) + `Restart=on-failure` + `SuccessExitStatus=SIGTERM` (no `[Install]` — services are `disabled` so they don't auto-start on boot; `up.sh` starts them on demand) |
| `link generate` returns "no tokens" | CLI bug on podman platform | Build link YAML manually from client certs |
| rhel-ai port 55671 not publicly accessible | AWS security group | Use port 8000 via `hub-rhel-ai-public` RouterAccess |
| Cert verify failed on link | No SANs on server cert | Add `subjectAlternativeNames` to RouterAccess |
| No CLI to stop controller | By design | `down.sh all` stops via systemctl; manual: `systemctl --user stop skupper-controller.service` |
| Services auto-start on reboot | `skupper system start` creates `default.target.wants/` symlinks + `Linger=yes` | `install_*_auto_restart()` runs `systemctl --user disable` before writing unit files (no `[Install]` section). Survives re-running `setup.sh`. Services stay `static` — `up.sh` starts on demand, `Restart=on-failure` handles crashes |
| system-controller doesn't restart crashed router | Podman platform limitation | Auto-restart via systemd patch |
| Scoped `down.sh HOST` killed all routes | Local router/controller are shared infrastructure serving all links; v7.1.0 `down.sh` unconditionally stopped them even in scoped mode | v7.2.0: scoped mode checks if other remote hosts still have active routers before stopping local infrastructure. Only stops local when it's the last active host. |
| rhel-ai router survives `systemctl stop` | On tmpfs-workaround hosts, `recreate_router_with_tmpfs()` creates the container via `podman run` outside full systemd lifecycle; `systemctl stop` may not reach it | v7.2.0: `down.sh` explicitly runs `podman stop` (NOT `podman rm`) on tmpfs-workaround hosts as a safety net after `systemctl stop` |
| `up.sh` broke auto-restart on rhel-ai | `up.sh` called `recreate_router_with_tmpfs()` every start, which did `podman rm` + `podman run -d` — bypassing systemd entirely. `start-watch.sh` never ran, so no crash detection, no auto-restart, and `systemctl stop` was a no-op. | v7.3.0: `up.sh` uses `systemctl --user start` for ALL hosts (same path). `recreate_router_with_tmpfs()` is setup-only — tmpfs flags are baked into the container at creation and preserved across `podman stop`/`podman start` cycles. |
| `systemctl stop` marked service `failed` (exit 143) | Original `start-watch.sh` used bash SIGTERM trap with `exit 0`, but bash reports signal-based exit code (128+15=143) to systemd regardless of trap exit code. systemd saw non-zero → `Result=exit-code` → `failed` state. | v7.4.0: Simplified `start-watch.sh` to 6 lines (no trap, no stop marker). `podman wait` returns container exit code directly. `SuccessExitStatus=SIGTERM` in systemd unit tells systemd that exit 143 is success. Verified on all 3 hosts: `systemctl stop` → `Result=success`, `ActiveState=inactive`. |
| CRC operator only supports AllNamespaces | skupper-operator v2.2.1 `installModes` has `OwnNamespace: false` | Install in `openshift-operators` (has `global-operators` OperatorGroup). Do NOT create a namespace-scoped OperatorGroup. |
| CRC secret must be `kubernetes.io/tls` type | kube-adaptor only auto-mounts TLS-type secrets into router pod; Opaque secrets are ignored | Use `oc create secret tls` + patch to add `ca.crt` |
| CRC router pod restart after link recreation | kube-adaptor doesn't dynamically mount new TLS secrets into an existing router pod | `up.sh crc` deletes the router pod after recreating the Link; Deployment recreates it with the secret mounted |
| CRC TCP precheck fails during fresh setup | Hub routers aren't up yet when CRC precheck runs (setup creates them in Phase 1-2) | Downgraded to warning — CRC link will connect once hubs are up |
| `((var++))` exits with code 1 in bash | `((0++))` evaluates to 0 (falsy), triggering `set -e` exit | Added `|| true` to all `((var++))` in CRC code paths |
| OLS duplicate volume mount with shared secret | Two OLS providers referencing the same `credentialsSecretRef` cause Kubernetes `Duplicate value` error on volume name and mount path | Each provider MUST use a separate secret, even if contents are identical (e.g., `skupper-model-llmcreds` vs `skupper-model-rhtevan-llmcreds`) |
| llama.cpp incompatible with OLS tool-use | OLS sends `response_format: { type: "json_schema" }` for structured output; llama-server's grammar parser fails with "failed to parse grammar" (400) | Set `introspectionEnabled: false` in OLSConfig to disable MCP tools — basic Q&A works, tool-use does not. vLLM handles structured output correctly. |
| OLS provider naming for Skupper models | Single `skupper-model` name is ambiguous when multiple model hosts exist | Use `skupper-model-rhel` / `skupper-model-rhtevan` convention — provider name encodes the target host |

## Prerequisites

- `skupper` CLI (v2.2+) on localhost
- SSH key-based access to `rhtevan-work` and `rhel-ai`
- Podman on all 3 hosts (4.9+ on rhel-ai, 5.x on others)
- `podman.socket` enabled (`skupper system install --reload-type auto`)
- Model containers deployed via `hosted-model-ctl`
- Port 55671 reachable on rhtevan-work (LAN)
- Port 8000 reachable on rhel-ai (AWS security group)
- **CRC (if enabled):** CRC running with OpenShift 4.x, `oc` CLI configured with context `CRC_OC_CONTEXT`, CRC VM able to reach hub's public host on AMQPS port

## Relationship to Other Skills

| Skill | Relationship | Coupling |
|-------|-------------|----------|
| `hosted-model-ctl` | Manages model container lifecycle (deploy, start, stop, remove) | Agent-level semantic triggering — scripts do NOT cross-reference or invoke each other |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint | Independent |


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
