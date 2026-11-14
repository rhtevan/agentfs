---
name: goose-gcp-provider
description: >
  configure goose gcp, goose gcp provider
platforms: ['linux']
argument-hint: "[--model M | --family opus|sonnet|haiku] [--region R] [--activate]"
compatibility: "goose CLI/Desktop with native gcp_vertex_ai provider; gcp-vertex-models skill"
metadata:
  author: agentfs
  version: "1.0.2"
  model-tier: T2
  tags: [goose, gcp, vertex-ai, provider, configuration]
  related_skills: [gcp-vertex-models, goose-litellm-provider, litellm-vertex-ai-proxy]
user-invocable: true
disable-model-invocation: false
---

# Configure goose Native GCP Vertex AI Provider

Set the default model of goose's built-in `gcp_vertex_ai` provider (CLI
and Desktop) to a model the GCP project can actually call — by default
the strongest one reported by the `gcp-vertex-models` skill — after a
live goose test. goose's model picker for this provider is compiled into
the binary and stops at the 4.6 generation, so newer models never show
up in the list; they work when set by name. This skill writes that name
(and `GCP_LOCATION`) into `~/.config/goose/config.yaml` and checks the
credential plumbing. Use it after `refresh vertex models`, or whenever
the gcp provider is on an outdated or failing model. For the proxy path
(`custom_redhat`, dynamic model list) use `goose-litellm-provider`.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0.2 |
| **Trigger** | `hey configure goose gcp` (Command) · `hey goose gcp provider` (Query) |
| **Dependencies** | `gcp-vertex-models` (model + region), goose CLI, SA key in `GOOGLE_APPLICATION_CREDENTIALS` |
| **Writes** | `~/.config/goose/config.yaml`: `providers.gcp_vertex_ai.model`, `GCP_LOCATION` (+ `active_provider` only with `--activate`) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | goose config has project, location, and gcp model | `scripts/verify.sh` S1a–S1c |
| S2 | SA credentials reach CLI and Desktop | `scripts/verify.sh` S2a–S2b |
| S3 | Configured model returned 200 in the configured region | `scripts/verify.sh` S3 |
| S4 | Set model from `vertex default model` (or `--model`) after a live test, editing only target lines | `scripts/setup.sh --apply` → re-run prints `DRY_RUN_RESULT=CONVERGED` |
| S5 | goose chats on the configured default | `scripts/verify.sh --live` S5 |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S4 | `bash scripts/setup.sh` | `DRY_RUN_RESULT=PENDING` with a change list, or `CONVERGED`; config unchanged |
| T2 | S4 | `GOOSE_CONFIG=<copy> bash scripts/setup.sh --family sonnet --apply` | `✅ goose run … → OK`, copy differs only in `model:` line |
| T3 | S3 | `bash scripts/setup.sh --model claude-opus-4-7 --apply` | Exit 1 "did not return 200"; config unchanged |
| T4 | S2 | `env -u GOOGLE_APPLICATION_CREDENTIALS bash scripts/setup.sh` | Exit 1 credentials message |
| T5 | S1–S5 | `bash scripts/verify.sh --live` | All ✅, exit 0 |

## Rules

Do NOT fabricate model names, regions, or test results. Every value you
report MUST come from script output.

Do NOT edit `config.yaml` by hand or with a YAML re-dump. Use
`scripts/setup.sh`, which changes only the target lines and keeps a backup.

Do NOT pass `--activate` unless the user asks to make GCP the active
provider. Setting the default model and switching providers are separate.

## Prerequisites

- `gcp-vertex-models` skill with a recent probe (`hey vertex model list`; refresh if stale)
- `GOOGLE_APPLICATION_CREDENTIALS=<SA key>` exported in the shell that runs goose CLI
- Goose Desktop: the same variable on the `Exec=env …` line of `~/.local/share/applications/Goose.desktop`
- `GCP_PROJECT_ID` in `~/.config/goose/config.yaml`

## Workflow

### Step 1 — Route the signal

| Signal | Go to |
|--------|-------|
| `goose gcp provider` | Step 2 only |
| `configure goose gcp` | Steps 2–5 |

### Step 2 — Check current state (Query)

```bash
bash ~/.agents/skills/goose-gcp-provider/scripts/verify.sh
```

Report each check. S4 is informational: it names the strongest usable model.

### Step 3 — Dry run

```bash
bash ~/.agents/skills/goose-gcp-provider/scripts/setup.sh
```

