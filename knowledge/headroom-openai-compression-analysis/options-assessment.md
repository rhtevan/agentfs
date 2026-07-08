---
type: decision
title: "LLM Proxy Architecture Decision — When to Keep vs Remove a Compression Proxy"
created: 2026-07-08
updated: 2026-07-08 09:55
tags: [headroom, architecture, decision, proxy, observability, compression]
---

# LLM Proxy Architecture Decision

When an LLM compression proxy provides zero compression due to an
API format mismatch, should it be kept for observability or removed
for simplicity?

## Decision Framework

| Factor | Keep Proxy | Remove Proxy |
|--------|-----------|-------------|
| Memory budget | Generous (>1GB spare) | Constrained |
| Observability need | High (cost tracking, latency monitoring) | Low (logs sufficient) |
| Future compression likely | Yes (upstream fix expected) | No (architectural barrier) |
| Chain complexity tolerance | Acceptable | Minimize hops |

## Value a Passthrough Proxy Still Provides

- Per-request token counts and latency tracking (`/stats`)
- Cost accounting across models and sessions
- Health monitoring of the upstream API chain (`/health`)
- Prometheus metrics (`/metrics`)
- Single point to re-enable compression if the format mismatch
  is resolved upstream

## Cost of Keeping a Passthrough Proxy

- ~755MB memory for a monitoring-only service
- Extra network hop (~38ms avg, negligible)
- Operational complexity of an additional systemd service

## Decision Taken

**Remove Headroom from the active chain** (2026-07-08).

Rationale: Compression provides zero value for OpenAI-format traffic.
Observability features don't justify ~755MB on a development
workstation. Configuration preserved for easy re-enablement.

Traffic chain simplified:
```
Goose → LiteLLM (:4000) → Vertex AI (Claude)
```

Reversibility: `systemctl --user enable --now headroom-proxy`

## Signals to Re-evaluate

- Headroom release with OpenAI message compression support
- `--compress-user-messages` flag becoming functional
- Content router improvements for flat message streams
- Client adding Anthropic-native API support
