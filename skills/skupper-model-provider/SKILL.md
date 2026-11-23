---
name: skupper-model-provider
description: >
  setup skupper, teardown skupper, upgrade skupper,
  start skupper, stop skupper, skupper status,
  test skupper, precheck skupper, skupper topology,
  start skupper on SITE, stop skupper on SITE,
  start skupper with PROFILE, stop skupper with PROFILE
argument-hint: "start skupper | stop skupper | start skupper on rhel-ai | upgrade skupper | skupper status"
compatibility: "skupper CLI 2.2+, podman, SSH access to remote GPU hosts, CRC/OpenShift"
metadata:
  author: agentfs
  version: "9.3.1"
  model-tier: T3
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite, podman, kubernetes, crc, openshift, interior-mode, rhel-ai, rhtevan-work]
user-invocable: true
disable-model-invocation: false
writes-files: true
---

# Skupper Model Provider

Expose remote GPU-hosted LLM models to localhost via a Skupper V2
Virtual Application Network. Separates one-time infrastructure setup
from daily start/stop operations. Manages a 4-site VAN across podman
and Kubernetes (CRC) platforms with automated model container
orchestration via `hosted-model-ctl`.

For architecture details, topology, and routing tables, see
[references/architecture.md](references/architecture.md).

For agent orchestration rules (signal routing, scoping, partial
availability, startup/shutdown order), see
[references/agent-orchestration.md](references/agent-orchestration.md).

## Site Switch — `RHEL_AI_ENABLED`

`topology.env` → `RHEL_AI_ENABLED="false"` takes rhel-ai out of every
script: setup (Phase 1, its local listener and link), up, down, status,
teardown, upgrade, precheck, and host/profile validation (`up.sh rhel-ai`
→ "disabled"). The VAN becomes local ↔ rhtevan-work (2-site; 3-site with
CRC). Default `true` (or absent) keeps the original behaviour.

- Re-enable: set `"true"`, fill the `RHEL_AI_*` values, re-run
  `setup.sh` — Phase 1 builds the hub, Phase 3 adds the missing local
  listener (`system reload`), Phase 4 creates the link.
- CRC with rhel-ai disabled: `CRC_LINK_TARGET` must name an enabled hub
  (precheck errors otherwise).
- `RHEL_AI_DECISION_ROUTING_KEY` / `RHEL_AI_DECISION_PORT` are optional;
  the decision connector/listener is created only when both are set.

## Script Separation

| Script | Purpose | When to use |
|--------|---------|-------------|
| `setup.sh` | One-time infrastructure | First time, or after teardown |
| `setup.sh --check` | Precheck only (topology + validation) | Before setup, or to inspect topology |
| `teardown.sh` | Remove infrastructure | Decommissioning |
| `upgrade.sh` | Align podman versions to CRC baseline | After CRC operator upgrade |
| `up.sh [SITE]` | Start VAN (controllers + routers) | Daily use |
| `down.sh [SITE]` | Stop VAN (routers + controllers) | End of day |
| `status.sh` | Full health check | Troubleshooting |
| `test-model.sh SITE_OR_PROFILE` | E2E connectivity test | Verification |

## Workflow

The agent MUST select the appropriate operation based on the user's
request and run the corresponding script. The agent MUST report
the script output verbatim.

### Step 1 — Precheck

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh --check`

### Step 2 — Setup

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh`

### Step 3 — Upgrade

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/upgrade.sh`

### Step 4 — Start

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/up.sh [SITE]`

### Step 5 — Stop

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/down.sh [SITE]`

### Step 6 — Status

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/status.sh`

