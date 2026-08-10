---
name: litellm-vertex-ai-proxy
description: "Set up a local LiteLLM proxy for GCP Vertex AI with systemd auto-start and service account credentials"
platforms: [linux]
user-invocable: true
disable-model-invocation: false
metadata:
  version: "3.0.0"
  tags: [litellm, vertex-ai, gcp, proxy, systemd]
  signals: ["litellm vertex", "vertex ai proxy", "setup litellm vertex"]
  related_skills: [litellm-proxy-status, goose-litellm-provider, hermes-litellm-provider]
---

# LiteLLM Proxy for GCP Vertex AI

Set up a local LiteLLM proxy that fronts GCP Vertex AI as an
OpenAI-compatible endpoint, managed by systemd, with proper service
account credentials.

## Overview

This skill deploys LiteLLM locally as a proxy that:
- Exposes `http://127.0.0.1:4000/v1` (OpenAI-compatible)
- Routes requests to GCP Vertex AI (Anthropic Claude models)
- Uses a GCP service account key (no expiring refresh tokens)
- Auto-starts at boot via a systemd user service

Any AI agent or application that supports OpenAI-compatible endpoints
can use this proxy. See agent-specific skills (`goose-litellm-provider`,
`hermes-litellm-provider`) for integration guidance.

## Prerequisites

