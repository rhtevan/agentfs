---
name: litellm-vertex-ai-proxy
description: >
  setup litellm vertex, vertex ai proxy, litellm vertex,
  refresh litellm models
platforms: ['linux']
metadata:
  version: "3.4.1"
  model-tier: T2
  tags: [litellm, vertex-ai, gcp, proxy, systemd]
  related_skills: [gcp-vertex-models, litellm-proxy-status, goose-litellm-provider, hermes-litellm-provider]
user-invocable: true
disable-model-invocation: false
---

# LiteLLM Proxy for GCP Vertex AI

Set up a local LiteLLM proxy that fronts GCP Vertex AI as an
OpenAI-compatible endpoint, managed by systemd, with proper service
account credentials.

## Overview

This skill deploys LiteLLM locally as a proxy that:
- Exposes `http://127.0.0.1:4000/v1` (OpenAI-compatible) by default
  (use `--host 0.0.0.0` for container/sandbox access)
- Routes requests to GCP Vertex AI (Anthropic Claude models)
- Uses a GCP service account key (no expiring refresh tokens)
- Auto-starts at boot via a systemd user service

Any AI agent or application that supports OpenAI-compatible endpoints
can use this proxy. See agent-specific skills (`goose-litellm-provider`,
`hermes-litellm-provider`) for integration guidance.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Prerequisites

