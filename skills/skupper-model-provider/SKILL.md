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
  version: "9.0.0"
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

## Operations

### Precheck / Show Topology

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh --check
```

### First-Time Setup

```bash
cp ~/.agents/skills/skupper-model-provider/topology.env.example \
   ~/.agents/skills/skupper-model-provider/topology.env
# Edit topology.env with actual IPs, hostnames, SANs
bash ~/.agents/skills/skupper-model-provider/scripts/setup.sh
```

### Upgrade (align podman sites to CRC baseline)

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/upgrade.sh
```

### Start / Stop VAN

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh               # all sites
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh rhel-ai       # specific provider
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh crc           # CRC site only
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh             # all sites
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh rhel-ai     # specific provider
```

### Status

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh
```

Agent runs `hosted-model-ctl list.sh` for model container status and
presents a combined 5-section report (VAN infra, CRC links, localhost
listeners, CRC listeners, model containers).

### Teardown

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/teardown.sh
```

### Test

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/test-model.sh rhtevan-work
```

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

## Gotchas

- **Never use `skupper system stop`** for restart — it deletes the entire namespace directory including input resources. Use `systemctl --user stop/start` instead.
- **Never include `normal` role** in RouterAccess input — controller rejects it. Only `inter-router` and `edge` are valid.
- **Models are NOT stopped** during Skupper upgrade — they run independently as podman containers.
- **CRC operator upgrades** happen through OLM, not through `upgrade.sh`. The upgrade script only aligns podman sites.

For the full known issues table, see
[references/known-issues.md](references/known-issues.md).

## Prerequisites

- `skupper` CLI (v2.2+) on localhost
- SSH key-based access to rhtevan-work and rhel-ai
- Podman on all 3 hosts (4.9+ on rhel-ai, 5.x on others)
- `podman.socket` enabled (`skupper system install --reload-type auto`)
- Model containers deployed via `hosted-model-ctl`
- Port 55671 reachable on rhtevan-work (LAN)
- Port 8000 reachable on rhel-ai (AWS security group)
- **CRC (if enabled):** CRC running with OpenShift 4.x, `oc` CLI configured with context `CRC_OC_CONTEXT`

## Relationship to Other Skills

| Skill | Relationship | Coupling |
|-------|-------------|----------|
| `hosted-model-ctl` | Manages model container lifecycle | Agent-level semantic triggering |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint | Independent |

## References

- [Architecture](references/architecture.md) — VAN topology, site config, routing tables, link naming
- [Agent Orchestration](references/agent-orchestration.md) — signal routing, scoping rules, partial availability, startup/shutdown order
- [Known Issues](references/known-issues.md) — full workarounds table
- [Troubleshooting](references/troubleshooting.md) — debugging procedures, cert chain verification
- [Postmortem](POSTMORTEM.md) — incident history

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