- Linux with systemd (Fedora, RHEL, Ubuntu, etc.)
- `uv` package manager (`which uv` or install from https://docs.astral.sh/uv/)
- `gcloud` CLI authenticated (`gcloud auth login`)
- A GCP project with Vertex AI API enabled
- A GCP service account key (JSON) with `roles/aiplatform.user` permission
- `python3` with `google-auth` package

## Known Available Models (as of 2026-08-10)

| Model | Region | Context Window |
|---|---|---|
| `claude-opus-4-6` | `us-east5` | 1M tokens |
| `claude-sonnet-4-6` | `us-east5` | 1M tokens |
| `claude-haiku-4-5` | `us-east5` | 200k tokens |

---

## Workflow

### Step 1 — Detect GCP Configuration

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/detect-sa.sh
```

Identifies GCP project, active account, and all service account
key files. Prints metadata (type, email, truncated key ID) — never
exposes private keys.

### Step 2 — Test Service Account Permissions

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/test-sa.sh \
  --sa-key <path_to_key.json> \
  --project <project_id> \
  --region us-east5
```

Sends a minimal Vertex AI request using the SA key. If 403, the
account needs `roles/aiplatform.user` — contact GCP admin.

### Step 3 — Discover Available Models

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/probe-models.sh \
  --project <project_id> --region us-east5
```

Probes known Claude model names against Vertex AI. There is no
listing API — this brute-force probe is the only discovery method.

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
  --region us-east5 \
  --dry-run
```

Review the generated files, then run for real:

```bash
bash ~/.agents/skills/litellm-vertex-ai-proxy/scripts/setup.sh \
  --project <project_id> \
  --sa-key <path_to_key.json> \
  --region us-east5 \
  --force
```

The setup script:
- Discovers available models from live Vertex AI
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
| 1 | **No model listing API** | Vertex AI has no endpoint to list available Anthropic publisher models. `gcloud ai models list`, `GET .../publishers/anthropic/models`, and all v1/v1beta1 variants return 404 or empty. The only discovery method is probing each model name with a `rawPredict` request. Use `scripts/probe-models.sh`. |
| 2 | **`global` region returns 404 on raw API** | Direct API calls to `https://global-aiplatform.googleapis.com/.../:rawPredict` return 404 for all models. However, LiteLLM's internal routing via `vertex_location: global` still works. Use explicit `us-east5` for reliability and consistency. |
| 3 | **Region availability varies by model** | Not all models are available in all regions. `us-central1` returns 400 ("not servable in region"). Always probe with `scripts/probe-models.sh` before adding a model. |
| 4 | **429 ≠ 404** | A 429 response from probing means the model exists but is rate-limited or quota-gated (e.g., `claude-sonnet-5` returned 429). A 404 means the model is genuinely unavailable. |
| 5 | **Context windows differ across model families** | Opus/Sonnet 4.6 have 1M token context; Haiku 4.5 and Sonnet 4.5 have 200k tokens. Downstream consumers (Goose, Hermes) must set `context_limit` correctly per model. |
| 6 | **Service account key, not user ADC** | systemd services cannot re-authenticate interactively. User ADC refresh tokens expire and the proxy silently fails. Always use a service account key file via `GOOGLE_APPLICATION_CREDENTIALS`. |
| 7 | **`setup.sh` discovers all available models** | The probe may find models you've intentionally excluded (e.g., `claude-sonnet-4-5`). After running `setup.sh`, review the generated config and remove unwanted models before restarting. |

---

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | systemd service file exists, is active, and is enabled | `scripts/verify.sh` checks S1a–S1c |
| S2 | Config file exists with models and explicit vertex_location | `scripts/verify.sh` checks S2a–S2c |
| S3 | Service account credentials file exists and is type service_account | `scripts/verify.sh` checks S3a–S3b |
| S4 | Health endpoint responds with all endpoints healthy | `scripts/verify.sh` checks S4a–S4b |
| S5 | /v1/models endpoint returns configured models | `scripts/verify.sh` check S5 |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash scripts/verify.sh 2>&1 \| grep S1` | S1a–S1c show ✅ |
| T2 | S2 | `bash scripts/verify.sh 2>&1 \| grep S2` | S2a–S2c show ✅ |
| T3 | S3 | `bash scripts/verify.sh 2>&1 \| grep S3` | S3a–S3b show ✅ |
| T4 | S4 | `bash scripts/verify.sh 2>&1 \| grep S4` | S4a–S4b show ✅ |
| T5 | S5 | `bash scripts/verify.sh 2>&1 \| grep S5` | S5 shows ✅ |
| T6 | S1–S5 | `bash scripts/verify.sh` | Exit code 0, all checks pass |
| T7 | — | `bash scripts/probe-models.sh --region us-east5` | At least 1 model found |
| T8 | — | `bash scripts/detect-sa.sh` | At least 1 SA key found |
| T9 | — | `bash scripts/test-sa.sh --sa-key <key> --project <proj>` | ✅ Success response |
| T10 | S1–S5 | `bash scripts/setup.sh --dry-run` → diff against live | Generated files match expectations |
| T11 | S1–S5 | Stop proxy → remove config → `bash scripts/setup.sh --force` → `bash scripts/verify.sh` | Full rebuild passes all checks |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Service fails to start | Wrong binary path | Check `which litellm`, re-run `scripts/setup.sh` |
| 403 from Vertex AI | SA missing IAM role | Grant `roles/aiplatform.user` to the service account |
| Credentials expire | Using user ADC instead of SA key | Switch to service account key file |
| Port 4000 in use | Another process | Use `--port` flag with `scripts/setup.sh` |
| Model returns 404 | Model not available in region | Run `scripts/probe-models.sh` to check availability |
| `global` returns 404 | Direct API doesn't support `global` | Use `us-east5` explicitly |
| Unwanted models after setup | `setup.sh` discovers all available | Edit config.yaml, remove unwanted, restart proxy |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-10 16:44 | v3.0.0 — Extracted all inline execution code to scripts: setup.sh (config + systemd + start), detect-sa.sh (GCP detection), test-sa.sh (SA permission test); SKILL.md now contains only script invocations and reference tables; added Gotcha #7 (setup.sh discovers all models); added T8–T11 tests; workflow reduced from 8 steps to 6 |
| 2026-08-10 16:05 | v2.1.0 — Added Gotchas section: no model listing API, global region 404, region availability, 429 vs 404, context window differences, SA key requirement |
| 2026-08-10 15:45 | v2.0.0 — Updated model list (removed sonnet-4-5, added haiku-4-5); documented us-east5 as explicit region; added scripts/verify.sh and scripts/probe-models.sh; added Specification and Tests; fixed frontmatter |
| 2026-07-06 14:37 | v1.1.0 — Made agent-agnostic: removed Hermes-specific config, updated description and troubleshooting |
| 2026-06-19 16:11 | v1.0.0 — Initial skill |
