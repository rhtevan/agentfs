---
name: gcp-vertex-models
description: >
  refresh vertex models, vertex model list, vertex default model,
  select vertex credential, vertex credential list
platforms: ['linux']
argument-hint: "[--project P] [--regions global,us-east5] [--family opus|sonnet|haiku]"
compatibility: "python3 with google-auth (system or litellm uv tool); GCP service account key"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T2
  tags: [gcp, vertex-ai, claude, models, discovery, credentials, service-account]
  related_skills: [litellm-vertex-ai-proxy, litellm-proxy-status, goose-litellm-provider, goose-gcp-provider, crc-ols]
user-invocable: true
disable-model-invocation: false
---

# GCP Vertex AI Model Discovery

Find out which Anthropic Claude models a GCP project can call on
Vertex AI, in which region, and which one is the strongest. Vertex AI
has no entitlement-listing API, so the skill calls each candidate
model with a 1-token request and records the HTTP status per region.
The result is cached as JSON. Other skills consume that JSON: the
`litellm-vertex-ai-proxy` setup generates its model list from it, and
goose's native `gcp_vertex_ai` provider uses `vertex default model`
for `providers.gcp_vertex_ai.model` + `GCP_LOCATION`. This skill is
read-only toward every config file — it never writes agent or proxy
configuration.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.2.0 |
| **Trigger** | `hey refresh vertex models` (Command) · `hey vertex model list` · `hey vertex default model` · `hey select vertex credential` · `hey vertex credential list` (Query) |
| **Dependencies** | python3 + google-auth, service-account key, network to `*aiplatform.googleapis.com` |
| **Cache** | Private to this skill. Consumers MUST read it through `models.sh` (`list --json`, `default`, `project`), never by path. Location is overridable with `GCP_VERTEX_MODELS_CACHE`. |
| **Consumers** | `litellm-vertex-ai-proxy` (setup/refresh + `select-sa.sh`), `litellm-proxy-status` (rank), `goose-gcp-provider` (gcp_vertex_ai default), `crc-ols` (install Phase 0: project/location/model/SA key) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Probe every candidate model × region and classify 200/429/404/403 | `scripts/probe-models.sh` exits 0 with ≥1 usable model |
| S2 | Persist the result as JSON matching the Output Contract | `scripts/verify.sh` check S2 |
| S3 | Show the cached model × region table with age warning | `scripts/models.sh list` exits 0 |
| S4 | Report the strongest usable model and its region | `scripts/models.sh default` prints `<model> <region>` that returned 200 |
| S5 | Rank any list of model names deterministically | `scripts/verify.sh` check S5 |
| S6 | Select exactly one dedicated service-account key, rejecting the default compute SA and any non-`service_account` file | `scripts/select-sa.sh` prints one path, exit 0; exit 1 when none or ambiguous |
| S7 | Report every GCP credential on the host without ever printing a private key | `scripts/detect-sa.sh` lists keys; output contains no `private_key` |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1, S2 | `bash scripts/verify.sh --live` | S1–S5 ✅, exit 0 |
| T2 | S3 | `bash scripts/models.sh list` | Table with `Probed:` header and `Usable: N` (N ≥ 1) |
| T3 | S4 | `bash scripts/models.sh default --family sonnet` | One line `claude-sonnet-… <region>` |
| T4 | S5 | `printf 'claude-opus-5\nclaude-fable-5\n' \| bash scripts/models.sh rank` | `claude-opus-5` only |
| T5 | S3 | `GCP_VERTEX_MODELS_CACHE=/nonexistent bash scripts/models.sh list` | Exit 1, "No probe cache" |
| T6 | S6 | `bash scripts/select-sa.sh` | One path to an `adc.json`, exit 0 |
| T7 | S6 | `bash scripts/select-sa.sh --sa-email nosuch@example.com` | Exit 1, no path printed |
| T8 | S7 | `bash scripts/detect-sa.sh \| grep -c private_key` | `0` |
| T9 | S1, S6 | `env -u GOOGLE_APPLICATION_CREDENTIALS bash scripts/probe-models.sh --project <proj> 2>&1 \| grep credential` | Reports a `service_account`, never a silent user-ADC fallback |

## Rules

Do NOT fabricate model names, regions, or availability. Every model
you report MUST come from script output. If the cache is missing or
stale, say so and offer `refresh vertex models` — do not guess.

Do NOT write goose, LiteLLM, Hermes, or DSH configuration from this
skill. Report the result; the consuming skill applies it.

Do NOT describe "strongest" as cheapest or fastest. The ranking is
capability only: family opus > sonnet > haiku, then newest version.

## Prerequisites

