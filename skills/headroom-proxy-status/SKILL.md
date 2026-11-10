---
name: headroom-proxy-status
description: >
  headroom status, check headroom, headroom health
platforms: ['linux']
metadata:
  version: "1.2.0"
  model-tier: T2
  tags: [headroom, proxy, status, health, systemd, compression, context-optimization]
  related_skills: [litellm-proxy-status, goose-litellm-provider]
---

# Headroom Proxy Status Check

Check the health, configuration, and runtime status of the local
Headroom context-optimization proxy. Queries systemd service state,
health and stats HTTP endpoints, and Goose provider configuration.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.1.0 |
| **Trigger** | `hey headroom status` / `hey check headroom` |
| **Dependencies** | systemd, curl, headroom-proxy service |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Report systemd service status | `systemctl --user status headroom-proxy` shows active/inactive |
| S2 | Report health endpoint state | `/health` returns healthy/unhealthy |
| S3 | Report compression statistics | `/stats` returns compression metrics |
| S4 | Display service and provider configuration | Config files read successfully |

## Rules

Do NOT fabricate health or stats data. Every value in the report
MUST come from actual command or HTTP endpoint output. If an
endpoint is unreachable, report "unreachable" — do not guess values.

## Workflow

### Step 1 — Run the status script

```bash
bash ~/.agents/skills/headroom-proxy-status/scripts/check-status.sh
```

The script gathers all status facts: systemd service state, health
endpoint, compression statistics, stats history, service config,
provider config.

Read the output — it contains all the data needed for the report.

### Step 2 — Report the results

Read the script output.

Build the summary table defined in the Output Contract below.
Include:

- Service state (active/inactive) and uptime
- Proxy health status and operating mode
- Compression effectiveness: percentage, tokens saved, cost savings
- Upstream connection target and key runtime flags
- Goose provider configuration details

### Step 3 — Check logs (conditional)

Run only if Step 1 output indicates an inactive or unhealthy state:

```bash
journalctl --user -u headroom-proxy --no-pager -n 20
```

## Output Contract

Present a summary table:

| Item | Status |
|---|---|
| Service | active/inactive, uptime |
| Health | healthy/unhealthy |
| Version | headroom version |
| Mode | token/cache |
| Upstream | OpenAI API URL (e.g. LiteLLM on :4000) |
| Optimize | enabled/disabled |
| Kompress ML | enabled/disabled |
| Target ratio | compression target value or unset |
| Compression | requests compressed, average compression %, tokens saved |
| Uncompressed reasons | count by reason category |
| Cost savings | USD saved, savings % |
| Port | 8787 |
| Key flags | target-ratio, intercept-tool-results, ccr, rate-limit, memory, etc. |
| Goose provider | custom_headroom — base_url, models |

## Traffic Chain

```
Goose (custom_headroom) → Headroom Proxy (:8787) → LiteLLM (:4000) → Vertex AI (Claude)
                           ↑ context compression        ↑ routing
```

## Error Handling

| Step | Command | On Failure |
|:----:|---------|------------|
| 1 | `systemctl --user status` | Service not found → report "not installed" |
| 2 | `curl /health` | Connection refused → report "proxy not running" |
| 3 | `curl /stats` | Connection refused → skip, note "stats unavailable" |
| 5 | `cat service file` | File missing → report "service not configured" |
| 6 | `cat provider config` | File missing → report "provider not configured" |

## Troubleshooting

If the service is not running:
```bash
systemctl --user start headroom-proxy
```

If the service fails to start, check logs:
```bash
journalctl --user -u headroom-proxy --no-pager -n 50
```

If health endpoint reports an unhealthy upstream, verify LiteLLM:
```bash
systemctl --user status litellm-proxy
curl -s http://127.0.0.1:4000/health | python3 -m json.tool
```

If Goose cannot connect, verify the provider config:
```bash
cat ~/.config/goose/custom_providers/custom_headroom.json
grep custom_headroom ~/.config/goose/config.yaml
```

If compression shows 0% despite long conversations, review the
health and stats output from the script for compression configuration
and thresholds. Common causes: lossless mode enabled, compression
target not configured, or conversations below the minimum token
threshold.


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