### Step 7 — Teardown

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/teardown.sh`

### Step 8 — Test

The agent MUST run: `bash ~/.agents/skills/skupper-model-provider/scripts/test-model.sh [SITE]`

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `setup.sh` | ✅ | Safe to retry. Checks existing state before each phase. |
| `teardown.sh` | ✅ | Safe to retry. Skips missing resources. |
| `upgrade.sh` | ✅ | Safe to retry. Verifies versions before/after. |
| `up.sh` | ✅ | Safe to retry. Skips unreachable hosts. |
| `down.sh` | ✅ | Safe to retry. Skips unreachable hosts. |
| `status.sh` | ✅ (read-only) | Never modifies state. |
| `test-model.sh` | ✅ (read-only) | Never modifies state. |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| CRC link `Pending` | Stale CA cert in link secret | Compare CA fingerprints, refresh secret, restart pod |
| `SSL certificate verify failed` | Server cert missing SANs | Regenerate cert with proper SANs |
| `Connection refused` on :55672 | No inter-router listener | Inject listener into `skrouterd.json`, restart router |
| Observer shows suffixed site names | Podman platform limitation (v2.2.1) | Upgrade to v2.2.3 |
| Version mismatch across sites | Podman sites not aligned with CRC | Run `upgrade.sh` |

For detailed troubleshooting procedures, see
[references/troubleshooting.md](references/troubleshooting.md).

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | One-time VAN setup across 4 sites | `setup.sh` → all sites Ready |
| S2a | Start ALL VAN infrastructure | `up.sh` → all sites up, all listeners active |
| S2b | Start scoped VAN (one site) | `up.sh SITE` → SITE up, other routes unaffected |
| S3a | Stop ALL VAN infrastructure | `down.sh` → all sites down |
| S3b | Stop scoped VAN (one site, others active) | `down.sh SITE` → SITE down, other routes preserved |
| S3c | Stop scoped VAN (last site) | `down.sh SITE` → SITE + local stopped |
| S4 | Full status with all components | `status.sh` → comprehensive report |
| S5 | E2E connectivity test | `test-model.sh` → 6/6 pass |
| S6 | Teardown infrastructure | `teardown.sh` → all Skupper containers stopped |
| S7a | Auto-restart on crash (normal hosts) | Kill router → auto-restart within 10s |
| S7b | Auto-restart on crash (tmpfs hosts) | Kill router → auto-restart within 10s |
| S8 | Agent orchestration with `hosted-model-ctl` | Signal → VAN + model lifecycle coordinated |
| S9a | Partial start — provider unreachable | Available providers up, unreachable skipped |
| S9b | Partial start — consumer unreachable | All providers up, unreachable consumer skipped |
| S9c | Partial stop — provider unreachable | Reachable hosts stopped, unreachable skipped |
| S10a | Start scoped consumer site | `up.sh crc` → CRC link recreated, no model delegation |
| S10b | Stop scoped consumer site | `down.sh crc` → CRC link deleted |
| S11a | Start localhost independently | `up.sh localhost` → local started, links reconverge |
| S11b | Stop localhost independently | `down.sh localhost` → local stopped, remotes untouched |
| S12 | Upgrade podman sites to CRC baseline | `upgrade.sh` → all versions aligned |
| S13 | Disable rhel-ai site | `RHEL_AI_ENABLED=false` → precheck/up/down/status/teardown/upgrade skip rhel-ai; `up.sh rhel-ai` → disabled |

## Tests

| Test | Spec | Precondition | Command | Expected |
|:----:|:----:|-------------|---------|----------|
| T1 | S1 | Clean (post-teardown) | `setup.sh` | All sites Ready, all links connected |
| T2a | S2a | All sites down | `up.sh` | All sites up, all listeners active |
| T2b | S2b | Only rhtevan-work up | `up.sh rhel-ai` | rhel-ai starts, :9000 listening |
| T3a | S3a | All sites up | `down.sh` | All stopped, no listeners |
| T3b | S3b | Both providers up | `down.sh rhel-ai` | rhel-ai down, :10000 preserved |
| T3d | S3c | Only rhtevan-work up | `down.sh rhtevan-work` | All stopped |
| T4 | S4 | Any | `status.sh` | All components reported correctly |
| T5 | S5 | VAN + model up | `test-model.sh rhtevan-work` | 6/6 pass |
| T6 | S6 | Any | `teardown.sh` | All Skupper containers stopped |
| T7a | S7a | VAN up | Kill rhtevan-work router, wait 12s | Auto-restarted |
| T8 | S8 | All down | "start skupper" signal | VAN + models up, e2e pass |
| T9a | S9a | rhel-ai unreachable | `up.sh` | rhtevan-work up, rhel-ai skipped |
| T10a | S10a | CRC authenticated | `up.sh crc` | CRC links recreated |
| T11b | S11a | Local down, providers up | `up.sh localhost` | Local started, links reconverge |
| T12 | S12 | Version mismatch | `upgrade.sh` | All versions match CRC baseline |
| T13 | S13 | `RHEL_AI_ENABLED=false` | `setup.sh --check`; `up.sh --list-sites`; `up.sh rhel-ai` | 2-site tree, no rhel-ai checks; `rhtevan-work`; "disabled" error |

## Gotchas

- **Never use `skupper system stop`** for restart — it deletes the entire namespace directory including input resources. Use `systemctl --user stop/start` instead.
- **Never include `normal` role** in RouterAccess input — controller rejects it. Only `inter-router` and `edge` are valid.
- **Models are NOT stopped** during Skupper upgrade — they run independently as podman containers.
- **CRC operator upgrades** happen through OLM, not through `upgrade.sh`. The upgrade script only aligns podman sites.
- **Router image is versioned separately** — skupper 2.2.3 and 2.2.4 both pin `skupper-router:3.5.3`. `upgrade.sh` reads the pinned tag from the release's `internal/images/images.go` (offline: `SKUPPER_ROUTER_TAG=<tag>`).
- **Rebuild an existing podman namespace with `system reload`, not `system start`** — `start` refuses ("namespace already exists"). `system install --reload-type auto` recreates a removed controller container. Reload keeps `runtime/issuers` (CA), so links and the CRC secret stay valid.
- **Restart the router before the controller.** A controller whose router restarts under it can stop publishing flow records: the CRC site drops that hub and its listener shows `No matching connectors`. Fix: `systemctl --user restart skupper-controller.service` on the hub. `oc rollout restart` of the CRC controller is reverted by OLM.
- **`CRC_LINK_TARGET` drives the CRC link name and cert** (`link-<crc-site>-<target>`, client cert from the local link to the same hub). With rhel-ai disabled also set `CRC_ROUTING_KEY` to the target hub's key.

For the full known issues table, see
[references/known-issues.md](references/known-issues.md).

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Prerequisites

- `skupper` CLI (v2.2+) on localhost — `setup.sh` Phase 0a installs
  `SKUPPER_CLI_VERSION` (default 2.2.3) into `~/.local/bin` if missing
  (never upgrades; use `upgrade.sh` to change versions)
- SSH key-based access to rhtevan-work (and rhel-ai when `RHEL_AI_ENABLED=true`)
- Podman on all 3 hosts (4.9+ on rhel-ai, 5.x on others)
- `podman.socket` enabled; the local system controller is installed by
  `setup.sh` Phase 0a (`skupper system install --reload-type auto`) when absent
- Model containers deployed via `hosted-model-ctl`
- Port 55671 reachable on rhtevan-work (LAN)
- Port 8000 reachable on rhel-ai (AWS security group)
- **CRC (if enabled):** CRC running with OpenShift 4.x or 5.0 (verified on 5.0.0, operator 2.2.4-rh-2), `oc` CLI configured with context `CRC_OC_CONTEXT`
- **Operator policy:** OCP sites use the **Red Hat Service Interconnect (RHSI)** operators from the `redhat-operators` catalog only: `skupper-operator` (site/router) and `skupper-netobs-operator` (Network Observer), channel `stable-2.2`. Do NOT use the community `skupper-operator` package of the same name. Podman sites use the upstream community images (`quay.io/skupper/*`) and the GitHub CLI by design; versions are aligned to the RHSI operator by `upgrade.sh`.

## Network Observer (CRC)

Web console for the whole VAN (sites, links, services, traffic flows) from the RHSI Network Observer operator.

- Enable: `topology.env` → `CRC_OBSERVER_ENABLED="true"`, then `setup.sh` (Phase 6 subscribes `skupper-netobs-operator` and creates `NetworkObserver skupper-network-observer` in `CRC_NAMESPACE`).
- URL: `https://skupper-network-observer-<CRC_NAMESPACE>.apps-crc.testing` (Route, reencrypt). `status.sh` prints it.
- Login: OpenShift OAuth (oauth-proxy sidecar) — any cluster user, e.g. `kubeadmin`. An unauthenticated request returns HTTP 403 with the "Log in with OpenShift" page; that is expected.
- It collects flow records through the CRC router, so it shows the podman sites too (verified: local-ezhang, rhtevan-work, crc-ezhang).

## Relationship to Other Skills

| Skill | Relationship | Coupling |
|-------|-------------|----------|
| `hosted-model-ctl` | Manages model container lifecycle | Agent-level semantic triggering |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint | Independent |

## References

- [Naming Convention](references/naming-convention.md) — resource naming rules for all Skupper components
- [Architecture](references/architecture.md) — VAN topology, site config, routing tables, link naming
- [Agent Orchestration](references/agent-orchestration.md) — signal routing, scoping rules, partial availability, startup/shutdown order
- [Known Issues](references/known-issues.md) — full workarounds table
- [Troubleshooting](references/troubleshooting.md) — debugging procedures, cert chain verification
- [Postmortem](POSTMORTEM.md) — incident history

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
