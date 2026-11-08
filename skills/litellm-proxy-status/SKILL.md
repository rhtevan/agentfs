---
name: litellm-proxy-status
description: >
  litellm status, check litellm, litellm health
platforms: ['linux']
metadata:
  version: "1.1.0"
  model-tier: T2
  tags: [litellm, proxy, status, health, systemd]
  related_skills: [litellm-vertex-ai-proxy, hermes-litellm-provider]
---

# LiteLLM Proxy Status Check

Check the health, configuration, and runtime status of the local
LiteLLM proxy. Queries systemd service state, health and model
endpoints, and proxy configuration files.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.1.0 |
| **Trigger** | `hey litellm status` / `hey check litellm` |
| **Dependencies** | systemd, curl, litellm-proxy service |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Report systemd service status | `systemctl --user status litellm-proxy` shows active/inactive |
| S2 | Report health endpoint state | `/health` returns healthy/unhealthy endpoint counts |
| S3 | List available models | `/v1/models` returns model ID list |
| S4 | Display proxy and service configuration | Config files read successfully |

## Rules

Do NOT fabricate health or model data. Every value in the report
MUST come from actual command or HTTP endpoint output. If an
endpoint is unreachable, report "unreachable" — do not guess values.

## Workflow

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

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Service not running | Stopped or crashed | `systemctl --user start litellm-proxy` |
| Service fails to start | Config error or missing credentials | Check logs: `journalctl --user -u litellm-proxy -n 50` |
| Health shows unhealthy models | Backend unreachable (Vertex AI) | Verify credentials and network connectivity |
| Models endpoint empty | No models configured | Check `~/.config/litellm/config.yaml` model_list |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
