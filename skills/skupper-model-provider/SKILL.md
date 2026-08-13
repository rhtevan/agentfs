---
name: skupper-model-provider
description: >
  setup skupper model, teardown skupper model, start skupper model,
  stop skupper model, skupper model status, test skupper model,
  precheck skupper model, skupper model topology
argument-hint: "setup skupper model | teardown skupper model | start skupper model | shutdown skupper model | skupper model status | skupper model precheck"
compatibility: "skupper CLI 2.2+, podman, SSH access to remote GPU hosts"
metadata:
  author: agentfs
  version: "7.4.1"
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite, podman, interior-mode, rhel-ai, rhtevan-work]
user-invocable: true
disable-model-invocation: false
writes-files: false
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
| `up.sh [HOST]` | Start VAN (controllers + routers) | Daily use |
| `down.sh [HOST]` | Stop VAN (routers + controllers) | End of day |
| `status.sh` | Full health check | Troubleshooting |
| `test-model.sh ALIAS` | E2E connectivity test | Verification |

## Agent Orchestration

This skill manages **Skupper VAN infrastructure only**. Model container
lifecycle is handled by `hosted-model-ctl` — the agent semantically
triggers that skill (loads and follows its instructions), NOT by
cross-referencing or invoking its scripts directly.

### Signal Routing Rules

| Signal pattern | Skupper action | hosted-model-ctl delegation |
|----------------|----------------|-----------------------------|
| `setup skupper model [provider]` | `setup.sh` (infra) | Trigger `hosted-model-ctl` → `setup.sh DEFAULT_MODEL` per host |
| `teardown skupper model [provider]` | `teardown.sh` (remove infra) | Trigger `hosted-model-ctl` → `stop.sh all` (stop, do NOT remove) |
| `start skupper model [provider]` | `up.sh` (start VAN) | Trigger `hosted-model-ctl` → `start.sh DEFAULT_MODEL` per host |
| `stop skupper model [provider]` | `down.sh` (stop VAN) | Trigger `hosted-model-ctl` → `stop.sh all` |
| `start skupper model with g8b-128k` | `up.sh rhel-ai` (scoped) | Trigger `hosted-model-ctl` → `start.sh g8b-128k` |
| `check skupper model [provider]` | `status.sh` (VAN status) | Trigger `hosted-model-ctl` → `status.sh` (model status) |
| `stop skupper model on rhtevan-work` | `down.sh rhtevan-work` (scoped) | Trigger `hosted-model-ctl` → stop models on rhtevan-work only |

### Scoping Rules

- **Without `on HOST`** → action applies to ALL hosts (local + all remotes)
- **Without `with MODEL`** → use default models from `hosted-model-ctl`
  (`DEFAULT_MODEL_RHTEVAN` and `DEFAULT_MODEL_RHELAI` in its `common.sh`)
- **With explicit target** → scope to that specific host/model

### Error Handling

When any phase fails, the agent MUST:
1. Present the error output and analysis
2. **STOP** — do not proceed to the next phase
3. **WAIT** for user instructions before continuing

### Startup Order

1. Skupper controllers (systemd)
2. Skupper routers (systemd)
3. Model containers (via `hosted-model-ctl`)

### Shutdown Order (reverse)

1. Model containers (via `hosted-model-ctl`)
2. Skupper routers (systemd)
3. Skupper controllers (systemd)

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
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh           # all hosts
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh rhel-ai   # specific host
```

4-phase process:
1. Prerequisites (SSH, setup check)
2. Start controllers (systemd)
3. Start routers (systemd — same path for all hosts)
4. Verify VAN connectivity

Agent then semantically triggers `hosted-model-ctl` to start model containers.

### Stop VAN

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh           # all hosts
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh rhel-ai   # specific host
```

Agent first semantically triggers `hosted-model-ctl` to stop model
containers, then runs `down.sh` to stop routers and controllers.

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
container status and presents combined results.