- `DRY_RUN_RESULT=CONVERGED` → report "already configured". Stop.
- `DRY_RUN_RESULT=PENDING` → show the ranking and the change list. Ask for approval.

Pass the user's choice through: `--model <name>`, `--family sonnet`, `--region <r>`.

### Step 4 — Apply (after approval)

```bash
bash ~/.agents/skills/goose-gcp-provider/scripts/setup.sh --apply
```

Repeat the same flags as Step 3. The script runs a live goose chat first and
writes nothing if it fails.

### Step 5 — Verify and hand off

```bash
bash ~/.agents/skills/goose-gcp-provider/scripts/verify.sh --live
```

Tell the user the Desktop step from the script output: restart Goose Desktop
or open the model switcher, choose GCP Vertex AI, and type the model name.

## Output Contract

Report as a table:

| Item | Value |
|------|-------|
| Model | `providers.gcp_vertex_ai.model` before → after |
| Region | `GCP_LOCATION` before → after |
| Test | goose live chat result |
| Backup | path printed by setup.sh |
| Desktop | restart / type-the-name note |

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `setup.sh` | ✅ | Exit 1 before writing on precondition/test failure; after writing, a failed post-check restores the backup. Exit 2 → fix flags. |
| `verify.sh` | ✅ (read-only) | Report failing check IDs; match Troubleshooting. |

## Gotchas

| # | Issue | Detail |
|:-:|-------|--------|
| 1 | **Picker list is compiled in** | goose 1.59 `gcp_vertex_ai` known models end at 4.6; no config key extends the list. Type the name in Desktop's switcher (`Use: "<name>"`). |
| 2 | **Desktop writes the same key** | Picking a model in Desktop writes `providers.gcp_vertex_ai.model` **and** `active_provider` (verified 2026-11-13). This skill changes `active_provider` only with `--activate`. |
| 3 | **Recent records the model you leave** | On a model switch Desktop adds the *previous* provider/model to `recentModels`, not the new one (`EF(recent, prevProvider, prevModel)` in Desktop 1.59.0). A typed gcp model appears in Recent only after you switch away from it. |
| 4 | **Built-in default is Gemini** | With no `model:` line, goose picks `gemini-2.5-flash` for this provider. |
| 5 | **One region per provider** | `GCP_LOCATION` applies to every model; the pick is filtered to models with 200 in that region. New Claude models are usually 429 in `us-east5`, 200 on `global`. |
| 6 | **Credentials come from process env** | goose reads `GOOGLE_APPLICATION_CREDENTIALS` via the environment, not `~/.config/goose/.env`. Without it goose falls back to user ADC. |
| 7 | **Desktop rewrites config.yaml** | Edits made while Desktop is running can be overwritten by a later model switch; setup.sh re-reads the file immediately before writing. |
| 8 | **Provider switch ignores the saved model** | Desktop 1.59.0 Switch Model dialog restores a provider's model from `saved_model`, but `goose serve` 1.59.0 never sends that field. Desktop falls back to `kF()`: the first built-in model matching `/claude-sonnet-4/`, `/claude-4/`, … — e.g. `claude-sonnet-4-6` — and on confirm writes it to `providers.gcp_vertex_ai.model` + `active_provider`, overwriting this skill's value. Workaround: switch via the bottom-bar **Recent** entry `claude-opus-5-5 — gcp_vertex_ai`, or type the name and pick `Use: "<name>"` before confirming. Not fixable from config. Same bug hits `custom_redhat` (see `goose-litellm-provider` gotcha #1). |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "GOOGLE_APPLICATION_CREDENTIALS unset" | Shell lacks the SA variable | `export GOOGLE_APPLICATION_CREDENTIALS=<SA key>` |
| S2b fails | Desktop launcher lacks the variable | Add it to the `Exec=env …` line in `Goose.desktop`, restart Desktop |
| "did not return 200" | Model not usable in that region | `hey vertex model list`; choose another model or `--region` |
| "No model from gcp-vertex-models" | Missing/stale probe cache | `hey refresh vertex models` |
| goose test fails, 429 | Regional quota | Use `--region global` |
| Desktop still shows old model | Desktop not restarted | Restart Desktop or type the name in the switcher |
| Switching to GCP in Desktop selects a sonnet-4 model | Gotcha #8 (`saved_model` not sent by goose serve) | Use the Recent entry or type the name; if already saved, re-run `hey configure goose gcp` |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
