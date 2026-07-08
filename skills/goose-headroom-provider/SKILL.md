---
name: goose-headroom-provider
description: "Configure Goose to use the Headroom context-optimization proxy as a custom provider, chained to LiteLLM for upstream LLM access"
version: 2.0.0
platforms: [linux]
metadata:
  tags: [goose, headroom, custom-provider, context-optimization, compression, configuration]
  related_skills: [headroom-litellm-proxy, headroom-proxy-status, goose-litellm-provider, litellm-proxy-status]
---

# Configure Goose Custom Provider for Headroom

Create and configure a Goose custom provider that points to the local
Headroom context-optimization proxy. This skill covers **only** the Goose
provider configuration — for Headroom installation and systemd setup, see
the `headroom-litellm-proxy` skill.

## Traffic Chain

```
Goose (custom_headroom) → Headroom Proxy (:8787) → LiteLLM (:4000) → Vertex AI (Claude)
                           ↑ context compression        ↑ model routing
```

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- Headroom proxy running on port 8787 (use `headroom-litellm-proxy` skill
  to set up; verify with `headroom-proxy-status` skill)
- LiteLLM proxy running on port 4000 (upstream of Headroom)

---

## Reference Configuration

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_headroom.json`

```json
{
  "name": "custom_headroom",
  "engine": "openai",
  "display_name": "Headroom",
  "description": "Headroom context-optimization proxy → LiteLLM (Vertex AI Claude models)",
  "api_key_env": "",
  "base_url": "http://localhost:8787",
  "models": [
    {
      "name": "claude-opus-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-5",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 600,
  "supports_streaming": true,
  "requires_auth": false,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": true
}
```

### config.yaml Provider Entry

```yaml
providers:
  custom_headroom:
    enabled: true
    model: claude-opus-4-6
    configured: true
```

### .env Entry

**File:** `~/.config/goose/.env`

```
CUSTOM_HEADROOM_API_KEY=sk-headroom
```

The API key value is a placeholder — Headroom does not require
authentication by default. However, Goose custom providers expect an
entry in `.env` for the `<NAME>_API_KEY` pattern.

### Key Fields Explained

| Field | Value | Why |
|---|---|---|
| `name` | `custom_headroom` | Internal identifier; must match config.yaml |
| `engine` | `openai` | Headroom exposes OpenAI-compatible `/v1/chat/completions` |
| `display_name` | `Headroom` | Friendly name shown in provider picker |
| `base_url` | `http://localhost:8787` | Local Headroom proxy address |
| `requires_auth` | `false` | Headroom proxy does not require authentication |
| `api_key_env` | `""` | No API key environment variable needed |
| `timeout_seconds` | `600` | 10-minute timeout for long-running requests |
| `supports_streaming` | `true` | Headroom supports streaming responses |
| `preserves_thinking` | `true` | Pass through Claude thinking blocks |
| `models` | (see JSON) | Must match models available in upstream LiteLLM |

---

## Workflow

### Step 1 — Verify Headroom Proxy Is Running

```bash
systemctl --user status headroom-proxy
curl -s http://127.0.0.1:8787/health | python3 -m json.tool
```

All checks should be healthy. If not running, use the
`headroom-litellm-proxy` skill to set it up.

### Step 2 — Create the Custom Provider JSON

Write the JSON file shown in the [Reference Configuration](#custom-provider-json)
section to:

```bash
mkdir -p ~/.config/goose/custom_providers
# Write custom_headroom.json (see Reference Configuration above)
```

### Step 3 — Add to Goose config.yaml

Add the provider entry under `providers:` in `~/.config/goose/config.yaml`:

```yaml
  custom_headroom:
    enabled: true
    model: claude-opus-4-6
    configured: true
```

Add to `~/.config/goose/.env`:

```
CUSTOM_HEADROOM_API_KEY=sk-headroom
```

### Step 4 — Configure via `goose configure` CLI (Alternative)

Alternatively, use the interactive wizard:

```bash
goose configure
```

1. Select **Custom Providers**
2. Select **Add A Custom Provider**
3. API Type → **OpenAI Compatible**
4. Name → `Headroom`
5. API URL → `http://localhost:8787`
6. Authentication Required → **No**
7. Available Models → `claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5`
8. Streaming Support → **Yes**

### Step 5 — Switch to the Headroom Provider

Set as active provider in `~/.config/goose/config.yaml`:

```yaml
active_provider: custom_headroom
```

Or use the interactive wizard:

```bash
goose configure
```

1. Select **Configure Providers**
2. Select **Headroom** from the list
3. Choose your preferred model

### Step 6 — Verify config.yaml

```bash
grep -A3 'custom_headroom' ~/.config/goose/config.yaml
grep 'active_provider' ~/.config/goose/config.yaml
```

Expected output:

```
  custom_headroom:
    enabled: true
    model: claude-opus-4-6
    configured: true
active_provider: custom_headroom
```

### Step 7 — Test from CLI

```bash
goose run -t "Say hello in one sentence"
```

Verify the response comes through the Headroom → LiteLLM chain.

---

## Comparing Providers: Headroom vs Direct LiteLLM

You can A/B compare by switching `active_provider` in config.yaml:

| Provider | Path | Context optimization |
|---|---|---|
| `custom_redhat` | Goose → LiteLLM (:4000) → Vertex AI | None |
| `custom_headroom` | Goose → Headroom (:8787) → LiteLLM (:4000) → Vertex AI | ✅ Automatic compression |

Both use the same upstream models. The Headroom provider adds a
compression layer that reduces token usage on long conversations.

Check compression savings anytime:

```bash
curl -s http://127.0.0.1:8787/stats | python3 -m json.tool
```

---

## Recovery Procedure

If the Headroom custom provider is lost (e.g., after a config reset):

1. **Ensure Headroom proxy is running** (use `headroom-proxy-status` skill)
2. **Copy the JSON file** from this skill's reference into
   `~/.config/goose/custom_providers/custom_headroom.json`
3. **Add the provider entry** to `~/.config/goose/config.yaml` under
   `providers:`
4. **Add API key** to `~/.config/goose/.env`:
   `CUSTOM_HEADROOM_API_KEY=sk-headroom`
5. **Set `active_provider: custom_headroom`** in config.yaml
6. **Restart Goose** — the Headroom provider will be available

### Quick Recovery Script

```bash
#!/usr/bin/env bash
# Restore the Headroom custom provider for Goose
set -euo pipefail

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_headroom.json"

mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_FILE" << 'EOF'
{
  "name": "custom_headroom",
  "engine": "openai",
  "display_name": "Headroom",
  "description": "Headroom context-optimization proxy → LiteLLM (Vertex AI Claude models)",
  "api_key_env": "",
  "base_url": "http://localhost:8787",
  "models": [
    {
      "name": "claude-opus-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-6",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-5",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 600,
  "supports_streaming": true,
  "requires_auth": false,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": true
}
EOF

# Ensure .env has the API key
ENV_FILE="$HOME/.config/goose/.env"
if ! grep -q 'CUSTOM_HEADROOM_API_KEY' "$ENV_FILE" 2>/dev/null; then
  echo 'CUSTOM_HEADROOM_API_KEY=sk-headroom' >> "$ENV_FILE"
fi

echo "✅ Headroom custom provider restored to: $PROVIDER_FILE"
echo ""
echo "Next steps:"
echo "  1. Add to ~/.config/goose/config.yaml under providers:"
echo ""
echo "     providers:"
echo "       custom_headroom:"
echo "         enabled: true"
echo "         model: claude-opus-4-6"
echo "         configured: true"
echo "     active_provider: custom_headroom"
echo ""
echo "  2. Verify Headroom proxy is running:"
echo "     systemctl --user status headroom-proxy"
```

---

## Verification Checklist

- [ ] Headroom proxy running and healthy (prerequisite)
- [ ] `custom_headroom.json` exists in `~/.config/goose/custom_providers/`
- [ ] `config.yaml` has `custom_headroom` in `providers:` with `enabled: true`
- [ ] `CUSTOM_HEADROOM_API_KEY=sk-headroom` is in `~/.config/goose/.env`
- [ ] `goose configure` shows **Headroom** in the provider list
- [ ] A test chat via Goose returns a valid LLM response

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Headroom not in provider list | Missing JSON file | Copy `custom_headroom.json` to `~/.config/goose/custom_providers/` |
| "Connection refused" on :8787 | Headroom proxy not running | `systemctl --user start headroom-proxy` (see `headroom-litellm-proxy` skill) |
| Provider shows but won't connect | `base_url` wrong in JSON | Verify `http://localhost:8787` |
| Only 1 model available | Models not listed in JSON | Update the `models` array to match LiteLLM models |
| Config lost after update | Goose config reset | Re-run the recovery procedure above |
| Timeout on long requests | `timeout_seconds` too low | Increase from 600 to a higher value |
| No compression visible in `/stats` | Short messages don't compress | Use longer conversations; check `curl http://localhost:8787/stats` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 21:47 | v2.0 — Refactored: split out installation/systemd to `headroom-litellm-proxy` skill; this skill now covers Goose provider config only |
| 2026-07-06 21:37 | v1.0 — Initial skill capturing Headroom provider setup |