- `python3` with `google-auth` (the scripts fall back to the litellm uv tool's python)
- Dedicated service-account key with `roles/aiplatform.user`; pass `--credentials` or set `GOOGLE_APPLICATION_CREDENTIALS`
- Project via `--project`, `ANTHROPIC_VERTEX_PROJECT_ID`, `GCP_PROJECT_ID`, or `gcloud config`

## Workflow

### Step 1 — Route the signal

Match the user's signal in the table below and execute that step. Each
row is a complete dispatch: run the named step, then stop. If the
signal matches no row, say so and list the signals in this table —
do not guess a step.

| Signal | Go to | Runs |
|--------|-------|------|
| `refresh vertex models` | Step 2 | `scripts/probe-models.sh` |
| `vertex model list` | Step 3 | `scripts/models.sh list` |
| `vertex default model` | Step 4 | `scripts/models.sh default` |
| `vertex project` | Step 5 | `scripts/models.sh project` |
| `select vertex credential` | Step 6 | `scripts/select-sa.sh` |
| `vertex credential list` | Step 7 | `scripts/detect-sa.sh` |

### Step 2 — Refresh (Command)

Run the probe. It updates the cache and prints the table.

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/probe-models.sh \
  --project <project_id> --credentials <sa_key.json>
```

Show the table to the user. Add `--regions global,us-east5,europe-west1`
to probe more regions. Add `--models name1,name2` to probe extra names.

### Step 3 — List (Query)

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/models.sh list
```

Show the table and the `Probed:` header. If the output has a ⚠️ age
warning, offer Step 2. Use `--json` when another skill needs the data.

### Step 4 — Default model (Query)

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/models.sh default
```

The first stdout line is `<model> <region>`. Stderr carries the probe
time and the full ranking — show both. Use `--family sonnet` or
`--family haiku` to pick within a family. Use `--region <r>` to pick
only models that returned 200 in that region (goose `GCP_LOCATION`
applies one region to the whole provider).

### Step 5 — GCP project (Query)

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/models.sh project
```

Prints the GCP project recorded by the last probe, one line on stdout,
exit 0. Exit 1 with a refresh hint when no cache exists. Consumers that
need the project (for example `crc-ols` install Phase 0) call this
instead of reading the cache file.

### Step 6 — Select a service-account credential (Query)

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/select-sa.sh [--project P] [--sa-email E]
```

Prints exactly one path to a service-account `adc.json` on stdout,
exit 0. Exit 1 when none match or more than one matches — in that case
show the script's stderr and ask the user which to use. Never pick one
yourself. Default compute service accounts and non-`service_account`
files are rejected by the script.

### Step 7 — List every GCP credential on the host (Query)

```bash
bash ~/.agents/skills/gcp-vertex-models/scripts/detect-sa.sh
```

Read-only report of the active gcloud project, account, region, and
every service-account key file found. Never prints a private key.
Use it when Step 6 reports an ambiguous or empty match.

## Output Contract

**Cache / `probe-models.sh --format json`:**

```json
{"project": "<id>", "regions": ["global", "us-east5"],
 "credential": {"type": "service_account", "identity": "<sa email>"},
 "generated_at": "2026-11-14T00:32:57Z",
 "models": [{"model": "claude-opus-5", "status": "available",
             "region": "global", "regions": {"global": 200, "us-east5": 429}}]}
```

- `status`: `available` · `quota-limited` · `blocked` · `not-offered` · `error`
- `region`: recommended region (`global` preferred; `--prefer regional` to flip) or `null`
- Pass `region` verbatim to LiteLLM `vertex_location` or goose `GCP_LOCATION`

**`models.sh default`:** stdout `<model> <region>`; ranking on stderr.

**`models.sh rank`:** names on stdin → ranked names on stdout (non-Claude/unknown families dropped).

## Error Handling

| Script | Idempotent | Exit codes | On Failure |
|--------|:----------:|------------|------------|
| `probe-models.sh` | ✅ | 0 ok · 1 no usable model · 2 usage · 3 auth failure | 3 → check key path/permissions; 1 → show table, see Troubleshooting |
| `models.sh` | ✅ (read-only) | 0 ok · 1 no cache / no usable model · 2 usage | 1 + "No probe cache" → Step 2 |
| `verify.sh` | ✅ (read-only) | 0 all pass · 1 any fail | Report failing check IDs |

## Gotchas

| # | Issue | Detail |
|:-:|-------|--------|
| 1 | **Catalog ≠ entitlement** | `v1beta1/publishers/anthropic/models` lists names only; listed models can still return 404/403 for the project. The probe uses the catalog as candidates, not as truth. |
| 2 | **Global host has no prefix** | `aiplatform.googleapis.com` for `global`, `<region>-aiplatform.googleapis.com` otherwise. `global-aiplatform…` does not exist. |
| 3 | **429 = exists but quota-limited** | New models are usually 429 in `us-east5` and 200 on `global`. `global` has no data-residency guarantee. |
| 4 | **403 data-sharing** | Some models (e.g. `claude-fable-5-2`) require enabling data sharing for publisher `anthropic`. |
| 5 | **`gcloud auth print-access-token` may fail** | The scripts use the SA key via google-auth instead. |
| 6 | **Probe costs tokens** | ~1 output token per model × region; the list/default queries are free (cache). |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| exit 3 "AUTH FAILED" | Bad/missing key, wrong `GOOGLE_APPLICATION_CREDENTIALS` | Pass `--credentials <sa_key.json>` |
| All models 403 | SA lacks `roles/aiplatform.user` | Grant the role |
| exit 2 "No project" | Project not set | `--project <id>` |
| "No python3 with google-auth" | Missing library | `pip install --user google-auth` or install litellm uv tool |
| ⚠️ cache older than 7 days | Stale cache | `refresh vertex models` |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
