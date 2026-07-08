---
name: headroom-litellm-proxy
description: "Install the Headroom context-optimization proxy and configure it as a systemd user service chained to a local LiteLLM upstream"
version: 1.1.0
platforms: [linux]
metadata:
  tags: [headroom, proxy, litellm, systemd, compression, context-optimization, installation]
  related_skills: [headroom-proxy-status, litellm-proxy-status, litellm-vertex-ai-proxy, goose-headroom-provider]
---

# Headroom Proxy — Installation & Systemd Setup

Install the Headroom context-optimization proxy and run it as a systemd
user-scope service, chained to a local LiteLLM proxy for upstream LLM
access.

## Traffic Chain

```
Any OpenAI-compatible client → Headroom Proxy (:8787) → LiteLLM (:4000) → Vertex AI (Claude)
                                 ↑ context compression        ↑ model routing
```

Headroom exposes OpenAI-compatible endpoints (`/v1/chat/completions`) and
Anthropic-compatible endpoints (`/v1/messages`), so any client that
speaks either protocol can use it.

## Prerequisites

- LiteLLM proxy running locally on port 4000 (see skill
  `litellm-vertex-ai-proxy` to set one up; verify with
  `litellm-proxy-status` skill)
- `uv` package manager installed (`curl -LsSf https://astral.sh/uv/install.sh | sh`)

---

## Workflow

### Step 1 — Install Headroom

Install Headroom using `uv`:

```bash
uv tool install 'headroom-ai[proxy]'
```

Verify:

```bash
headroom --version
headroom proxy --help
```

If `uv` is not installed:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### Step 2 — Create the Headroom Systemd Service

**File:** `~/.config/systemd/user/headroom-proxy.service`

```ini
[Unit]
Description=Headroom Proxy - Context optimization layer for LLM traffic
After=litellm-proxy.service
Wants=litellm-proxy.service

[Service]
Type=simple
ExecStart=/home/<USER>/.local/bin/headroom proxy \
  --host 127.0.0.1 \
  --port 8787 \
  --openai-api-url http://localhost:4000 \
  --no-ccr-inject-tool \
  --no-ccr-marker \
  --no-telemetry \
  --no-rate-limit \
  --request-timeout-seconds 600 \
  --mode token \
  --target-ratio 0.5 \
  --intercept-tool-results
Restart=on-failure
RestartSec=5
Environment=OPENAI_TARGET_API_URL=http://localhost:4000
Environment=HEADROOM_TELEMETRY=off

[Install]
WantedBy=default.target
```

Replace `<USER>` with your username.

#### Key Service Flags Explained

| Flag | Purpose |
|---|---|
| `--openai-api-url http://localhost:4000` | Route upstream traffic to LiteLLM |
| `--no-ccr-inject-tool` | Don't inject CCR retrieve tool (downstream clients can't resolve it) |
| `--no-ccr-marker` | Don't add CCR markers to compressed content |
| `--no-telemetry` | Disable anonymous telemetry |
| `--no-rate-limit` | Disable rate limiting (local use) |
| `--mode token` | Prioritize token compression savings |
| `--target-ratio 0.5` | Kompress compression target — keep ~50% of tokens in compressed turns (lower = more aggressive) |
| `--intercept-tool-results` | Compress stale tool result blocks (file reads, shell output, etc.) |
| `--request-timeout-seconds 600` | 10-minute timeout for long-running requests |

#### Compression Tuning

The `--target-ratio` controls how aggressively Kompress ML compresses
older conversation turns:

| Value | Behavior | Risk |
|---|---|---|
| `0.3` | Aggressive — keep ~30%, remove ~70% | Model may miss details from older turns |
| `0.5` | Balanced — keep ~50%, remove ~50% | Good default for most workloads |
| `0.7` | Conservative — keep ~70%, remove ~30% | Minimal information loss, modest savings |
| unset | Kompress decides autonomously | Very conservative, often skips compression |

Only older conversation turns are compressed — the most recent messages
always retain full fidelity.

#### Flags NOT to Use

| Flag | Why to avoid |
|---|---|
| `--lossless` | Restricts to format-native lossless compaction only — blocks Kompress ML compression, resulting in near-zero savings through OpenAI-compatible endpoints |
| `--memory` | Injects `memory_save`/`memory_search` tools that downstream clients (e.g., Goose) don't understand; duplicates agent-side memory systems |
| `--learn` | Writes `MEMORY.md`/`AGENTS.md` to CWD which conflicts with agent-managed files; `headroom learn` CLI only supports Claude Code/Codex/Gemini, not Goose |

### Step 3 — Enable and Start the Service

```bash
systemctl --user daemon-reload
systemctl --user enable headroom-proxy
systemctl --user start headroom-proxy
```

### Step 4 — Verify the Service

```bash
systemctl --user status headroom-proxy
```

Confirm it shows `active (running)`.

### Step 5 — Verify Health Endpoint

```bash
curl -s http://127.0.0.1:8787/health | python3 -m json.tool
```

