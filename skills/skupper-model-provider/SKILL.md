---
name: skupper-model-provider
description: >
  Expose remote LLM model runtimes to localhost through a Skupper V2
  Virtual Application Network (VAN). All-interior-mode mesh on Podman
  platform with official skupper-router container. Auto-routes model
  alias to correct remote host and local port.
argument-hint: "bring up skupper model g350m | shutdown skupper model | skupper model status | skupper model precheck | show skupper topology"
compatibility: "skupper CLI 2.2+, podman, SSH access to remote GPU hosts"
writes-files: false
metadata:
  author: agentfs
  version: "6.1.1"
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite, podman, interior-mode, rhel-ai, rhtevan-work]
  signals:
    - "skupper model up"
    - "skupper model down"
    - "skupper model status"
    - "skupper model test"
    - "skupper model setup"
    - "skupper model teardown"
    - "bring up skupper model"
    - "shutdown skupper model"
    - "expose remote model"
    - "skupper van"
    - "skupper model precheck"
    - "skupper model topology"
    - "show skupper topology"
user-invocable: true
disable-model-invocation: false
---

# Skupper Model Provider

Expose remote GPU-hosted LLM models to localhost via a Skupper V2
Virtual Application Network. Separates one-time infrastructure setup
from daily start/stop operations.

## Architecture

```
LOCAL: LOCAL_SITE_NAME (localhost)
  ├── link → hub-rhel-ai
  │     host:  RHEL_AI_PUBLIC_HOST
  │     port:  RHEL_AI_INTER_ROUTER_PORT (AMQPS)
  │     Listener :RHEL_AI_MODEL_PORT ← RHEL_AI_ROUTING_KEY
  │
  └── link → hub-rhtevan-work
        host:  RHTEVAN_WORK_PUBLIC_HOST
        port:  RHTEVAN_WORK_INTER_ROUTER_PORT (AMQPS)
        Listener :RHTEVAN_WORK_MODEL_PORT ← RHTEVAN_WORK_ROUTING_KEY
```

All site-specific values (IPs, hostnames, ports, SANs) are read from
`topology.env`. Run `setup.sh --check` to see the full topology
diagram with actual values and validate the configuration.

## Model Alias Routing

| Alias | Host | Local Port | Routing Key |
|:-----:|------|:----------:|-------------|
| `g350m` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g1b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g8b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g30b-96k` | rhel-ai | 9000 | `model-api-rhel-ai` |
| `g8b-128k` | rhel-ai | 9000 | `model-api-rhel-ai` |

## Site Configuration

| Site Name | Host | Mode | Link Port | Model Port |
|-----------|------|------|:---------:|:----------:|
| **LOCAL_SITE_NAME** | localhost | Interior (outbound) | — | — |
| **hub-rhtevan-work** | RHTEVAN_WORK_SSH_HOST | Interior hub | RHTEVAN_WORK_INTER_ROUTER_PORT | RHTEVAN_WORK_MODEL_PORT |
| **hub-rhel-ai** | RHEL_AI_SSH_HOST | Interior hub | RHEL_AI_INTER_ROUTER_PORT | RHEL_AI_MODEL_PORT |

All values in the table above are defined in `topology.env`.

- **Topology config:** `topology.env` (site-specific IPs, hostnames, SANs)
- **Shared config:** `scripts/common.sh` (site profiles, aliases, helper functions)
- **Router image:** `quay.io/skupper/skupper-router:3.5.1`
- **Namespace:** `model-provider-podman`
- **System controller:** `--reload-type auto` (cert rotation, config reconciliation)

## Script Separation

| Script | Purpose | When to use |
|--------|---------|-------------|
| `setup.sh` | One-time infrastructure | First time, or after teardown |
| `setup.sh --check` | Precheck only (topology + validation) | Before setup, or to inspect topology |
| `teardown.sh` | Remove infrastructure | Decommissioning |
| `up.sh ALIAS` | Start model + ensure VAN running | Daily use |
| `down.sh ALIAS` | Stop one model | Daily use |
| `down.sh all` | Stop all models, routers + controllers | End of day |
| `status.sh` | Full health check | Troubleshooting |
| `test-model.sh ALIAS` | E2E connectivity test | Verification |

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

### Bring Up a Model

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh g350m
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh g8b-128k
```

5-phase process:
1. Prerequisites (SSH, setup check)
2. Start controllers (systemd)
3. Start routers (systemd, with tmpfs workaround for rhel-ai)
4. Start model container
5. Verify local endpoint

### Shut Down

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh g350m     # stop one model
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh all        # stop all models, routers + controllers
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh all --keep-van  # stop models only
```

### Status

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh
```

Shows: controllers, routers (with mode), sites, links, listeners,
connectors, model containers, end-to-end HTTP, systemd services.

