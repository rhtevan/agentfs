---
name: goose-litellm-provider
description: "Configure Goose to use a local LiteLLM proxy as a custom provider, with model discovery and verification"
version: 1.2.0
platforms: [linux]
metadata:
  tags: [goose, litellm, custom-provider, redhat, configuration]
  related_skills: [litellm-vertex-ai-proxy, litellm-proxy-status, hermes-litellm-provider, goose-maas-provider]
---

# Configure Goose with a Local LiteLLM Proxy Provider

Set up Goose (CLI and Desktop) to use a **local LiteLLM proxy** as a
custom provider. This covers the **RedHat** provider pattern — a local
LiteLLM proxy backed by Vertex AI Claude models (no auth,
`http://localhost:4000`).

For remote MaaS (Model as a Service) setup, see the `goose-maas-provider`
skill instead.

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- LiteLLM proxy running locally (see skill `litellm-vertex-ai-proxy` to
  set one up); must be accessible at `http://localhost:4000` (default
  LiteLLM port)
- Use skill `litellm-proxy-status` to verify the proxy is healthy before
  proceeding

## Reference Configuration

The custom provider is defined as a JSON file under
`~/.config/goose/custom_providers/` with a matching entry in
`~/.config/goose/config.yaml`.

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_redhat.json`

```json
{
  "name": "custom_redhat",
  "engine": "openai",
  "display_name": "RedHat",
  "description": "Local LiteLLM proxy to Vertex AI (Claude models)",
  "api_key_env": "",
  "base_url": "http://localhost:4000",
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
  custom_redhat:
    enabled: true
    model: claude-opus-4-6
    configured: true
```

### Key Fields Explained

| Field | Value | Why |
|---|---|---|
| `name` | `custom_redhat` | Internal identifier; must match config.yaml |
| `engine` | `openai` | LiteLLM exposes an OpenAI-compatible API |
| `display_name` | `RedHat` | Friendly name shown in provider picker |
| `base_url` | `http://localhost:4000` | Local LiteLLM proxy address |
| `requires_auth` | `false` | Local LiteLLM proxy does not require an API key |
| `api_key_env` | `""` | No API key environment variable needed |
| `timeout_seconds` | `600` | 10-minute timeout for long-running requests |
| `supports_streaming` | `true` | LiteLLM supports streaming responses |
| `preserves_thinking` | `true` | Pass through Claude thinking blocks |
| `models` | (see JSON) | One entry per model with 128K context limit |

---

## Workflow

### Step 1 — Verify LiteLLM Proxy Is Running

```bash
systemctl --user status litellm-proxy
curl -s http://127.0.0.1:4000/health | python3 -m json.tool
```

All endpoints should be healthy. If not, run:

```bash
systemctl --user start litellm-proxy
```

Or use the `litellm-vertex-ai-proxy` skill to set it up from scratch.

### Step 2 — Discover Available Models

```bash
curl -s http://127.0.0.1:4000/v1/models | python3 -m json.tool
```

Record the model IDs. These will be listed in the custom provider JSON.

### Step 3 — Create the Custom Provider JSON

Write the JSON file shown in the [Reference Configuration](#custom-provider-json)
section above to:

```
~/.config/goose/custom_providers/custom_redhat.json
```

Create the directory if it does not exist:

```bash
mkdir -p ~/.config/goose/custom_providers
```

### Step 4 — Configure via `goose configure` CLI (Interactive)

Alternatively, use the interactive wizard:

```bash
goose configure
```

1. Select **Custom Providers**
2. Select **Add A Custom Provider**
3. API Type → **OpenAI Compatible**
4. Name → `RedHat`
5. API URL → `http://localhost:4000`
6. Authentication Required → **No**
7. Available Models → `claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5`
8. Streaming Support → **Yes**

Then activate it:

```bash
goose configure
```

1. Select **Configure Providers**
2. Select **RedHat** from the provider list
3. Choose `claude-opus-4-6` as the default model

### Step 5 — Verify config.yaml

Check that `~/.config/goose/config.yaml` contains the provider entry and
active provider setting shown in the
[Reference Configuration](#configyaml-provider-entry) section.

```bash
grep -A3 'custom_redhat' ~/.config/goose/config.yaml
grep 'active_provider' ~/.config/goose/config.yaml
```

Expected output:

```
  custom_redhat:
    enabled: true
    model: claude-opus-4-6
    configured: true
active_provider: custom_redhat
```

### Step 6 — Test from CLI

```bash
goose run -t "Say hello in one sentence"
```

Verify the response comes through successfully via the LiteLLM proxy.

### Step 7 — Test from Desktop (Optional)

1. Launch Goose Desktop
2. Open Settings → Models
3. Confirm **RedHat** appears as a configured provider
4. Select it and choose a model
5. Send a test message

---

## Recovery Procedure

If the RedHat custom provider is lost (e.g., after a config reset or
reinstall), restore it by:

1. **Ensure LiteLLM proxy is running** (use `litellm-proxy-status` skill)
2. **Copy the JSON file** from this skill's reference into
   `~/.config/goose/custom_providers/custom_redhat.json`
3. **Add the provider entry** to `~/.config/goose/config.yaml` under
   `providers:`
4. **Set `active_provider: custom_redhat`** in config.yaml
5. **Restart Goose** — the RedHat provider will be available

Or re-run the interactive wizard (Step 4) to recreate it from scratch.

### Quick Recovery Script

```bash
#!/usr/bin/env bash
# Restore the RedHat custom provider for Goose
set -euo pipefail

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_redhat.json"

mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_FILE" << 'EOF'
{
  "name": "custom_redhat",
  "engine": "openai",
  "display_name": "RedHat",
  "description": "Local LiteLLM proxy to Vertex AI (Claude models)",
  "api_key_env": "",
  "base_url": "http://localhost:4000",
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

echo "✅ RedHat custom provider restored to: $PROVIDER_FILE"
echo ""
echo "Next steps:"
echo "  1. Run 'goose configure' → Configure Providers → RedHat"
echo "  2. Or manually add to ~/.config/goose/config.yaml:"
echo ""
echo "     providers:"
echo "       custom_redhat:"
echo "         enabled: true"
echo "         model: claude-opus-4-6"
echo "         configured: true"
echo "     active_provider: custom_redhat"
```

---

## Verification Checklist

- [ ] LiteLLM proxy is running and healthy (`litellm-proxy-status` skill)
- [ ] `custom_redhat.json` exists in `~/.config/goose/custom_providers/`
- [ ] `config.yaml` has `custom_redhat` in `providers:` with `enabled: true`
- [ ] `active_provider: custom_redhat` is set (if RedHat is the default)
- [ ] `goose configure` shows **RedHat** in the provider list
- [ ] A test chat returns a valid LLM response
- [ ] `curl http://127.0.0.1:4000/v1/models` lists all expected models

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| RedHat not in provider list | Missing JSON file | Copy `custom_redhat.json` to `~/.config/goose/custom_providers/` |
| "Connection refused" | LiteLLM proxy not running | `systemctl --user start litellm-proxy` |
| Provider shows but won't connect | `base_url` wrong | Verify `http://localhost:4000` is correct |
| Only 1 model available | Models not listed in JSON | Update the `models` array in the JSON file |
| Config lost after update | Goose config reset | Re-run the recovery procedure above |
| Timeout on long requests | `timeout_seconds` too low | Increase from 600 to a higher value |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 19:25 | v1.2 — Removed MaaS content (moved to dedicated `goose-maas-provider` skill); restored as local-proxy-only; updated description, tags, and related_skills |
| 2026-07-06 19:14 | v1.1 — Added MaaS remote provider config (now removed) |
| 2026-07-06 18:04 | v1.0 — Initial skill, capturing RedHat custom provider configuration |
