---
name: goose-skupper-provider
description: >
  setup goose skupper provider, teardown skupper provider,
  recreate skupper provider, test skupper provider,
  check skupper provider
argument-hint: "setup goose skupper provider for rhel-ai | recreate skupper provider | test skupper provider"
compatibility: "goose CLI or Desktop, skupper-model-provider running"
metadata:
  author: agentfs
  version: "5.3.0"
  tags: [goose, provider, skupper, van, granite, vllm, custom-provider, rhel-ai, rhtevan-work]
user-invocable: true
disable-model-invocation: false
writes-files: true
---

# Goose Skupper Provider

Configure Goose (CLI and Desktop) to use a remote GPU-hosted LLM
model as a custom provider named **Skupper**. The model is served
through a Skupper V2 Virtual Application Network managed by
`skupper-model-provider`, which exposes remote GPU hosts (rhel-ai,
rhtevan-work) as local endpoints on `localhost:9000` and
`localhost:10000`. Use this skill after the VAN is running
(`skupper model up`) to wire Goose to the self-hosted model
instead of a cloud provider.

## Host-Based Routing

Skupper routes by host:port. The active model is determined by
`hosted-model-ctl` (profile-based mutual exclusion). The setup
script **discovers** the model identity from the live API — no
static alias mapping.

| Host | Port | Default Profile | Routing Key |
|------|:----:|:---------------:|-------------|
| rhel-ai | 9000 | `g8b-fp8-spec-128k` | `model-api-rhel-ai` |
| rhtevan-work | 10000 | `g3b-16k` | `model-api-rhtevan-work` |

The script accepts host names (`rhel-ai`) or profile names
(`g8b-fp8-spec-128k`) — profile names are resolved to their host.
Default target: `rhel-ai`.

## Poison-JSON Safeguard

> ⚠️ **Goose Desktop loads ALL JSON files in
> `~/.config/goose/custom_providers/`. One malformed file breaks
> ALL providers — not just the broken one.**
>
> The `setup.sh` script enforces three layers of defense:
> 1. **Python `json.dumps`** — writes JSON programmatically (never
>    bash heredoc interpolation)
> 2. **Round-trip validation** — parses the output back and checks
>    all 22 required fields before writing to disk
> 3. **Post-write validation** — reads the file from disk and
>    validates independently; restores backup on any failure
>
> **NEVER write this JSON manually.** Always use `setup.sh`.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Setup provider for a host or profile | `scripts/setup.sh HOST_OR_PROFILE` → JSON + config.yaml updated |
| S2 | Teardown provider | `scripts/teardown.sh` → JSON + config.yaml cleaned |
| S3 | Recreate provider (teardown + setup) | `teardown.sh` then `setup.sh HOST_OR_PROFILE` |
| S4 | Verify provider configuration | `scripts/test.sh` → 6 checks pass |
| S5 | API-driven model discovery | `setup.sh` queries `/v1/models` for model ID + context |
| S6 | Poison-JSON prevention | `setup.sh` validates JSON pre- and post-write; restores backup on failure |

## Operations

All operations are implemented as scripts in `scripts/`.

### Setup

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhel-ai
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhtevan-work
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh g8b-fp8-spec-128k
```

7-step process: discover model from API → backup existing → write
JSON (via Python with round-trip validation) → post-write validation
→ update config.yaml → verify → test chat.

> ⚠️ **The JSON schema is Goose-specific.** The script uses the exact
> template with all 22 required fields via `json.dumps`. Do NOT write
> the JSON manually — see [Poison-JSON Safeguard](#poison-json-safeguard).

### Teardown

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/teardown.sh
```

Backups existing files, removes JSON and config.yaml entry, verifies.

### Recreate

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/teardown.sh
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhel-ai
```

Run teardown then setup sequentially. Useful when switching hosts/models.

### Test

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/test.sh
```

6 checks: JSON exists, schema valid, model/port correct,
config.yaml matches, endpoint health, chat completion.

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `setup.sh rhel-ai` | JSON + config updated, chat works |
| T2 | S4 | `test.sh` | 6/6 pass |
| T3 | S2 | `teardown.sh` | JSON removed, config cleaned |
| T4 | S4 | `test.sh` | T1 fails (JSON missing) |
| T5 | S3 | `teardown.sh && setup.sh rhtevan-work` | Switched to port 10000 |
| T6 | S4 | `test.sh` | 6/6 pass (port 10000) |
| T7 | S5 | `setup.sh g8b-fp8-spec-128k` | Profile resolved → rhel-ai, model discovered from API |
| T8 | S6 | `MODEL_ID='"};rm -rf /;{"' PORT=9000 CTX=131072 bash setup.sh --test-inject` | Validation fails, backup restored, no file damage |

## Signal Routing

| Signal Pattern | Action | Script | Precondition |
|----------------|--------|--------|--------------|
| `setup goose skupper provider` | Setup with default host (rhel-ai) | `setup.sh rhel-ai` | VAN up, model serving |
| `setup skupper provider for rhel-ai` | Setup for specific host | `setup.sh rhel-ai` | VAN up, model serving on rhel-ai |
| `setup skupper provider for g8b-fp8-spec-128k` | Setup for specific profile | `setup.sh g8b-fp8-spec-128k` | VAN up, profile active on rhel-ai |
| `setup skupper provider for rhtevan-work` | Setup for rhtevan-work | `setup.sh rhtevan-work` | VAN up, model serving on rhtevan-work |
| `teardown skupper provider` | Remove provider config | `teardown.sh` | Provider exists |
| `remove skupper provider` | Same as teardown | `teardown.sh` | Provider exists |
| `recreate skupper provider` | Switch host/model | `teardown.sh` then `setup.sh` | VAN up, model serving |
| `recreate skupper provider for rhtevan-work` | Switch to specific host | `teardown.sh` then `setup.sh rhtevan-work` | VAN up, model serving on rhtevan-work |
| `test skupper provider` | Verify current config | `test.sh` | Provider configured |
| `check skupper provider` | Same as test | `test.sh` | Provider configured |

### Routing Rules

- **Without target** → default to `rhel-ai` (port 9000)
- **With host name** (`rhel-ai`, `rhtevan-work`) → resolve directly
- **With profile name** (`g8b-fp8-spec-128k`, `g3b-16k`) → resolve to host
- **"recreate"** always runs teardown first, then setup
- **"test" / "check"** run `test.sh` only (no setup/teardown)

For detailed JSON schema reference, see
[PROVIDER.md](./PROVIDER.md).


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
