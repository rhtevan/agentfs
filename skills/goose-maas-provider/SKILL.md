---
name: goose-maas-provider
description: "Configure Goose to use a remote MaaS (Model as a Service) LiteLLM instance, with API key setup, reasoning model fixes, and troubleshooting"
version: 1.3.0
platforms: [linux]
metadata:
  tags: [goose, maas, litellm, custom-provider, reasoning, configuration]
  related_skills: [goose-litellm-provider, litellm-proxy-status]
---

# Configure Goose with MaaS (Remote LiteLLM) Provider

Set up Goose (CLI and Desktop) to use a **remote MaaS** endpoint — a
shared LiteLLM instance that requires API key authentication (e.g.,
`https://maas-rhdp.apps.maas.redhatworkshops.io`).

For local LiteLLM proxy setup, see the `goose-litellm-provider` skill
instead.

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- A valid LiteLLM virtual key (starts with `sk-`) for the remote MaaS
  endpoint
- The remote MaaS endpoint URL

## Reference Configuration

The custom provider is defined as a JSON file under
`~/.config/goose/custom_providers/` with a matching entry in
`~/.config/goose/config.yaml`.

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_maas.json`

```json
{
  "name": "custom_maas",
  "engine": "openai",
  "display_name": "MaaS",
  "description": "Custom MaaS provider",
  "api_key_env": "CUSTOM_MAAS_API_KEY",
  "base_url": "https://maas-rhdp.apps.maas.redhatworkshops.io",
  "models": [
    {
      "name": "llama-scout-17b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "gpt-oss-120b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "qwen3-14b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 300,
  "supports_streaming": true,
  "requires_auth": true,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": false
}
```

### config.yaml Provider Entry

```yaml
providers:
  custom_maas:
    enabled: true
    model: llama-scout-17b
    configured: true
```

### Required Global Settings in config.yaml

These settings **must** be present at the top level of `config.yaml`
for MaaS to work properly:

```yaml
GOOSE_TOOLSHIM: true
```

**`GOOSE_TOOLSHIM`** — Enables the tool shim layer. Smaller models
(like `llama-scout-17b`) cannot handle goose's namespaced tool names
(e.g., `computercontroller__web_scrape`). They call tools by short
names (e.g., `web_scrape`) which goose rejects as "Tool not found".
The tool shim strips namespace prefixes before presenting tools to the
model and re-maps them when the model makes a call.

Without this setting, tool calls fail with:
```
Tool 'web_scrape' not found. Available tools: [computercontroller__web_scrape, ...]
```

### ⚠️ Goose Desktop Is NOT Compatible with MaaS

**Goose Desktop v1.41.0 cannot use the MaaS provider for tool-calling
tasks.** Use `goose run --provider custom_maas` (CLI) instead.

Desktop failures across all configurations tested:

| Desktop config | Result |
|---|---|
| `streaming: true` | Response received (tokens counted) but **never saved** or displayed |
| `streaming: false`, no toolshim | Model calls tools by wrong name (strips namespace prefix) |
| `streaming: false`, toolshim on | Model outputs raw Llama native format as text, tools never execute |

All three configurations **work correctly via CLI**. This is a Goose
Desktop v1.41.0 bug specific to custom OpenAI-engine providers.

The provider JSON has `"supports_streaming": false` as a partial
mitigation (at least responses are saved), but tool-calling tasks will
still fail in Desktop.

### Available Models on MaaS

Query the remote endpoint to discover available models:

```bash
curl -s "https://maas-rhdp.apps.maas.redhatworkshops.io/v1/models" \
  -H "Authorization: Bearer <your-sk-key>" | python3 -m json.tool
```

Known models (as of 2026-07-06):

| Model ID | Type | Notes |
|---|---|---|
| `gpt-oss-120b` | Reasoning (OSS) | Default model; reasoning output in `reasoning_content` |
| `qwen3-14b` | Standard | Smaller model |
| `llama-scout-17b` | Standard | Meta Llama Scout |
| `deepseek-r1-distill-qwen-14b` | Reasoning | DeepSeek R1 distilled |

---

## Critical: Reasoning Models Are INCOMPATIBLE with Goose

### ⚠️ DO NOT use `gpt-oss-120b` or `deepseek-r1-*` as the default model

Models that produce `reasoning_content` in their streaming responses
(such as `gpt-oss-120b`, `qwen3-14b`, `deepseek-r1-distill-qwen-14b`)
are **fundamentally broken with Goose** as of v1.41.0. The issue is a
**goose bug** in its OpenAI streaming parser — it cannot handle
`reasoning_content` chunks followed by `tool_calls` chunks.

**Use `llama-scout-17b` instead** — it produces clean responses with no
`reasoning_content` field and works perfectly with Goose.

### What happens with reasoning models

When goose receives a streaming response from a reasoning model:

1. The model sends `reasoning_content` chunks first (thinking)
2. Then sends `tool_calls` chunks (the actual actions)
3. Goose captures the reasoning as a `thinking` block
4. **Goose drops the `tool_calls`** — the session ends with only
   thinking content, 0 output tokens, no tool calls, no response

This happens **regardless** of the `reasoning` and `preserves_thinking`
config settings. Even with both set to `false`, goose still parses
the `reasoning_content` field from the streaming chunks and creates a
thinking block, then fails to process the subsequent tool_calls.

### Evidence

| Setting combo | Result | Session evidence |
|---|---|---|
| `reasoning: true`, `preserves_thinking: true` | Empty response + 400 errors on resume | Sessions 20260706_13, _14, _15, _33 |
| `reasoning: false`, `preserves_thinking: false` | Empty response (thinking only, 0 output tokens) | Session 20260706_35 (after config fix AND goose restart) |
| Non-reasoning model (`llama-scout-17b`) | **Works correctly** | Verified via direct API test |

### Provider config requirements

| Setting | Must be | Why |
|---|---|---|
| `"reasoning"` (model) | `false` | Must be false for all models on MaaS |
| `"preserves_thinking"` (provider) | `false` | Must be false; `true` causes 400 errors when resuming sessions |
| Default model | `llama-scout-17b` | Only non-reasoning model on MaaS that works with Goose |

### Model compatibility matrix

| Model | Has `reasoning_content` | Works with Goose | Notes |
|---|---|---|---|
| `llama-scout-17b` | ❌ No | ✅ **Yes** | Recommended default |
| `gpt-oss-120b` | ✅ Yes (always) | ❌ **No** | Goose drops tool_calls after reasoning |
| `qwen3-14b` | ✅ Yes (always) | ❌ **No** | Same streaming parser issue |
| `deepseek-r1-distill-qwen-14b` | ✅ Yes (always) | ❌ **No** | Same streaming parser issue |

### Diagnostic Test

Test whether a model produces `reasoning_content`:

```bash
curl -s "<base_url>/v1/chat/completions" \
  -H "Authorization: Bearer <key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "<model-name>",
    "messages": [{"role":"user","content":"Say hello"}],
    "max_tokens": 500,
    "stream": false
  }' | python3 -c "
import json,sys
d = json.loads(sys.stdin.read())
c = d['choices'][0]['message']
print(f'content: {c.get(\"content\")}')
print(f'reasoning_content: {c.get(\"reasoning_content\")}')
if c.get('reasoning_content'):
    print('⚠️  This model produces reasoning_content — INCOMPATIBLE with Goose')
else:
    print('✅ No reasoning_content — compatible with Goose')
"
```

---

## API Key Storage

The MaaS API key (starts with `sk-`) is stored in the **GNOME Keyring**
via Goose's built-in secret store. It is **NOT** set as a shell
environment variable.

Goose reads it automatically at runtime from the keyring via the
`CUSTOM_MAAS_API_KEY` env var name configured in the provider JSON.

### Storing the Key

Use `goose configure` → Configure Providers → MaaS to store or update
the key interactively.

### Verifying the Key

```bash
secret-tool search service goose 2>/dev/null | grep CUSTOM_MAAS
```

This should show the key is present in the keyring.

### Key Not Found on Session Restore

If goose logs show:
```
Failed to restore provider for session ...: Could not create provider:
missing required key CUSTOM_MAAS_API_KEY
```

This means the GNOME Keyring was locked or unavailable when Goose tried
to restore a MaaS session. Re-run `goose configure` to re-store the key,
or ensure the keyring is unlocked.

---

## Workflow

### Step 1 — Verify Endpoint Connectivity

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" --connect-timeout 5 \
  "https://maas-rhdp.apps.maas.redhatworkshops.io"
```

Expected: `HTTP 200`

### Step 2 — Verify Authentication

```bash
curl -s "https://maas-rhdp.apps.maas.redhatworkshops.io/v1/models" \
  -H "Authorization: Bearer <your-sk-key>" | python3 -m json.tool
```

Should return a JSON list of available models. If you get a 401 error,
the key is invalid or doesn't start with `sk-`.

### Step 3 — Create the Custom Provider JSON

```bash
mkdir -p ~/.config/goose/custom_providers
```

Write the JSON file from the [Reference Configuration](#custom-provider-json)
section to `~/.config/goose/custom_providers/custom_maas.json`.

### Step 4 — Store the API Key

```bash
goose configure
```

1. Select **Configure Providers**
2. Select **MaaS**
3. Enter the API key when prompted (starts with `sk-`)

### Step 5 — Add Provider to config.yaml

Ensure `~/.config/goose/config.yaml` contains:

```yaml
providers:
  custom_maas:
    enabled: true
    model: gpt-oss-120b
    configured: true
```

### Step 6 — Activate the Provider

```yaml
active_provider: custom_maas
```

### Step 7 — Verify

```bash
grep -A3 'custom_maas' ~/.config/goose/config.yaml
grep 'active_provider' ~/.config/goose/config.yaml
```

Then test:

```bash
goose run -t "Say hello in one sentence"
```

---

## Recovery Procedure

If the MaaS provider is lost or needs to be recreated:

1. **Copy the JSON file** from this skill's reference into
   `~/.config/goose/custom_providers/custom_maas.json`
2. **Add the provider entry** to `~/.config/goose/config.yaml` under
   `providers:`
3. **Store the API key** via `goose configure` → Configure Providers →
   MaaS (the key starts with `sk-` and is stored in GNOME Keyring)
4. **Set `active_provider: custom_maas`** in config.yaml if desired
5. **Restart Goose**

### Quick Recovery Script

```bash
#!/usr/bin/env bash
# Restore the MaaS custom provider for Goose
set -euo pipefail

PROVIDER_DIR="$HOME/.config/goose/custom_providers"
PROVIDER_FILE="$PROVIDER_DIR/custom_maas.json"

mkdir -p "$PROVIDER_DIR"

cat > "$PROVIDER_FILE" << 'EOF'
{
  "name": "custom_maas",
  "engine": "openai",
  "display_name": "MaaS",
  "description": "Custom MaaS provider",
  "api_key_env": "CUSTOM_MAAS_API_KEY",
  "base_url": "https://maas-rhdp.apps.maas.redhatworkshops.io",
  "models": [
    {
      "name": "llama-scout-17b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "gpt-oss-120b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "qwen3-14b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    }
  ],
  "headers": null,
  "timeout_seconds": 300,
  "supports_streaming": true,
  "requires_auth": true,
  "catalog_provider_id": null,
  "base_path": null,
  "env_vars": null,
  "dynamic_models": null,
  "skip_canonical_filtering": false,
  "model_doc_link": null,
  "setup_steps": [],
  "fast_model": null,
  "preserves_thinking": false
}
EOF

echo "✅ MaaS custom provider restored to: $PROVIDER_FILE"
echo ""
echo "Next steps:"
echo "  1. Run 'goose configure' → Configure Providers → MaaS to store API key"
echo "  2. Or manually add to ~/.config/goose/config.yaml:"
echo ""
echo "     providers:"
echo "       custom_maas:"
echo "         enabled: true"
echo "         model: llama-scout-17b"
echo "         configured: true"
echo "     active_provider: custom_maas"
```

---

## Verification Checklist

- [ ] `custom_maas.json` exists in `~/.config/goose/custom_providers/`
- [ ] Default model is `llama-scout-17b` (NOT `gpt-oss-120b` or other reasoning models)
- [ ] `"supports_streaming": false` in provider JSON (required for Desktop)
- [ ] `"reasoning": false` in all model entries
- [ ] `"preserves_thinking": false` in provider
- [ ] `"timeout_seconds": 300` (not `null`)
- [ ] `config.yaml` has `custom_maas` in `providers:` with `enabled: true` and `model: llama-scout-17b`
- [ ] `config.yaml` has `GOOSE_TOOLSHIM: true` (required for tool calls)
- [ ] API key stored in GNOME Keyring (`secret-tool search service goose`)
- [ ] Endpoint reachable: `curl -s -o /dev/null -w "%{http_code}" <base_url>` → 200
- [ ] Auth works: `curl <base_url>/v1/models -H "Authorization: Bearer <key>"` → model list
- [ ] Tool calls work: model calls tools by short names, goose maps them correctly
- [ ] Goose Desktop was restarted after any config changes

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| "Tool 'web_scrape' not found" | `GOOSE_TOOLSHIM` not enabled | Add `GOOSE_TOOLSHIM: true` to `config.yaml` |
| Desktop: tools don't work (any config) | Goose Desktop v1.41 bug with custom OpenAI providers | **Use CLI instead**: `goose run --provider custom_maas` |
| Desktop: response generated but not shown/saved | `supports_streaming: true` in provider JSON | Set `"supports_streaming": false` (partial mitigation; tools still won't work) |
| Empty/dead session, 0 output tokens, only thinking shown | Using a reasoning model (`gpt-oss-120b`, `qwen3-14b`) | **Switch to `llama-scout-17b`** |
| Raw `<\|start_header_id\|>` or `<\|start\|>` text instead of tool call | Desktop + toolshim outputs native Llama format | Use CLI with `GOOSE_TOOLSHIM: true` instead |
| 400: "thinking blocks cannot be modified" | `"preserves_thinking": true` | Set `"preserves_thinking": false` |
| Config changes not taking effect | Goose Desktop not restarted | Close and reopen Goose Desktop; config is read at process start |
| HTTP 401 from MaaS | API key missing or invalid | Store key via `goose configure`; key must start with `sk-` |
| "missing required key CUSTOM_MAAS_API_KEY" | GNOME Keyring locked or key not stored | Re-run `goose configure` → MaaS to store the key |
| MaaS not in provider list | Missing JSON file | Copy `custom_maas.json` to `~/.config/goose/custom_providers/` |
| Timeout on requests | `timeout_seconds` too low or `null` | Set to `300` (5 minutes) |
| Session restore fails | Keyring inaccessible when restoring evicted session | Unlock keyring; re-store key via `goose configure` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 20:06 | v1.3 — **Goose Desktop is incompatible with MaaS** — tool calling fails under all tested Desktop configurations (streaming on/off, toolshim on/off); CLI with `GOOSE_TOOLSHIM: true` is the only working approach; updated Desktop section, troubleshooting |
| 2026-07-06 20:00 | v1.2 — Added `GOOSE_TOOLSHIM: true` requirement; `supports_streaming: false` for Desktop; documented Desktop vs CLI differences |
| 2026-07-06 19:39 | v1.1 — **Breaking**: reasoning models (`gpt-oss-120b`, `qwen3-14b`, `deepseek-r1-*`) are fundamentally incompatible with Goose's OpenAI streaming parser — goose drops tool_calls that follow `reasoning_content` chunks. Changed default model to `llama-scout-17b`. Added all available models to provider JSON. Updated model compatibility matrix, troubleshooting, recovery script. Config settings (`reasoning: false`, `preserves_thinking: false`) are necessary but NOT sufficient for reasoning models. |
| 2026-07-06 19:25 | v1.0 — Initial skill; extracted MaaS-specific content from `goose-litellm-provider`, added critical reasoning model fixes (`reasoning: false`, `preserves_thinking: false`), documented failure modes with evidence from real sessions, API key keyring handling, diagnostic tests |
