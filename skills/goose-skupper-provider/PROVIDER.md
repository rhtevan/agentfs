# Goose Skupper Provider Configuration

Configure Goose (CLI and Desktop) to use a **Skupper VAN model endpoint**
as a custom provider named **Skupper**. The endpoint is served by a
remote GPU host through a Skupper V2 Virtual Application Network
(see `skupper-model-provider` skill).

**Port routing:** The `base_url` port depends on which host is targeted:
- `http://localhost:9000` → rhel-ai models (default: `g8b-fp8-spec-128k`)
- `http://localhost:10000` → rhtevan-work models (default: `g3b-16k`)

Default: `http://localhost:9000` (rhel-ai).

## Poison-JSON Safeguard

> ⚠️ **CRITICAL: Goose Desktop loads ALL JSON files in
> `~/.config/goose/custom_providers/`. One malformed file breaks
> ALL providers — not just the broken one. This was discovered in
> a production incident (see knowledge bundle: `agentfs-process-lessons`).**
>
> **NEVER write `custom_skupper.json` manually or via bash heredoc
> interpolation.** Always use `scripts/setup.sh`, which:
> 1. Writes JSON via Python `json.dumps` (guarantees valid JSON)
> 2. Round-trip validates all 22 required fields before writing
> 3. Post-write validates from disk independently
> 4. Restores backup on any validation failure

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- Skupper Model Provider running (`skupper model up`) — the local
  endpoint (`http://localhost:9000/v1/...` or `http://localhost:10000/v1/...`
  depending on host) must be reachable
- Use `skupper model status` to verify before proceeding

## API-Driven Model Discovery

The `setup.sh` script **discovers** the active model from the live
API instead of using a static mapping. This means:

- You don't need to know the model ID or context limit
- The configuration always matches what's actually running
- Switching profiles via `hosted-model-ctl` → re-running `setup.sh`
  picks up the new model automatically

| Host | Port | What `setup.sh` Discovers |
|------|:----:|---------------------------|
| rhel-ai | 9000 | Model ID + context from `/v1/models` (e.g., `ibm-granite/granite-4.1-8b-fp8`, 131072) |
| rhtevan-work | 10000 | Model ID + context from `/v1/models` (e.g., `/models/granite-4.1-3b-Q4_K_M.gguf`, 16384) |

vLLM returns `max_model_len`; llama.cpp returns `meta.n_ctx`. The
script handles both formats.

