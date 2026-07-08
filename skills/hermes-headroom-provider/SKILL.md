# Skill: hermes-headroom-provider

Configure Hermes Agent to use the local Headroom context-optimization proxy as its custom LLM provider, with model discovery and verification.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 22:17 | v1.2 — Added `service_tier: fast` incompatibility warning and troubleshooting; `speed` kwarg rejected by OpenAI-compat transport |
| 2026-07-06 22:06 | v1.1 — Aligned config structure with actual Hermes `providers:` map format (not `custom_providers` list); provider named `headroom-proxy` |
| 2026-07-06 22:00 | v1.0 — Initial skill |

## Traffic Chain

```
Hermes Agent → Headroom Proxy (:8787) → LiteLLM (:4000) → Vertex AI (Claude)
                ↑ context compression        ↑ model routing
```

## Prerequisites

- Hermes Agent installed (`~/.hermes/`)
- Headroom proxy running locally on port 8787 (see skill `headroom-litellm-proxy` to set one up; verify with `headroom-proxy-status` skill)
- LiteLLM proxy running on port 4000 upstream of Headroom

## Procedure

### Step 1: Verify Headroom Proxy Is Running

```bash
systemctl --user status headroom-proxy
curl -s http://127.0.0.1:8787/health | python3 -m json.tool
```

Confirm `status` is `healthy` and `ready` is `true`.
If the proxy is not running, use the `headroom-litellm-proxy` skill to set it up first.

### Step 2: Discover Available Models

Query the Headroom proxy's model list (it forwards to LiteLLM):

```bash
curl -s http://127.0.0.1:8787/v1/models | python3 -m json.tool
```

Record all model IDs returned. These will be available to Hermes.

### Step 3: Configure via `hermes model` CLI

Run the interactive model setup:

```bash
hermes model
```

Then follow these steps in the wizard:

1. Select **"Custom endpoint (enter URL manually)"**
2. API base URL → `http://127.0.0.1:8787/v1`
3. API key → `sk-headroom` (or press Enter to skip — Headroom doesn't require a real key by default)
4. When it asks about `/v1` — decline if you already included it in the URL
5. API mode → accept the default (auto-detect)
6. Pick a default model from the discovered list

The wizard will:
- Probe the endpoint and confirm the number of available models
- Create a named provider entry (e.g., `headroom-proxy`) under `providers:` in `~/.hermes/config.yaml`
- Set `model.provider` to the new provider name

### Step 4: Verify the Configuration

Check that `~/.hermes/config.yaml` contains:

```yaml
model:
  default: <chosen-model>
  provider: headroom-proxy

providers:
  headroom-proxy:
    api: http://127.0.0.1:8787/v1
    name: Headroom Proxy
    api_key: sk-headroom
    discover_models: true
    default_model: <chosen-model>
```

If `discover_models: true` is missing, add it manually so all proxy models appear in the `/model` picker.

### Step 5: Test from CLI

```bash
hermes chat --oneshot "Say hello in one sentence"
```

Verify the response comes through successfully.

### Step 6: Test from Desktop

1. Launch Hermes Desktop
2. Type `/model` in a chat session
3. Confirm all proxy models are listed and selectable
4. Send a test message

## Manual Configuration (Alternative)

If `hermes model` is unavailable or you prefer direct editing, update `~/.hermes/config.yaml`:

```yaml
model:
  default: <preferred-model>
  provider: headroom-proxy

providers:
  headroom-proxy:
    api: http://127.0.0.1:8787/v1
    name: Headroom Proxy
    api_key: sk-headroom
    discover_models: true
    default_model: <preferred-model>
```

The provider key (`headroom-proxy`) must match the `model.provider` value.
Set `discover_models: true` so all upstream models appear in the `/model` picker.

> **Note:** The existing `litellm-vertex-ai` provider entry can remain — Hermes
> supports multiple providers. Just change `model.provider` to switch between them.

## Important: Disable `service_tier: fast`

If `agent.service_tier` is set to `fast` in `~/.hermes/config.yaml`, Hermes
injects `{"speed": "fast"}` into `request_overrides` for Anthropic models
(e.g., `claude-opus-4-6`). This parameter is only valid on native Anthropic
endpoints — the OpenAI-compatible `chat_completions` transport used by
Headroom passes it directly to `Completions.create()`, which rejects the
unknown `speed` keyword with a `TypeError`.

**Fix:** Before switching to `headroom-proxy`, set `service_tier` to empty
or remove it:

```yaml
agent:
  service_tier:        # empty = disabled
```

Alternatively, toggle it off in a live session with `/fast normal`.

If you switch back to a direct Anthropic provider (e.g., via `litellm-vertex-ai`
with `anthropic_messages` mode), you can safely re-enable `service_tier: fast`.

## Key Difference from `hermes-litellm-provider`

| Setting | hermes-litellm-provider | hermes-headroom-provider |
|---------|------------------------|-------------------------|
| `base_url` | `http://127.0.0.1:4000/v1` | `http://127.0.0.1:8787/v1` |
| `api_key` | `sk-litellm` | `sk-headroom` |
| Context optimization | None | ✅ Automatic compression |
| Upstream path | Hermes → LiteLLM → Vertex AI | Hermes → Headroom → LiteLLM → Vertex AI |

Both use the same upstream models. The Headroom provider adds a
compression layer that reduces token usage on long conversations.

Check compression savings anytime:

```bash
curl -s http://127.0.0.1:8787/stats | python3 -m json.tool
```

## Verification

- [ ] Headroom proxy running and healthy (`curl http://127.0.0.1:8787/health`)
- [ ] `model.provider` in `~/.hermes/config.yaml` is set to `headroom-proxy`
- [ ] `providers.headroom-proxy` entry exists with `api: http://127.0.0.1:8787/v1`
- [ ] `/model` in a Hermes session lists all models from the proxy
- [ ] A test chat returns a valid LLM response
- [ ] `curl http://127.0.0.1:8787/v1/models` matches what Hermes sees

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Completions.create() got an unexpected keyword argument 'speed'` | `agent.service_tier: fast` injects `speed` override; Headroom's OpenAI-compat endpoint rejects it | Set `agent.service_tier:` to empty in config.yaml, or `/fast normal` in session |
| Only 1 model in picker | Missing `discover_models: true` | Add it to the `providers.headroom-proxy` entry |
| "Connection refused" on :8787 | Headroom proxy not running | `systemctl --user start headroom-proxy` |
| Hermes ignores provider | `model.provider` not set to `headroom-proxy` | Check `model.provider` in config.yaml |
| Desktop shows old provider | Cached provider in localStorage | Clear Desktop cache or restart |
| Upstream LiteLLM down | LiteLLM not running | `systemctl --user start litellm-proxy` |
| Want to switch back to direct LiteLLM | — | Use the `hermes-litellm-provider` skill; set `model.provider: litellm-vertex-ai` |
