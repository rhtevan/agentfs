---
name: skupper-model-provider
description: >
  Expose a remote LLM model runtime to the local host through a
  Skupper V2 Virtual Application Network (VAN). The remote interior/hub
  site runs a containerized model (via local-model-ctl) and the local
  edge site exposes an OpenAI-compatible API endpoint on localhost:8000.
  Fully idempotent — 'skupper model up' brings everything up,
  'skupper model down' tears everything down.
argument-hint: "'skupper model up', 'skupper model down', 'skupper model status', 'skupper model test'"
compatibility: >
  Requires Skupper V2 CLI + skrouterd on both hosts, SSH access
  to remote host, Podman + NVIDIA GPU on remote host for model
  runtime (see local-model-ctl skill)
metadata:
  author: agentfs
  version: "1.2.0"
  tags: [skupper, model-serving, van, service-mesh, llm, inference, remote-gpu, granite]
  signals:
    - "skupper model up"
    - "skupper model down"
    - "skupper model status"
    - "skupper model test"
    - "skupper model provider"
    - "expose remote model"
    - "van model"
    - "remote model access"
---

# Skupper Model Provider

Expose a remote LLM model runtime to the local host through a
Skupper V2 Virtual Application Network (VAN) on the Linux/systemd
platform. The remote interior/hub site runs a containerized model
server (IBM Granite via `local-model-ctl`) and the local edge site
exposes an OpenAI-compatible API endpoint at `http://localhost:8000/v1/...`.

## Architecture

```
Localhost (Edge)                         Remote Host (Interior/Hub)
┌────────────────────────────┐  mTLS   ┌────────────────────────────┐
│  Skupper Edge Site         │ ──────→ │  Skupper Interior Site     │
│                            │  Link   │                            │
│  Listener                  │  port   │  Connector                 │
│    routingKey: model-api   │  45671  │    routingKey: model-api   │
│    port: 8000              │         │    port: 8000              │
│                            │         │    host: localhost          │
│  curl localhost:8000 ──────┼────→────┼──→ model container         │
│    /v1/chat/completions    │         │    (g350m/g1b/g8b)         │
└────────────────────────────┘         └────────────────────────────┘
```

## Parameters

| Parameter | Required | Default | Binding Cues | Example |
|-----------|:--------:|---------|-------------|----------|
| `REMOTE_SSH_HOST` | ✅ | — | "remote host", "hub host", "gpu host" | `rhtevan-work` |
| `MODEL_ALIAS` | ❌ | `g350m` | "model", "which model", "use model" | `g8b` |
| `NAMESPACE` | ❌ | `model-provider` | "namespace", "ns" | `model-provider` |
| `LOCAL_SITE_NAME` | ❌ | `edge` | "local site", "edge name" | `edge` |
| `REMOTE_SITE_NAME` | ❌ | `hub` | "remote site", "hub name" | `hub` |

### Agent Binding Rules

1. **Match user input against binding cues** — when the user says
   "skupper model up", bind defaults and prompt only for
   `REMOTE_SSH_HOST` if not resolvable from context or memory.

2. **Model selection** — when the user says "skupper model up" without
   specifying a model, present the available models list and ask for
   selection (default: `g350m`):

   ```
   Available models on <REMOTE_SSH_HOST>:
     [1] g350m — Granite 4.0 350M (FP16, vLLM) — fastest, basic quality
     [2] g1b   — Granite 4.0 1B (INT4, vLLM) — good quality
     [3] g8b   — Granite 4.1 8B (Q4_K_M, llama.cpp) — best quality, 16K ctx

   Select model [1-3] (default: 1/g350m):
   ```

   If a model container doesn't exist on the remote host (never
   deployed via `local-model-ctl`), indicate it:

   ```
     [3] g8b   — Granite 4.1 8B (Q4_K_M, llama.cpp) — ⚠️ not deployed
   ```

3. **Check remote model containers** before presenting the list:

   ```bash
   ssh <REMOTE_SSH_HOST> 'for c in model-g350m model-g1b model-g8b; do
     podman ps -a --filter name=$c --format "$c: {{.Status}}" 2>/dev/null
   done'
   ```

4. **Confirm before executing** — show resolved parameters:

   ```
   Skupper Model Provider — UP
     Remote host:  rhtevan-work
     Model:        g350m (container: model-g350m)
     Namespace:    model-provider
     Local site:   edge
     Remote site:  hub (interior)
     Local API:    http://localhost:8000/v1/...

   Proceed? [y/n]
   ```

5. **For 'skupper model down'** — no model selection needed, tears
   down everything. Confirm:

   ```
   Skupper Model Provider — DOWN
     This will stop: model runtime, Skupper sites, inter-site link
     Remote host: rhtevan-work
     Namespace:   model-provider

   Proceed? [y/n]
   ```

### Script Argument Mapping

| Script | Args |
|--------|------|
| `up.sh` | `$1=NAMESPACE $2=REMOTE_SSH_HOST $3=LOCAL_SITE_NAME $4=REMOTE_SITE_NAME $5=MODEL_ALIAS` |
| `down.sh` | `$1=NAMESPACE $2=REMOTE_SSH_HOST` |
| `test-model.sh` | `$1=MODEL_PORT` (default 8000) |
| `status.sh` | `$1=NAMESPACE $2=REMOTE_SSH_HOST` |

