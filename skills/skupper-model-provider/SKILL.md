---
name: skupper-model-provider
description: >
  Expose remote LLM model runtimes to localhost through a Skupper V2
  Virtual Application Network (VAN). All-interior-mode mesh on Podman
  platform with official skupper-router container. Auto-routes model
  alias to correct remote host and local port.
argument-hint: "bring up skupper model g350m | shutdown skupper model | skupper model status"
compatibility: "skupper CLI 2.2+, podman, SSH access to remote GPU hosts"
writes-files: false
metadata:
  author: agentfs
  version: "5.0.0"
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite, podman, interior-mode, rhel-ai, rhtevan-work]
  signals:
    - "skupper model up"
    - "skupper model down"
    - "skupper model status"
    - "skupper model test"
    - "bring up skupper model"
    - "shutdown skupper model"
    - "expose remote model"
    - "skupper van"
user-invocable: true
disable-model-invocation: false
---

# Skupper Model Provider

Expose remote GPU-hosted LLM models to localhost via a Skupper V2
Virtual Application Network. All operations are implemented as
deterministic scripts.

## Architecture

```
localhost (interior, outbound only)
  ├── inter-router → rhtevan-work:55671 (hub)
  │     Listener :10000 ← model-api-rhtevan-work
  │     Connector → host:10000 (model)
  │
  └── inter-router → rhel-ai:8000 (hub)
        Listener :9000 ← model-api-rhel-ai
        Connector → host:9000 (model)
```

## Model Alias Routing

| Alias | Host | Local Port | Routing Key |
|:-----:|------|:----------:|-------------|
| `g350m` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g1b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g8b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g30b-96k` | rhel-ai | 9000 | `model-api-rhel-ai` |
| `g8b-128k` | rhel-ai | 9000 | `model-api-rhel-ai` |

## Site Configuration

| Site | Mode | Platform | Link Port | Model Port |
|------|------|----------|:---------:|:----------:|
| **localhost** | Interior (outbound) | Podman | — | — |
| **rhtevan-work** | Interior hub | Podman | 55671 | 10000 |
| **rhel-ai** | Interior hub | Podman | 8000 | 9000 |

- **All sites** use `quay.io/skupper/skupper-router:latest` (3.5.2)
- **Namespace:** `model-provider-podman`
- **Local site:** no `linkAccess`, no `edge` — outbound only
- **Port 8000** on localhost is unoccupied

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Bring up Skupper VAN + start model by alias | `scripts/up.sh ALIAS` → localhost:PORT returns HTTP 200 |
| S2 | Shut down model (single or all) + stop routers | `scripts/down.sh [ALIAS\|all]` → ports clear |
| S3 | Show full status (routers, links, listeners, models, e2e) | `scripts/status.sh` → status report |
| S4 | Test model connectivity through VAN (6 checks) | `scripts/test-model.sh ALIAS` → all pass |

## Operations

All operations are implemented as scripts in `scripts/`.

### Bring Up

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh g350m
bash ~/.agents/skills/skupper-model-provider/scripts/up.sh g8b-128k
```

Idempotent 6-phase process:
1. Prerequisites (SSH, skupper CLI, model container)
2. Remote hub site (create if needed, start router)
3. Local interior site (create if needed, add listener)
4. Link (generate token, fix host/name, apply)
5. Start model container
6. Verify local endpoint

### Shut Down

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh g350m    # stop one model
bash ~/.agents/skills/skupper-model-provider/scripts/down.sh all      # stop everything
```

Single alias: stops model container only, routers stay running.
`all`: stops all models + all routers on all sites.

### Status

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh g8b-128k
```

Shows: router status, link connections, listener ports, model
container status, end-to-end HTTP checks.

### Test

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/test-model.sh g350m
```

6 tests: listener port, API health, model ID, chat completion,
remote host reachable, remote container running.

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `up.sh g350m` | localhost:10000 HTTP 200 |
| T2 | S4 | `test-model.sh g350m` | 6/6 pass |
| T3 | S3 | `status.sh` | All components green |
| T4 | S2 | `down.sh g350m` | Model stopped |
| T5 | S1 | `up.sh g8b-128k` | localhost:9000 HTTP 200 |
| T6 | S4 | `test-model.sh g8b-128k` | 6/6 pass |
| T7 | S2 | `down.sh all` | All ports clear |

## Prerequisites

- `skupper` CLI (v2.2+) on localhost
- SSH key-based access to `rhtevan-work` and `rhel-ai`
- Podman on all 3 hosts with `podman.socket` enabled
- `quay.io/skupper/skupper-router:latest` pulled on all hosts
- Model containers deployed via `hosted-model-ctl`
- Port 55671 open on rhtevan-work firewall
- Port 8000 reachable on rhel-ai (AWS security group)

## Podman Container Details

Skupper's auto-created container has `/tmp` permission issues.
All scripts use manual `podman run` with fixes:

```bash
podman run -d \
  --name model-provider-podman-skupper-router \
  --network host \
  --tmpfs /tmp:rw,size=10M,mode=1777 \
  -v ${NS_DIR}/runtime/router:/etc/skupper-router/config:Z \
  -v ${NS_DIR}/runtime/certs:/etc/skupper-router/runtime/certs:Z \
  -e QDROUTERD_CONF=/etc/skupper-router/config/skrouterd.json \
  -e QDROUTERD_CONF_TYPE=json \
  quay.io/skupper/skupper-router:latest
```

### Known Workarounds

| Issue | Fix |
|-------|-----|
| `/tmp` not writable (uid 10000) | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| Certs not readable (640 perms) | `chmod -R o+r` on certs dir |
| `skupper system stop` deletes namespace | Use `podman stop` instead |
| Link token host=0.0.0.0 | Fix to actual hostname in script |
| Link token name collision | Rename to `link-<host>` |
| `tlsCredentials` mismatch | Script auto-fixes |
| Old systemd skrouterd respawns | `systemctl --user mask` |
| CLI status shows Pending | Known bug — use `ss`/`curl` instead |

## Relationship to Other Skills

| Skill | Relationship |
|-------|--------------|
| `hosted-model-ctl` | Deploys model containers that this skill exposes |
| `goose-skupper-provider` | Configures Goose to use the exposed endpoint |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-11 | v5.1 — Fix pipefail crash in status.sh: `grep -c` in pipelines with `set -euo pipefail` aborted script when grep found no matches; replaced `\|\| echo "0"` (which produced `0\n0`) with `\|\| true` |
| 2026-08-08 | v5.0 — Complete rewrite: all scripts rewritten for podman/interior platform; added Specification and Tests; compact SKILL.md; applied skill-check 4 principles |
| 2026-08-08 | v4.0 — All-interior mode; podman platform; official container image; dual routing keys; ports 10000/9000 |
| 2026-08-07 | v3.0 — Two routing keys; rhel-ai edge port 8000 |
| 2026-08-06 | v2.0 — rhel-ai support; model alias routing |
| 2026-08-04 | v1.0 — Initial skill |