Confirm `status` is `healthy` and `ready` is `true`. Check that:
- `config.openai_api_url` shows `http://localhost:4000`
- `config.optimize` is `true`
- `config.disable_kompress` is `false`
- `config.target_ratio` is `0.5`

### Step 6 — Test the Full Chain

Test end-to-end through Headroom → LiteLLM → Vertex AI:

```bash
curl -s -X POST http://localhost:8787/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer sk-EXAMPLE-not-real' \
  -d '{
    "model": "claude-sonnet-4-6",
    "messages": [{"role": "user", "content": "Say hello in one word."}],
    "max_tokens": 50
  }'
```

You should get a valid chat completion response with a `choices` array.

### Step 7 — Check Compression Stats

```bash
curl -s http://127.0.0.1:8787/stats | python3 -m json.tool
```

Key fields to verify:
- `summary.compression.requests_compressed` — should increase as conversations grow
- `summary.compression.avg_compression_pct` — target ~50% with ratio 0.5
- `summary.compression.total_tokens_removed` — tokens saved
- `summary.cost.total_saved_usd` — dollar savings
- `summary.uncompressed_requests` — breakdown of why some requests skip compression
- `config.target_ratio` — confirms 0.5 is active

Compression kicks in on **longer conversations** once older turns exceed
the `min_tokens_to_crush` threshold (default 500 tokens). Short
conversations will show zero compression — this is expected.

---

## Headroom API Endpoints

The Headroom proxy exposes these endpoints:

| Endpoint | Method | Description |
|---|---|---|
| `/v1/chat/completions` | POST | OpenAI-compatible chat completions |
| `/v1/messages` | POST | Anthropic-compatible messages |
| `/v1/compress` | POST | Compression-only (no LLM call) |
| `/health` | GET | Service health and configuration |
| `/stats` | GET | Compression statistics |
| `/stats-history` | GET | Durable compression history |
| `/metrics` | GET | Prometheus-format metrics |
| `/livez` | GET | Process liveness |
| `/readyz` | GET | Traffic readiness |

---

## Using Headroom with Any Client

Point any OpenAI-compatible or Anthropic-compatible client at the proxy:

```bash
# OpenAI-compatible clients
OPENAI_BASE_URL=http://localhost:8787/v1 your-app

# Anthropic-compatible clients (e.g. Claude Code)
ANTHROPIC_BASE_URL=http://localhost:8787 claude
```

For Goose specifically, see the `goose-headroom-provider` skill.

---

## Service Management

```bash
# Status
systemctl --user status headroom-proxy

# Start / Stop / Restart
systemctl --user start headroom-proxy
systemctl --user stop headroom-proxy
systemctl --user restart headroom-proxy

# Live logs
journalctl --user -u headroom-proxy -f

# Disable auto-start
systemctl --user disable headroom-proxy
```

---

## Verification Checklist

- [ ] Headroom installed (`headroom --version`)
- [ ] `headroom-proxy.service` exists at `~/.config/systemd/user/`
- [ ] Service is enabled and running (`systemctl --user status headroom-proxy`)
- [ ] LiteLLM proxy running on port 4000 (upstream dependency)
- [ ] `curl http://127.0.0.1:8787/health` returns `healthy`
- [ ] `config.target_ratio` is `0.5` and `config.disable_kompress` is `false`
- [ ] Full-chain test via `curl` to `/v1/chat/completions` returns valid response
- [ ] `curl http://127.0.0.1:8787/stats` reports metrics

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `headroom: command not found` | Not installed | `uv tool install 'headroom-ai[proxy]'` |
| Service fails to start | Wrong ExecStart path | Verify `which headroom` and update service file |
| "Connection refused" on :8787 | Service not running | `systemctl --user start headroom-proxy` |
| Health shows unhealthy upstream | LiteLLM not running | `systemctl --user start litellm-proxy` |
| `--openai-api-url` not taking effect | Also set via env var | Check `OPENAI_TARGET_API_URL` in service file |
| High memory usage | Expected (~300–750 MB) | Normal for Headroom with Kompress compression models loaded |
| CCR tool errors from downstream clients | CCR injection enabled | Add `--no-ccr-inject-tool --no-ccr-marker` flags |
| Timeout on long requests | Default timeout too short | Increase `--request-timeout-seconds` |
| 0% compression after many requests | `--lossless` flag set | Remove `--lossless`; ensure `--target-ratio` is set (e.g. 0.5) |
| 0% compression on short conversations | Normal — too few old turns | Compression triggers once older turns exceed `min_tokens_to_crush` (500) |
| All requests show `no_compressible_content` | Content is protected user messages | Remove `--lossless`; add `--target-ratio` to enable ML compression |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-07 16:07 | v1.1 — Removed `--lossless` (blocks ML compression via OpenAI endpoints); added `--target-ratio 0.5` and `--intercept-tool-results` for effective compression; added Compression Tuning section; added Flags NOT to Use section (lossless, memory, learn); expanded health verification checks; expanded stats key fields; added compression-specific troubleshooting entries; updated memory range |
| 2026-07-06 21:46 | v1.0 — Initial skill; split from goose-headroom-provider |