## Invocation Examples

### skupper model up

User: *"skupper model up"*

Agent checks context/memory for `REMOTE_SSH_HOST` (e.g., `rhtevan-work`),
queries available models on remote, presents selection, confirms, then
runs `up.sh`.

### skupper model down

User: *"skupper model down"*

Agent confirms, then runs `down.sh`.

### skupper model status

User: *"skupper model status"*

Agent runs `status.sh` — no confirmation needed.

### skupper model test

User: *"skupper model test"*

Agent runs `test-model.sh` — no confirmation needed.

## Prerequisites

- [ ] `skrouterd` installed natively on **both** hosts
- [ ] `skupper` CLI (v2.x) installed on **both** hosts
- [ ] SSH key-based access from localhost to `REMOTE_SSH_HOST`
- [ ] systemd `--user` support on both hosts
- [ ] Model container deployed on remote host via `local-model-ctl`
      (at least one of: `model-g350m`, `model-g1b`, `model-g8b`)
- [ ] Podman + NVIDIA driver + nvidia-container-toolkit on remote host
- [ ] Firewall port 45671/tcp open on remote host (interior site)

## Operations

### `skupper model up`

Idempotent bring-up. Each phase checks current state before acting:

1. **Verify prerequisites** — skrouterd, skupper CLI, model container
2. **Create sites** — edge on localhost, interior/hub on remote (skip if running)
3. **Firewall check** — warn if 45671/tcp not open (cannot auto-fix, needs sudo)
4. **Link sites** — generate token, apply on edge (skip if ESTAB exists)
5. **Start model** — start the selected model container on remote (skip if running)
6. **Create Connector + Listener** — wire the model through the VAN

### `skupper model down`

Idempotent teardown, reverse order:

1. **Remove Connector + Listener** — unwire the model
2. **Stop model runtime** — stop all model containers on remote
3. **Stop Skupper sites** — both local and remote
4. **Clean up systemd** — reset-failed, daemon-reload

### `skupper model status`

Read-only status check of all components:
- Skupper site services (systemd)
- Inter-site link (TCP ESTAB on 45671)
- Model containers on remote (running/stopped)
- Remote API accessibility (direct)
- Local API accessibility (through VAN)

### `skupper model test`

Verification tests run from localhost through the VAN:
1. **API reachability** — `GET /v1/models` returns HTTP 200
2. **Chat completion** — Send a chat message, verify response
3. **Tool calling** — Send a tool-equipped request, check for function call

## Known Issues

| Issue | Description | Workaround |
|-------|-------------|------------|
| Link status "Pending" | `skupper link status` may report pending even when data flows | Verify with `ss -tnp \| grep 45671 \| grep ESTAB` |
| vLLM startup time | g350m/g1b can take 2-3 minutes to load model weights | `up.sh` polls for up to 5 minutes |
| Port 8000 conflict | If something else uses port 8000 on localhost, listener fails | Stop conflicting service first |
| Firewall needs sudo on remote | Cannot auto-open port 45671 on remote host | Manual on remote: `sudo firewall-cmd --zone=... --add-port=45671/tcp --permanent && sudo firewall-cmd --reload` |
| `skupper system stop` lingering | systemd service may not fully stop | `down.sh` runs `reset-failed` + `daemon-reload` |

## Relationship to Other Skills

| Skill | Relationship |
|-------|--------------|
| `skupper-linux-two-site` | **Replaced by** this skill — this skill includes full site lifecycle management |
| `local-model-ctl` | **Depends on** — model containers must be deployed on remote host first (`model setup <alias> on <host>`) |

## Changelog

| Date | Change |
|------|--------|
| 2026-08-04 | v1.2 — Fixed terminology consistency: local=edge, remote=hub/interior. Updated parameter defaults and binding cues to match. |
| 2026-08-04 | v1.1 — Swapped site roles: localhost=edge (outbound only, no firewall needed), remote=interior/hub (accepts inbound links, stable firewall). Updated all scripts and documentation. |
| 2026-08-04 | v1.0 — Initial skill: idempotent up/down/status/test for Skupper VAN model provider |

## Supporting Files

Skill directory: /home/ezhang/.agents/skills/skupper-model-provider

- scripts/up.sh → /home/ezhang/.agents/skills/skupper-model-provider/scripts/up.sh (load_skill(name: "skupper-model-provider/scripts/up.sh"))
- scripts/down.sh → /home/ezhang/.agents/skills/skupper-model-provider/scripts/down.sh (load_skill(name: "skupper-model-provider/scripts/down.sh"))
- scripts/test-model.sh → /home/ezhang/.agents/skills/skupper-model-provider/scripts/test-model.sh (load_skill(name: "skupper-model-provider/scripts/test-model.sh"))
- scripts/status.sh → /home/ezhang/.agents/skills/skupper-model-provider/scripts/status.sh (load_skill(name: "skupper-model-provider/scripts/status.sh"))
