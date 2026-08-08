# Goose Skupper Provider Configuration

Configure Goose (CLI and Desktop) to use a **Skupper VAN model endpoint**
as a custom provider named **Skupper**. The endpoint is served by a
remote GPU host through a Skupper V2 Virtual Application Network
(see `skupper-model-provider` skill).

**Port routing:** The `base_url` port depends on which model is targeted:
- `http://localhost:10000` → rhtevan-work models (g350m, g1b, g8b)
- `http://localhost:9000` → rhel-ai models (g30b-96k, g8b-128k)

Default: `http://localhost:10000` (g350m).

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- Skupper Model Provider running (`skupper model up`) — the local
  endpoint (`http://localhost:10000/v1/...` or `http://localhost:9000/v1/...`
  depending on model) must be reachable
- Use `skupper model status` to verify before proceeding

## Reference Configuration

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_skupper.json`

> ⚠️ **ALWAYS use this exact schema.** Do NOT improvise or write from
> memory. The field names are Goose-specific (`api_key_env`,
> `requires_auth`, `timeout_seconds`, `display_name`, etc.) — they
> are NOT standard OpenAI fields. Omitting or renaming fields will
> break Goose Desktop provider discovery.

```json
{
  "name": "custom_skupper",
  "engine": "openai",
  "display_name": "Skupper",
  "description": "Skupper VAN to remote GPU model (IBM Granite via vLLM)",
  "api_key_env": "",
  "base_url": "http://localhost:<PORT>",
  "models": [
    {
      "name": "<MODEL_NAME>",
      "context_limit": "<CONTEXT_LIMIT>",
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
  "requires_auth": false,
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

**Template substitutions** — resolve from the Model-to-Port Routing table:

| Placeholder | Example (g350m) | Example (g8b-128k) |
|-------------|-----------------|---------------------|
| `<PORT>` | 10000 | 9000 |
| `<MODEL_NAME>` | ibm-granite/granite-4.0-350m | ibm-granite/granite-4.1-8b |
| `<CONTEXT_LIMIT>` | 2048 | 131072 |

### config.yaml Provider Entry

```yaml
providers:
  custom_skupper:
    enabled: true
    model: <MODEL_NAME>    # e.g., ibm-granite/granite-4.1-8b
    configured: true
```

### Key Fields Explained

| Field | Value | Why |
|---|---|---|
| `name` | `custom_skupper` | Internal identifier; must match config.yaml |
| `engine` | `openai` | vLLM/llama.cpp expose an OpenAI-compatible API |
| `display_name` | `Skupper` | Friendly name shown in provider picker |
| `base_url` | `http://localhost:10000` or `http://localhost:9000` | Skupper VAN listener endpoint (port depends on model alias) |
| `requires_auth` | `false` | No API key needed for local endpoint |
| `api_key_env` | `""` | No API key environment variable needed |
| `timeout_seconds` | `300` | 5-minute timeout (small models respond fast) |
| `supports_streaming` | `true` | vLLM and llama.cpp support streaming |
| `preserves_thinking` | `false` | Granite models don't produce thinking blocks |
| `context_limit` | varies | 2048 for g350m/g1b, 16384 for g8b, 98304 for g30b-96k, 131072 for g8b-128k |

### Model Reference

The model listed in the JSON depends on which model is currently
running on the remote host via `skupper-model-provider`:

| Alias | Model ID | Context Limit | Engine | Port |
|-------|----------|:-------------:|--------|:----:|
| g350m | `ibm-granite/granite-4.0-350m` | 2048 | vLLM | 10000 |
| g1b | `ibm-granite/granite-4.0-1b` | 2048 | vLLM | 10000 |
| g8b | `ibm-granite/granite-4.1-8b` | 16384 | llama.cpp | 10000 |
| g30b-96k | `ibm-granite/granite-4.1-30b` | 98304 | vLLM | 9000 |
| g8b-128k | `ibm-granite/granite-4.1-8b` | 131072 | vLLM | 9000 |

To update the provider when switching models, run `skupper model status`
to get the current model ID, then update the `models` array,
`base_url` port, and `config.yaml` model entry accordingly.

---

## Setup

### Step 1 — Verify Skupper Model Provider Is Running

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh model-provider <REMOTE_SSH_HOST>
```

Or quick check:

```bash
# Use the port matching the target model (10000 for rhtevan-work, 9000 for rhel-ai)
PORT=10000  # or 9000 for rhel-ai models
curl -s http://localhost:${PORT}/v1/models | python3 -m json.tool
```

Should return HTTP 200 with the model list.

### Step 2 — Discover the Active Model

```bash
curl -s http://localhost:${PORT}/v1/models | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data['data']:
    print(f\"  {m['id']}  (max_model_len: {m.get('max_model_len', 'unknown')})\")
"
```

Record the model ID and context limit for the JSON config.

### Step 3 — Create the Custom Provider JSON

```bash
mkdir -p ~/.config/goose/custom_providers
```

Write the JSON file from the [Reference Configuration](#custom-provider-json)
section, substituting the model ID and context limit from Step 2.

### Step 4 — Update config.yaml

Add the provider entry to `~/.config/goose/config.yaml` under `providers:`.
Set `active_provider: custom_skupper` if this should be the default.

### Step 5 — Verify

```bash
grep -A3 'custom_skupper' ~/.config/goose/config.yaml
```

Expected:

```
  custom_skupper:
    enabled: true
    model: ibm-granite/granite-4.0-1b
    configured: true
```

### Step 6 — Test from CLI

```bash
goose run -t "Say hello in one sentence"
```

### Step 7 — Test from Desktop (Optional)

1. Launch Goose Desktop
2. Open Settings → Models
3. Confirm **Skupper** appears as a configured provider
4. Select it and choose the model
5. Send a test message

---

## Teardown

Remove the Skupper provider configuration from Goose so it no longer
points to the VAN model endpoint.

### Step 1 — Check Current Configuration

Inspect both configuration locations:

```bash
# Custom provider JSON
ls -la ~/.config/goose/custom_providers/custom_skupper.json

# config.yaml provider entry
grep -A3 'custom_skupper' ~/.config/goose/config.yaml
```

Identify all Skupper-related configuration that needs to be removed.

### Step 2 — Remove Custom Provider JSON

```bash
rm -f ~/.config/goose/custom_providers/custom_skupper.json
```

### Step 3 — Remove config.yaml Provider Entry

Remove the `custom_skupper:` block from the `providers:` section in
`~/.config/goose/config.yaml`.

If `active_provider` is set to `custom_skupper`, also remove or change
that setting.

**Ask the user for confirmation before modifying config.yaml.**

### Step 4 — Verify Removal

```bash
# Confirm JSON is gone
ls ~/.config/goose/custom_providers/custom_skupper.json 2>&1

# Confirm config.yaml no longer references skupper
grep -c 'custom_skupper' ~/.config/goose/config.yaml
```

Both checks should show the configuration is removed.

### Step 5 — Confirm Goose Defaults

If the removed provider was the active/default provider, inform the user
that they need to configure a new provider or switch to an existing one.

---

## Recovery Procedure

If the Skupper custom provider is lost:

1. **Ensure Skupper VAN is running** (`skupper model status`)
2. **Copy the JSON file** from this skill's reference into
   `~/.config/goose/custom_providers/custom_skupper.json`
3. **Add the provider entry** to `~/.config/goose/config.yaml`
4. **Restart Goose** — the Skupper provider will be available

---

## Verification Checklist

- [ ] Skupper Model Provider is running (`skupper model status` all green)
- [ ] `custom_skupper.json` exists in `~/.config/goose/custom_providers/`
- [ ] `config.yaml` has `custom_skupper` in `providers:` with `enabled: true`
- [ ] `goose configure` shows **Skupper** in the provider list
- [ ] A test chat returns a valid LLM response
- [ ] `curl http://localhost:<PORT>/v1/models` returns the expected model (10000 or 9000)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Skupper not in provider list | Missing JSON file | Copy `custom_skupper.json` to `~/.config/goose/custom_providers/` |
| "Connection refused" | Skupper VAN not running | Run `skupper model up` |
| Provider shows but won't connect | Model container not started | Check `skupper model status`, restart if needed |
| Timeout on requests | Model loading slowly | Increase `timeout_seconds`; wait for vLLM warmup |
| Wrong model listed | Model was switched | Update JSON `models` array, `base_url` port, and config.yaml `model` field; or run `recreate skupper provider` |
| Context too short | Using g8b but JSON says 2048 | Update `context_limit` to match model (see Model Reference table) |
| Wrong port | Switched between rhtevan-work and rhel-ai models | Update `base_url` to correct port (10000 or 9000); or run `recreate skupper provider for <alias>` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-08 | v3.1 — Added schema warning to JSON template; templated PORT/MODEL_NAME/CONTEXT_LIMIT fields; added substitution table; incident: agent bypassed skill and wrote invalid JSON with non-Goose fields (auth, default_params) |
| 2026-08-08 | v3.0 — Port update: rhtevan-work on port 10000 (was 8000); routing key model-api-rhtevan-work |
| 2026-08-07 | v2.0 — Multi-port support: base_url port resolved from model alias (10000 for rhtevan-work, 9000 for rhel-ai); added g30b-96k and g8b-128k to model reference |
| 2026-08-04 | v1.1 — Added Teardown section; restructured into Setup/Teardown capabilities |
| 2026-08-04 | v1.0 — Initial provider config: custom_skupper.json, config.yaml entry, model reference, recovery, troubleshooting |