- Linux with systemd (Fedora, RHEL, Ubuntu, etc.)
- `uv` package manager (`which uv` or install from https://docs.astral.sh/uv/)
- `gcloud` CLI (optional; only used for project auto-detection — scripts authenticate with the SA key via `google-auth`)
- A GCP project with Vertex AI API enabled
- A **dedicated** GCP service account key (JSON) with `roles/aiplatform.user` —
  do NOT use the Compute Engine default service account (`*-compute@developer.gserviceaccount.com`),
  which holds `roles/editor` and is over-privileged for Vertex AI workloads
- `python3` with `google-auth` package

## Available Models — Source of Truth

This skill keeps no model table. Model discovery belongs to the
**`gcp-vertex-models`** skill (dependency): `hey vertex model list`,
`hey refresh vertex models`, `hey vertex default model`. `setup.sh` calls
its probe and writes one `model_list` entry per usable model with that
model's `region` as `vertex_location`.

### Does the LiteLLM proxy serve a dynamic model list?

`GET /v1/models` works, but it is **config-driven, not live from Vertex**. It lists
the `model_list` entries (a wildcard `vertex_ai/*` expands LiteLLM's built-in,
version-dependent catalog, which includes models your project cannot call).
Therefore `setup.sh` writes an explicit `model_list` from the probe. Refresh it
with `hey refresh litellm models` (workflow below); clients that fetch `/v1/models`
(e.g. goose custom providers) then pick the change up automatically.

---

## Workflow

### Step 1 — Select Service Account

```bash
SA_KEY=$(bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/select-sa.sh \
  --project <project_id>)
```

Selects the best dedicated SA key file. Rejects the Compute Engine
default service account (`*-compute@developer.gserviceaccount.com`)
automatically — it holds `roles/editor`, which is over-privileged.
Exits non-zero if no suitable key is found or if ambiguous (use
`--sa-email <email>` to disambiguate).

Use `detect-sa.sh` for a human-readable overview of all available keys:

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/detect-sa.sh
```

### Step 2 — Test Service Account Permissions

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/test-sa.sh \
  --sa-key "$SA_KEY" \
  --project <project_id> \
  --region us-east5
```

Sends a minimal Vertex AI request using the SA key. If 403, the
account needs `roles/aiplatform.user` — contact GCP admin.

### Step 3 — Discover Available Models

Load the `gcp-vertex-models` skill and run its refresh step:

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/probe-models.sh \
  --project <project_id> --credentials "$SA_KEY"
```

Show the model × region table to the user. Continue only if it reports
at least one usable model.

### Step 4 — Install LiteLLM

```bash
uv tool install 'litellm[proxy]'
```

### Step 5 — Setup Proxy (Config + systemd + Start)

**Dry run first** (writes to `/tmp/`, doesn't touch live config):

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/setup.sh \
  --project <project_id> \
  --sa-key <path_to_key.json> \
  --dry-run
```

Review the generated files, then run for real:

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/setup.sh \
  --project <project_id> \
  --sa-key <path_to_key.json> \
  --force
```

To bind on all interfaces (required for container/sandbox access):

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/setup.sh \
  --project <project_id> \
  --sa-key <path_to_key.json> \
  --host 0.0.0.0 \
  --force
```

The setup script:
- Runs the `gcp-vertex-models` probe (SA auth, `global` + `us-east5`; `--regions`, `--prefer global|regional`)
- Writes an explicit `model_list` with a per-model `vertex_location` (no wildcard)
- Generates `~/.config/litellm/config.yaml`
- Generates `~/.config/systemd/user/litellm-proxy.service`
- Backs up existing files before overwriting
- Enables linger, reloads systemd, enables and starts the service
- Runs a health check to confirm proxy is up

### Step 6 — Verify

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/verify.sh
```

All 11 checks should pass.

---

## Refresh LiteLLM Models (`hey refresh litellm models`)

Use when Vertex offers new models or the proxy serves stale ones. The
refresh keeps the live bind host, port, and SA key from the systemd unit.

### Refresh Step 1 — Dry run

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/refresh-models.sh
```

- `DRY_RUN_RESULT=CONVERGED` → report "proxy already current". Stop.
- `DRY_RUN_RESULT=PENDING` → show the `-`/`+` model/region changes to the user. Ask for approval.

### Refresh Step 2 — Apply (after approval)

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/refresh-models.sh --apply
```

Backs up and rewrites `config.yaml`, restarts the proxy, and chat-tests every
served model. Exit 1 lists the failing models; the backup path is printed.

### Refresh Step 3 — Downstream

Relay the script's "Downstream" lines. goose `custom_redhat` discovers models
automatically, but its fallback list makes `goose-litellm-provider` verify S4 fail
until `goose-litellm-provider/scripts/restore.sh` runs. Hermes and DSH hold static
lists. Do NOT edit other agents' configs from this skill.

---

## Management

```bash
systemctl --user status litellm-proxy     # check status
systemctl --user restart litellm-proxy    # restart after config changes
systemctl --user stop litellm-proxy       # stop
journalctl --user -u litellm-proxy -f     # follow logs
```

---

## Gotchas

| # | Issue | Detail |
|:-:|-------|--------|
| 1 | **No entitlement listing API** | `GET https://us-central1-aiplatform.googleapis.com/v1beta1/publishers/anthropic/models` lists the publisher *catalog* (names only); some listed models still return 404/403 for your project. Only a `rawPredict` call shows true availability. Use the `gcp-vertex-models` skill. |
| 2 | **`global` host has no region prefix** | The global endpoint is `https://aiplatform.googleapis.com/v1/projects/P/locations/global/...` (NOT `global-aiplatform.googleapis.com`, which does not exist). Newer models (opus-5, sonnet-5-5, haiku-5-5 …) are typically quota-limited (429) in `us-east5` but 200 on `global`, which is what the native `claude` CLI uses (`CLOUD_ML_REGION=global`). `global` gives no regional data-residency guarantee. |
| 3 | **Region availability varies by model** | Not all models are available in all regions. `us-central1` returns 400 ("not servable in region"). Always probe (`gcp-vertex-models`) before adding a model. |
| 4 | **429 ≠ 404** | A 429 response from probing means the model exists but is rate-limited or quota-gated (e.g., `claude-sonnet-5` returns 429 on `us-east5` but 200 on `global`). A 404 means the model is genuinely unavailable. |
| 5 | **Context windows differ across model families** | Opus/Sonnet 4.6 and newer have 1M token context; Haiku 4.5, Sonnet 4.5 and Opus 4.5 have 200k tokens. Downstream consumers (Goose, Hermes) must set `context_limit` correctly per model. |
| 6 | **Service account key, not user ADC** | systemd services cannot re-authenticate interactively. User ADC refresh tokens expire and the proxy silently fails. Always use a service account key file via `GOOGLE_APPLICATION_CREDENTIALS`. |
| 7 | **`setup.sh` discovers all available models** | The probe may find models you've intentionally excluded. Review the generated config (use `--dry-run`) and remove unwanted models before restarting. |
| 8 | **`--host 127.0.0.1` blocks container access** | Default binds to loopback only. Containers (Podman, Docker, OpenShell sandboxes) reach the host via bridge IPs like `host.containers.internal`, which is not `127.0.0.1`. Use `--host 0.0.0.0` when the proxy must be reachable from containers. **The proxy has no `master_key`, so anyone who can reach the port can spend your GCP quota** — restrict via firewall, or set `general_settings.master_key` and give clients the key. |
| 9 | **Wildcard `vertex_ai/*` is misleading** | It exposes LiteLLM's built-in catalog (incl. models your project cannot call → Vertex 404/403 at request time) and varies with the LiteLLM version. Prefer the explicit list that `setup.sh` generates. |
| 10 | **`gcloud auth print-access-token` may fail** | It needs a usable user login for the active gcloud context. All scripts here use the SA key via `google-auth` instead. |

---

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | systemd service file exists, is active, and is enabled | `scripts/verify.sh` checks S1a–S1c |
| S2 | Config file exists with models and explicit vertex_location | `scripts/verify.sh` checks S2a–S2c |
| S3 | Service account credentials file exists and is type service_account | `scripts/verify.sh` checks S3a–S3b |
| S4 | Health endpoint responds with all endpoints healthy | `scripts/verify.sh` checks S4a–S4b |
| S5 | /v1/models endpoint returns configured models | `scripts/verify.sh` check S5 |
| S6 | Refresh detects drift without changing state, applies on request | `scripts/refresh-models.sh` prints `DRY_RUN_RESULT=…`; `--apply` chat-tests every model |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash scripts/verify.sh 2>&1 \| grep S1` | S1a–S1c show ✅ |
| T2 | S2 | `bash scripts/verify.sh 2>&1 \| grep S2` | S2a–S2c show ✅ |
| T3 | S3 | `bash scripts/verify.sh 2>&1 \| grep S3` | S3a–S3b show ✅ |
| T4 | S4 | `bash scripts/verify.sh 2>&1 \| grep S4` | S4a–S4b show ✅ |
| T5 | S5 | `bash scripts/verify.sh 2>&1 \| grep S5` | S5 shows ✅ |
| T6 | S1–S5 | `bash scripts/verify.sh` | Exit code 0, all checks pass |
| T7 | S6 | `bash scripts/refresh-models.sh` | Exit 0; `DRY_RUN_RESULT=CONVERGED` right after setup |
| T8 | — | `bash scripts/detect-sa.sh` | At least 1 SA key found |
| T9 | — | `bash scripts/test-sa.sh --sa-key <key> --project <proj>` | ✅ Success response |
| T10 | S1–S5 | `bash scripts/setup.sh --dry-run` | Ends with `DRY_RUN_RESULT=CONVERGED` or a `-`/`+` model diff + `PENDING` |
| T11 | S1–S5 | Stop proxy → remove config → `bash scripts/setup.sh --force` → `bash scripts/verify.sh` | Full rebuild passes all checks |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Service fails to start | Wrong binary path | Check `which litellm`, re-run `scripts/setup.sh` |
| 403 from Vertex AI | SA missing IAM role | Grant `roles/aiplatform.user` to the service account |
| Credentials expire | Using user ADC instead of SA key | Switch to service account key file |
| Port 4000 in use | Another process | Use `--port` flag with `scripts/setup.sh` |
| Model returns 404 | Model not available in region | `hey refresh litellm models` |
| `global` returns 404 | Wrong host (`global-aiplatform…`) or model not offered | Use host `aiplatform.googleapis.com`; `hey vertex model list` |
| 429 on a model | Regional quota (common in `us-east5` for new models) | Use `global` (`--prefer global`) or request quota |
| Unwanted models after setup | `setup.sh` includes every usable model | Edit config.yaml, remove unwanted, restart proxy |


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.


## Alternative: native goose `gcp_vertex_ai` (no proxy)

goose can call Vertex directly with the same SA key. Use the
`goose-gcp-provider` skill (`hey configure goose gcp`): it sets
`providers.gcp_vertex_ai.model` + `GCP_LOCATION` from `vertex default model`
after a live test. goose's picker for this provider is compiled in, so newer
models are used by name.
