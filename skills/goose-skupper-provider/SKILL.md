---
name: goose-skupper-provider
description: >
  Configure Goose to use a Skupper VAN model endpoint as a custom
  provider. Auto-routes model alias to correct local port (10000
  for rhtevan-work, 9000 for rhel-ai). All operations scripted.
argument-hint: "setup goose skupper provider for g8b-128k | recreate skupper provider"
compatibility: "goose CLI or Desktop, skupper-model-provider running"
writes-files: true
metadata:
  author: agentfs
  version: "4.0.0"
  tags: [goose, provider, skupper, van, granite, vllm, custom-provider, rhel-ai, rhtevan-work]
  signals:
    - "goose skupper provider"
    - "setup skupper provider"
    - "setup goose skupper provider for"
    - "remove skupper provider"
    - "teardown skupper provider"
    - "recreate skupper provider"
    - "reset skupper provider"
user-invocable: true
disable-model-invocation: false
---

# Goose Skupper Provider

Configure Goose to use a Skupper VAN model endpoint as a custom
provider named **Skupper**. All operations implemented as scripts.

## Model-to-Port Routing

| Alias | Host | Port | Routing Key |
|:-----:|------|:----:|-------------|
| `g350m` (default) | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g1b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g8b` | rhtevan-work | 10000 | `model-api-rhtevan-work` |
| `g30b-96k` / `g30b` | rhel-ai | 9000 | `model-api-rhel-ai` |
| `g8b-128k` | rhel-ai | 9000 | `model-api-rhel-ai` |

Default: `g350m` → port 10000.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Setup provider for a model alias | `scripts/setup.sh ALIAS` → JSON + config.yaml updated |
| S2 | Teardown provider | `scripts/teardown.sh` → JSON + config.yaml cleaned |
| S3 | Recreate provider (teardown + setup) | `teardown.sh` then `setup.sh ALIAS` |
| S4 | Verify provider configuration | `scripts/test.sh` → 6 checks pass |

## Operations

All operations are implemented as scripts in `scripts/`.

### Setup

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh g350m
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh g8b-128k
```

6-step process: verify endpoint → backup existing → write JSON →
update config.yaml → verify → test chat.

> ⚠️ **The JSON schema is Goose-specific.** The script uses the exact
> template with all 22 required fields. Do NOT write the JSON manually.

### Teardown

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/teardown.sh
```

Backups existing files, removes JSON and config.yaml entry, verifies.

### Recreate

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/teardown.sh
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh g8b-128k
```

Run teardown then setup sequentially. Useful when switching models.

### Test

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/test.sh
```

6 checks: JSON exists, schema valid, model/port correct,
config.yaml matches, endpoint health, chat completion.

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `setup.sh g350m` | JSON + config updated, chat works |
| T2 | S4 | `test.sh` | 6/6 pass |
| T3 | S2 | `teardown.sh` | JSON removed, config cleaned |
| T4 | S4 | `test.sh` | T1 fails (JSON missing) |
| T5 | S3 | `teardown.sh && setup.sh g8b-128k` | Switched to port 9000 |
| T6 | S4 | `test.sh` | 6/6 pass (port 9000) |

## Usage (Agent Binding)

Parse user intent to determine capability:
- "setup", "configure", "for g8b-128k" → run `setup.sh ALIAS`
- "teardown", "remove", "delete" → run `teardown.sh`
- "recreate", "reset", "redo" → run `teardown.sh` then `setup.sh ALIAS`
- No model specified → default `g350m`

For detailed JSON schema reference, see
[PROVIDER.md](./PROVIDER.md).

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-08 | v4.0 — All operations as scripts; added Spec and Tests; `writes-files: true`; applied skill-check 4 principles |
| 2026-08-08 | v3.1 — Schema warning in PROVIDER.md; incident fix |
| 2026-08-08 | v3.0 — Port 10000 for rhtevan-work; routing keys |
| 2026-08-07 | v2.0 — Multi-port; model alias routing |
| 2026-08-06 | v1.2 — Recreate capability |
| 2026-08-04 | v1.0 — Initial skill |