### Teardown

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/teardown.sh
```

Stops all sites and controllers on all hosts. Does NOT remove model
containers. Run `setup.sh` to rebuild.

### Test

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/test-model.sh g350m
```

6 tests: listener port, API health, model ID, chat completion,
remote host reachable, remote container running.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | One-time VAN setup across 3 hosts | `setup.sh` → all sites Ready |
| S2 | Start model + VAN by alias | `up.sh ALIAS` → localhost:PORT HTTP 200 |
| S3 | Stop model (single or all) | `down.sh ALIAS\|all` → container stopped |
| S4 | Full status with all components | `status.sh` → comprehensive report |
| S5 | E2E connectivity test | `test-model.sh ALIAS` → 6/6 pass |
| S6 | Teardown infrastructure | `teardown.sh` → all containers stopped |
| S7 | Auto-restart on crash | Kill router → systemd restarts within 10s |

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `setup.sh` | All 3 sites Ready, both links connected |
| T2 | S2 | `up.sh g350m` | localhost:10000 HTTP 200, model=granite-4.0-350m |
| T3 | S3 | `down.sh g350m` | Container stopped, VAN still running |
| T4 | S4 | `status.sh` | All components green, e2e connectivity ✅ |
| T5 | S5 | `test-model.sh g350m` | 6/6 pass |
| T6 | S6 | `teardown.sh` | All containers stopped on all hosts |
| T7 | S7 | `podman kill router; sleep 12` | Router auto-restarted, service active |

## Known Issues & Workarounds

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `/tmp` not writable (rhel-ai) | podman 4.9.4 rootless uid mapping on bootc | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| Cert files not readable | Files created 640, container runs as uid 10000 | `chmod -R o+r` on certs dir after each `system start` |
| `SSL_PROFILE_BASE_PATH` missing | env var not set on manual container | `-e SSL_PROFILE_BASE_PATH=/etc/skupper-router` |
| No auto-restart on crash | systemd `RemainAfterExit=yes` fire-and-forget | `start-watch.sh` + `Restart=on-failure` |
| `link generate` returns "no tokens" | CLI bug on podman platform | Build link YAML manually from client certs |
| rhel-ai port 55671 not publicly accessible | AWS security group | Use port 8000 via `hub-rhel-ai-public` RouterAccess |
| Cert verify failed on link | No SANs on server cert | Add `subjectAlternativeNames` to RouterAccess |
| No CLI to stop controller | By design | `down.sh all` stops via systemctl; manual: `systemctl --user stop skupper-controller.service` |
| system-controller doesn't restart crashed router | Podman platform limitation | Auto-restart via systemd patch |

## Prerequisites

- `skupper` CLI (v2.2+) on localhost
- SSH key-based access to `rhtevan-work` and `rhel-ai`
- Podman on all 3 hosts (4.9+ on rhel-ai, 5.x on others)
- `podman.socket` enabled (`skupper system install --reload-type auto`)
- Model containers deployed via `hosted-model-ctl`
- Port 55671 reachable on rhtevan-work (LAN)
- Port 8000 reachable on rhel-ai (AWS security group)

## Relationship to Other Skills

| Skill | Relationship |
|-------|-------------|
| `hosted-model-ctl` | Deploys model containers that this skill exposes |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-11 | v6.1.1 — `down.sh all` now stops controllers on all 3 hosts (previously left running). No reason to keep controllers alive when all routers are down. |
| 2026-08-11 | v6.1.0 — Extracted site-specific config to `topology.env` (gitignored). Added `topology.env.example` with placeholder values. Added precheck capability (`setup.sh --check`) with topology display and validation. Signals: `skupper model precheck`, `skupper model topology`, `show skupper topology`. Scripts no longer contain hardcoded IPs, hostnames, or usernames. |
| 2026-08-11 | v6.0.1 — Added Tests section (T1–T7) mapped to Specification (S1–S7) per skill-check P4 |
| 2026-08-11 | v6.0 — Complete refactor: separated setup.sh/teardown.sh (one-time) from up.sh/down.sh (daily). Added auto-restart patches for router + controller. Unique site names (hub-rhel-ai, hub-rhtevan-work, local-site). Manual link building (CLI `link generate` broken on podman). SANs on all RouterAccess certs. Comprehensive status.sh with controllers, systemd, e2e. |
| 2026-08-11 | v5.1 — Fix pipefail crash in status.sh |
| 2026-08-08 | v5.0 — Complete rewrite for podman/interior platform |
| 2026-08-08 | v4.0 — All-interior mode; podman platform |
| 2026-08-07 | v3.0 — Two routing keys; rhel-ai edge port 8000 |
| 2026-08-06 | v2.0 — rhel-ai support; model alias routing |
| 2026-08-04 | v1.0 — Initial skill |