### Teardown

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/teardown.sh
```

Agent first semantically triggers `hosted-model-ctl` to stop (not remove)
model containers, then runs `teardown.sh` to remove Skupper infrastructure.
Run `setup.sh` to rebuild.

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
| S2a | Start ALL VAN infrastructure | `up.sh` → all 3 sites up, both listeners active |
| S2b | Start scoped VAN (one host) | `up.sh HOST` → HOST up, its listener active, other routes unaffected |
| S3a | Stop ALL VAN infrastructure | `down.sh` → all sites down, local stopped, no listeners |
| S3b | Stop scoped VAN (one host, others active) | `down.sh HOST` → HOST down, its listener stopped, other routes **preserved** |
| S3c | Stop scoped VAN (last host) | `down.sh HOST` (no other active) → HOST + local stopped, no listeners |
| S4 | Full status with all components | `status.sh` → comprehensive report |
| S5 | E2E connectivity test | `test-model.sh ALIAS` → 6/6 pass (requires model via `hosted-model-ctl`) |
| S6 | Teardown infrastructure | `teardown.sh` → all Skupper containers stopped |
| S7a | Auto-restart on crash (normal hosts) | After VAN up → kill router on rhtevan-work → auto-restart within 10s |
| S7b | Auto-restart on crash (tmpfs-workaround hosts) | After VAN up → kill router on rhel-ai → auto-restart within 10s |
| S8 | Agent orchestration with `hosted-model-ctl` | Signal → VAN + model lifecycle coordinated |

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
| T5 | S5 | VAN + model up | `test-model.sh g350m` | 6/6 pass (model started via `hosted-model-ctl`) |
| T6 | S6 | Any | `teardown.sh` | All Skupper containers stopped on all hosts |
| T7a | S7a | VAN up (rhtevan-work running) | Kill rhtevan-work router, wait 12s | Router auto-restarted, service active |
| T7b | S7b | VAN up (rhel-ai running) | Kill rhel-ai router, wait 12s | Router auto-restarted, service active |
| T8 | S8 | All down | "start skupper model" signal | Agent: `up.sh` → `hosted-model-ctl start.sh` defaults → e2e ✅ |

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
| Services auto-start on reboot | `WantedBy=default.target` + `Linger=yes` | Removed `[Install]` section from unit files; services are `disabled` — `up.sh` starts on demand, `Restart=on-failure` handles crashes |
| system-controller doesn't restart crashed router | Podman platform limitation | Auto-restart via systemd patch |
| Scoped `down.sh HOST` killed all routes | Local router/controller are shared infrastructure serving all links; v7.1.0 `down.sh` unconditionally stopped them even in scoped mode | v7.2.0: scoped mode checks if other remote hosts still have active routers before stopping local infrastructure. Only stops local when it's the last active host. |
| rhel-ai router survives `systemctl stop` | On tmpfs-workaround hosts, `recreate_router_with_tmpfs()` creates the container via `podman run` outside full systemd lifecycle; `systemctl stop` may not reach it | v7.2.0: `down.sh` explicitly runs `podman stop` (NOT `podman rm`) on tmpfs-workaround hosts as a safety net after `systemctl stop` |
| `up.sh` broke auto-restart on rhel-ai | `up.sh` called `recreate_router_with_tmpfs()` every start, which did `podman rm` + `podman run -d` — bypassing systemd entirely. `start-watch.sh` never ran, so no crash detection, no auto-restart, and `systemctl stop` was a no-op. | v7.3.0: `up.sh` uses `systemctl --user start` for ALL hosts (same path). `recreate_router_with_tmpfs()` is setup-only — tmpfs flags are baked into the container at creation and preserved across `podman stop`/`podman start` cycles. |
| `systemctl stop` marked service `failed` (exit 143) | Original `start-watch.sh` used bash SIGTERM trap with `exit 0`, but bash reports signal-based exit code (128+15=143) to systemd regardless of trap exit code. systemd saw non-zero → `Result=exit-code` → `failed` state. | v7.4.0: Simplified `start-watch.sh` to 6 lines (no trap, no stop marker). `podman wait` returns container exit code directly. `SuccessExitStatus=SIGTERM` in systemd unit tells systemd that exit 143 is success. Verified on all 3 hosts: `systemctl stop` → `Result=success`, `ActiveState=inactive`. |

## Prerequisites

- `skupper` CLI (v2.2+) on localhost
- SSH key-based access to `rhtevan-work` and `rhel-ai`
- Podman on all 3 hosts (4.9+ on rhel-ai, 5.x on others)
- `podman.socket` enabled (`skupper system install --reload-type auto`)
- Model containers deployed via `hosted-model-ctl`
- Port 55671 reachable on rhtevan-work (LAN)
- Port 8000 reachable on rhel-ai (AWS security group)

## Relationship to Other Skills

| Skill | Relationship | Coupling |
|-------|-------------|----------|
| `hosted-model-ctl` | Manages model container lifecycle (deploy, start, stop, remove) | Agent-level semantic triggering — scripts do NOT cross-reference or invoke each other |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint | Independent |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-13 12:51 | v7.4.1 — Skill check fixes: `teardown.sh` now removes router `start-watch.sh` (not just controller's); `setup.sh` uses `mktemp`+`chmod 600` for link YAML temp files (was predictable `/tmp/link-hub-*.yaml`); updated POSTMORTEM.md Architecture Decision #4 to reflect v6.1.1 change (controllers now stopped on `down.sh all`); minor comment update in `down.sh` Phase 1. |
| 2026-08-13 | v7.4.0 — Simplified `start-watch.sh` from 20 lines to 6: removed bash SIGTERM trap, stop marker file, and `podman inspect` exit code check. Now uses direct `podman wait` exit code propagation. Added `SuccessExitStatus=SIGTERM` to systemd units. Fixes service marked `failed` (exit 143) after `systemctl stop`. Verified on all 3 hosts: crash → auto-restart ✅, `systemctl stop` → `inactive`/`success` ✅, `down.sh` → all `inactive`/`success` ✅. |
| 2026-08-12 | v7.3.0 — **Bugfix:** `up.sh` no longer calls `recreate_router_with_tmpfs()` on every start. Tmpfs workaround is setup-only — container retains flags across stop/start. All hosts now use identical `systemctl --user start` path, restoring systemd auto-restart (start-watch.sh) on rhel-ai. Split S7→S7a/S7b for normal vs tmpfs-workaround host auto-restart. Added T7a/T7b. Verified: T7b auto-restart on rhel-ai confirmed (kill → restart in ~5s). |
| 2026-08-12 | v7.2.0 — **Bugfix:** Scoped `down.sh HOST` no longer kills other routes. Local router/controller are shared infrastructure; scoped mode now checks if other remote hosts still have active routers before stopping local. Added `up.sh` scoped verification of unaffected routes. Split S2→S2a/S2b, S3→S3a/S3b/S3c with negative assertions. Added tests T2b/T2c/T3b/T3c/T3d/T3e for all scoped scenarios. Added Gotchas for shared-infrastructure incident and rhel-ai router surviving systemctl stop (tmpfs workaround creates container outside systemd lifecycle; explicit `podman stop` safety net added). |
| 2026-08-12 | v7.1.0 — Enhanced `status.sh` with dual-column reporting: Last-Known (persisted YAML) vs Live (actual container/systemd/port checks). Sites show controller+router systemd state with STALE flag when YAML disagrees with reality. Links include TCP probe to remote inter-router port. Listeners check local port binding. Removed redundant systemd section (merged into Sites). |
| 2026-08-12 | v7.0.1 — Clarified loose coupling: agent semantically triggers `hosted-model-ctl` (loads skill, follows instructions) — no cross-script invocation. Stripped model container and e2e sections from `status.sh` (VAN-only). Added `skupper model provider status`/`check skupper model provider` signals. |
| 2026-08-12 | v7.0.0 — **Breaking:** Decoupled model lifecycle from VAN scripts. `up.sh`/`down.sh` now manage Skupper infrastructure only (controllers + routers). Model containers semantically triggered via `hosted-model-ctl` at agent level (DRY + Loose Coupling). Added Agent Orchestration section with signal routing rules, scoping rules (`on HOST`, `with MODEL`), error handling (STOP & WAIT), startup/shutdown ordering. Updated signals for symmetric `verb skupper model` / `skupper model verb` patterns. Removed `--keep-van` flag (no longer needed). Scripts accept optional `[HOST]` arg for scoped operations. Updated Specification (S1–S8) and Tests (T1–T8). |
| 2026-08-12 | v6.1.3 — Fixed `down.sh` Phase 1 container filter: `--filter 'name=model-'` was also matching `model-provider-podman-skupper-router`; added `grep -v skupper-router` to exclude routers from model stop phase. |
| 2026-08-12 | v6.1.2 — Removed `[Install]` / `WantedBy=default.target` from systemd unit templates in `common.sh`; disabled services on all 3 hosts. Prevents auto-start on reboot when `Linger=yes`. `up.sh` starts on demand; `Restart=on-failure` still handles crash recovery. |
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
