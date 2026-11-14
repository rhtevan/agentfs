---
name: litellm-proxy-status
description: >
  litellm status, check litellm, litellm health,
  litellm model list, litellm default model
platforms: ['linux']
metadata:
  version: "1.2.0"
  model-tier: T2
  tags: [litellm, proxy, status, health, systemd]
  related_skills: [litellm-vertex-ai-proxy, gcp-vertex-models, hermes-litellm-provider, goose-litellm-provider]
---

# LiteLLM Proxy Status Check

Check the health, configuration, and runtime status of the local
LiteLLM proxy. Queries systemd service state, health and model
endpoints, and proxy configuration files. Also answers two read-only
model queries: which models the proxy serves (with region and context
limits) and which served model is the strongest. To change the served
list, use `refresh litellm models` (litellm-vertex-ai-proxy).

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.2.0 |
| **Trigger** | `hey litellm status` / `hey check litellm` / `hey litellm model list` / `hey litellm default model` |
| **Dependencies** | systemd, curl, litellm-proxy service; `gcp-vertex-models` (ranking for default model) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Report systemd service status | `systemctl --user status litellm-proxy` shows active/inactive |
| S2 | Report health endpoint state | `/health` returns healthy/unhealthy endpoint counts |
| S3 | List available models | `/v1/models` returns model ID list |
| S4 | Display proxy and service configuration | Config files read successfully |
| S5 | List served models with region and context limits | `scripts/models.sh list` exits 0 with `Served: N` |
| S6 | Report the strongest served model | `scripts/models.sh default` prints one model name that `/v1/models` serves |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1–S4 | `bash scripts/check-status.sh` | Sections for systemd, health, models, configs |
| T2 | S5 | `bash scripts/models.sh list` | Table + `Served: N` (N ≥ 1), exit 0 |
| T3 | S6 | `bash scripts/models.sh default --family sonnet` | One `claude-sonnet-…` name, exit 0 |
| T4 | S5 | `bash scripts/models.sh list --url http://127.0.0.1:4999` | Exit 1, "unreachable" |

## Rules

Do NOT fabricate health or model data. Every value in the report
MUST come from actual command or HTTP endpoint output. If an
endpoint is unreachable, report "unreachable" — do not guess values.

## Workflow

### Step 0 — Route the signal

| Signal | Go to |
|--------|-------|
| `litellm status`, `check litellm`, `litellm health` | Step 1 |
| `litellm model list` | Step 4 |
| `litellm default model` | Step 5 |

### Step 1 — Run the status script

```bash
bash ~/.agents/skills/litellm-proxy-status/scripts/check-status.sh
```

The script gathers all status facts: systemd service state, health
endpoint, model list, LiteLLM config, and service config. Read the
output — it contains all the data needed for the report.

### Step 2 — Report the results

Read the script output. Build the summary table defined in the
Output Contract below. Include:

- Service state (active/inactive) and uptime
- Health status and endpoint counts (healthy vs unhealthy)
- List of model IDs the proxy serves
- Port, credentials path, and config file location

### Step 3 — Check logs (conditional)

Run only if Step 1 shows the service is inactive or unhealthy:

```bash
journalctl --user -u litellm-proxy --no-pager -n 20
```

### Step 4 — Model list (Query)

```bash
bash ~/.agents/skills/litellm-proxy-status/scripts/models.sh list
```

Show the table. Use `--json` when another skill needs the data. The list
reflects the proxy config, not live Vertex availability — for that, use
`vertex model list` (gcp-vertex-models).

### Step 5 — Default model (Query)

```bash
bash ~/.agents/skills/litellm-proxy-status/scripts/models.sh default
```

The first stdout line is the strongest served model. Stderr carries the full
ranking — show it. Use `--family sonnet` or `--family haiku` to pick within a family.

## Output Contract

Present a summary table:

| Item | Status |
|------|--------|
| Service | active/inactive, uptime |
| Health | healthy/unhealthy endpoint count |
| Models | list of model names |
| Port | 4000 |
| Credentials | service account email from key file |
| Config | ~/.config/litellm/config.yaml |

## Error Handling

| Step | Command | On Failure |
|:----:|---------|------------|
| 1 | `check-status.sh` | Script exits 0 even if service is down. Parse output for state. |
| 3 | `journalctl` | No logs → report "no recent log entries" |
| 4–5 | `models.sh` (read-only, idempotent) | Exit 1 "unreachable" → run Step 1; "Dependency missing" → install gcp-vertex-models; exit 2 → fix arguments |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Service not running | Stopped or crashed | `systemctl --user start litellm-proxy` |
| Service fails to start | Config error or missing credentials | Check logs: `journalctl --user -u litellm-proxy -n 50` |
| Health shows unhealthy models | Backend unreachable (Vertex AI) | Verify credentials and network connectivity |
| Models endpoint empty | No models configured | Check `~/.config/litellm/config.yaml` model_list |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