## Reference Configuration

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_skupper.json`

> ⚠️ **ALWAYS use `setup.sh` to generate this file.** The template
> below is for reference only — it shows all 22 required fields.
> The field names are Goose-specific (`api_key_env`, `requires_auth`,
> `timeout_seconds`, `display_name`, etc.) — they are NOT standard
> OpenAI fields. Omitting or renaming fields will break Goose Desktop
> provider discovery for ALL providers.

```json
{
  "name": "custom_skupper",
  "engine": "openai",
  "display_name": "Skupper",
  "description": "Skupper VAN to remote GPU model (IBM Granite)",
  "api_key_env": "",
  "base_url": "http://localhost:<PORT>",
  "models": [
    {
      "name": "<MODEL_ID>",
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
  "supports_streaming": false,
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

**Template substitutions** — discovered automatically by `setup.sh`:

| Placeholder | Example (rhel-ai) | Example (rhtevan-work) |
|-------------|-------------------|------------------------|
| `<PORT>` | 9000 | 10000 |
| `<MODEL_ID>` | `ibm-granite/granite-4.1-8b-fp8` | `/models/granite-4.1-3b-Q4_K_M.gguf` |
| `<CONTEXT_LIMIT>` | 131072 | 16384 |

### config.yaml Provider Entry

```yaml
providers:
  custom_skupper:
    enabled: true
    model: <MODEL_ID>    # e.g., ibm-granite/granite-4.1-8b-fp8
    configured: true
```

### Key Fields Explained

| Field | Value | Why |
|---|---|---|
| `name` | `custom_skupper` | Internal identifier; must match config.yaml |
| `engine` | `openai` | vLLM/llama.cpp expose an OpenAI-compatible API |
| `display_name` | `Skupper` | Friendly name shown in provider picker |
| `base_url` | `http://localhost:9000` or `http://localhost:10000` | Skupper VAN listener endpoint (port depends on host) |
| `requires_auth` | `false` | No API key needed for local endpoint |
| `api_key_env` | `""` | No API key environment variable needed |
| `timeout_seconds` | `300` | 5-minute timeout for inference |
| `supports_streaming` | `false` | Disabled: goose v1.47.0 streaming parser drops leading chars from vLLM hermes tool-call arguments (see knowledge bundle: goose-desktop-operations) |
| `preserves_thinking` | `false` | Granite models don't produce thinking blocks |
| `context_limit` | varies | Discovered from API: `max_model_len` (vLLM) or `n_ctx` (llama.cpp) |

---

## Setup

### Automated (recommended)

```bash
# Default: rhel-ai (port 9000)
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhel-ai

# Or specify host or profile name
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhtevan-work
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh g8b-fp8-spec-128k
```

The script discovers the model from the live API, writes validated
JSON, updates config.yaml, and runs a chat test.

### Manual (reference only)

> ⚠️ **Use `setup.sh` instead.** This section exists for understanding
> only. Manual JSON editing risks the poison-JSON problem.

#### Step 1 — Verify Skupper Model Provider Is Running

```bash
bash ~/.agents/skills/skupper-model-provider/scripts/status.sh
```

Or quick check:

```bash
# Use the port matching the target host (9000 for rhel-ai, 10000 for rhtevan-work)
PORT=9000
curl -s http://localhost:${PORT}/v1/models | python3 -m json.tool
```

Should return HTTP 200 with the model list.

#### Step 2 — Discover the Active Model

```bash
curl -s http://localhost:${PORT}/v1/models | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data['data']:
    print(f\"  {m['id']}  (max_model_len: {m.get('max_model_len', 'unknown')})\")
"
```

Record the model ID and context limit.

#### Step 3 — Run setup.sh

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhel-ai
```

#### Step 4 — Verify

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/test.sh
```

---

## Teardown

Remove the Skupper provider configuration from Goose.

```bash
bash ~/.agents/skills/goose-skupper-provider/scripts/teardown.sh
```

Backups existing files, removes JSON and config.yaml entry, verifies.

If `custom_skupper` was the active provider, you'll need to configure
a new one.

---

## Recovery Procedure

If the Skupper custom provider is lost:

1. **Ensure Skupper VAN is running** (`skupper model status`)
2. **Run `setup.sh`** — it discovers the model and writes validated JSON:
   ```bash
   bash ~/.agents/skills/goose-skupper-provider/scripts/setup.sh rhel-ai
   ```
3. **Verify** with `test.sh`
4. **Restart Goose** — the Skupper provider will be available

---

## Verification Checklist

- [ ] Skupper Model Provider is running (`skupper model status` all green)
- [ ] `custom_skupper.json` exists in `~/.config/goose/custom_providers/`
- [ ] `config.yaml` has `custom_skupper` in `providers:` with `enabled: true`
- [ ] `goose configure` shows **Skupper** in the provider list
- [ ] A test chat returns a valid LLM response
- [ ] `curl http://localhost:<PORT>/v1/models` returns the expected model

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Skupper not in provider list | Missing JSON file | Run `setup.sh rhel-ai` |
| ALL providers disappeared | Malformed JSON in `custom_providers/` | Check all `.json` files for syntax errors; restore from `.bak` |
| "Connection refused" | Skupper VAN not running | Run `skupper model up` |
| Provider shows but won't connect | Model container not started | Check `hosted-model-ctl status`, start default profile |
| Timeout on requests | Model loading slowly | Increase `timeout_seconds`; wait for vLLM warmup |
| Wrong model listed | Model profile was switched | Re-run `setup.sh` — it discovers the current model from API |
| Context too short | JSON has old context value | Re-run `setup.sh` — it reads `max_model_len`/`n_ctx` from API |
| Wrong port | Switched between hosts | Re-run `setup.sh rhtevan-work` or `setup.sh rhel-ai` |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
