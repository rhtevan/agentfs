---
name: goose-litellm-provider
description: >
  configure goose litellm, goose litellm provider
platforms: ['linux']
metadata:
  version: "1.11.0"
  model-tier: T3
  tags: [goose, litellm, custom-provider, redhat, configuration]
  related_skills: [litellm-vertex-ai-proxy, litellm-proxy-status, hermes-litellm-provider, goose-maas-provider]
user-invocable: true
disable-model-invocation: false
---

# Configure Goose with a Local LiteLLM Proxy Provider

Set up Goose (CLI and Desktop) to use a **local LiteLLM proxy** as a
custom provider. This covers the **RedHat** provider pattern — a local
LiteLLM proxy backed by Vertex AI Claude models (no auth,
`http://host.containers.internal:4000`).

For remote MaaS (Model as a Service) setup, see the `goose-maas-provider`
skill instead.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- LiteLLM proxy running locally (see skill `litellm-vertex-ai-proxy` to
  set one up); must be accessible at `http://host.containers.internal:4000` (default
  LiteLLM port)
- Use skill `litellm-proxy-status` to verify the proxy is healthy before
  proceeding

## Model Selection Architecture

Goose uses two separate model settings for this provider. They are
independent — neither overwrites the other.

| Setting | Where | Purpose |
|---|---|---|
| **Default model** | `config.yaml` → `providers.custom_redhat.model` | Main conversation model. `restore.sh` sets it to the strongest served model (`litellm default model`: opus > sonnet > haiku, newest first) |
| **Fast model** | `custom_redhat.json` → `fast_model` | Lightweight model for auxiliary calls (tool-selection, classification, session titles) |

## Reference Configuration

The custom provider is defined as a JSON file under
`~/.config/goose/custom_providers/` with a matching entry in
`~/.config/goose/config.yaml`.

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_redhat.json`

> ⚠️ **Use this exact schema.** Do NOT write from memory or
> improvise field names. Prefer `scripts/restore.sh`, which fills the
> `models` array from the **live LiteLLM proxy** (`/model/info`) so it never
> drifts. The three entries below are only an illustration of the schema —
> the real list is whatever the proxy serves (`hey litellm model list`;
> refresh with `hey refresh litellm models`).

```json
{
  "name": "custom_redhat",
  "engine": "openai",
  "display_name": "RedHat",
  "description": "Local LiteLLM proxy to Vertex AI (Claude models)",
  "api_key_env": "",
  "base_url": "http://host.containers.internal:4000",
  "models": [
    {
      "name": "claude-opus-4-6",
      "context_limit": 1000000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-sonnet-4-6",
      "context_limit": 1000000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "claude-haiku-4-5",
      "context_limit": 200000,
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
  "fast_model": "claude-haiku-4-5",
  "preserves_thinking": true
}
```

### config.yaml Provider Entry

```yaml
providers:
  custom_redhat:
    enabled: true
    model: claude-opus-5-5       # default = strongest served model (restore.sh); any served model works
    configured: true
```

### Key Fields Explained

| Field | Value | Why |
|---|---|---|
| `name` | `custom_redhat` | Internal identifier; must match config.yaml |
| `engine` | `openai` | LiteLLM exposes an OpenAI-compatible API |
| `display_name` | `RedHat` | Friendly name shown in provider picker |
| `base_url` | `http://host.containers.internal:4000` | Local LiteLLM proxy address |
| `requires_auth` | `false` | Local LiteLLM proxy does not require an API key |
| `api_key_env` | `""` | No API key environment variable needed |
| `timeout_seconds` | `600` | 10-minute timeout for long-running requests |
| `supports_streaming` | `true` | LiteLLM supports streaming responses |
| `preserves_thinking` | `true` | Pass through Claude thinking blocks |
| `fast_model` | `claude-haiku-4-5` | Lighter model for auxiliary calls (does not affect default model) |
| `models` | (see JSON) | One entry per model served by the proxy, with its real `context_limit` (200K for haiku-4-5/sonnet-4-5/opus-4-5, 1M for 4.6+ and 5.x) |
| `dynamic_models` | `null` | goose fetches `/v1/models` from the proxy at runtime (`null`/`true`) and uses the JSON `models` only as a fallback; `false` = JSON list only. So the proxy's list is authoritative and `models` should mirror it (verify.sh S4) |

---

## Workflow

### Step 1 — Pre-flight Check

Run the verification script to confirm the LiteLLM proxy is running
and see current state:

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/verify.sh
```

If the proxy is not running, start it:

```bash
systemctl --user start litellm-proxy
```

Or use the `litellm-vertex-ai-proxy` skill to set it up from scratch.

### Step 2 — Create the Custom Provider

**Option A — Script (recommended; models list generated from the live proxy):**

Dry run first, then apply only on `DRY_RUN_RESULT=PENDING`:

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh --dry-run   # Current / Changes / DRY_RUN_RESULT
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh             # apply
```

| Flag / env | Effect |
|---|---|
| *(none)* | Default model = strongest served model (`litellm-proxy-status/scripts/models.sh default`) |
| `--default-model M` | Use `M` instead; exits 1 if the proxy does not serve it |
| `--fast-model M` | Fast model (default `claude-haiku-4-5`); exits 1 if not served |
| `--no-default` | Leave `providers.custom_redhat.model` untouched (JSON only) |
| `--dry-run` | Report changes, write nothing |
| `LITELLM_URL`, `GOOSE_CONFIG_DIR` | Proxy URL (default `http://127.0.0.1:4000`), config dir (default `~/.config/goose`) |

Apply behaviour:
- Models are ranked (opus > sonnet > haiku, newest first, so `claude-opus-5-5` precedes `claude-opus-5`).
- A new default is chat-tested through the proxy before it is written.
- `custom_redhat.json` and `config.yaml` get timestamped `.bak.<YYYYmmdd_HHMMSS>` backups.
- Only the `model:` line under `providers.custom_redhat` changes (line-level edit; a YAML post-check restores the backup if anything else differs). `active_provider` is never touched.
- Proxy unreachable: models come from the existing JSON and the default model is left alone.

**Option B — Interactive wizard:**

```bash
goose configure
```

1. Select **Custom Providers** → **Add A Custom Provider**
2. API Type → **OpenAI Compatible**
3. Name → `RedHat`
4. API URL → `http://host.containers.internal:4000`
5. Authentication Required → **No**
6. Available Models → the names from `curl -s localhost:4000/v1/models` (comma-separated)
7. Streaming Support → **Yes**

Then activate: **Configure Providers** → **RedHat** → choose default model.

> **Note:** The interactive wizard does not set `fast_model`. After using
> Option B, manually edit `custom_redhat.json` to add
> `"fast_model": "claude-haiku-4-5"`.

### Step 3 — Verify Configuration

Run the verification script:

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/verify.sh
```

All checks should pass. Alternatively, verify manually:

```bash
grep -A3 'custom_redhat' ~/.config/goose/config.yaml
grep 'active_provider' ~/.config/goose/config.yaml
```

### Step 4 — Test from CLI

```bash
goose run -t "Say hello in one sentence"
```

Verify the response comes through successfully via the LiteLLM proxy.

### Step 5 — Test from Desktop (Optional)

1. Launch Goose Desktop
2. Open Settings → Models
3. Confirm **RedHat** appears as a configured provider
4. Select it and choose a model
5. Send a test message

---

## Recovery Procedure

If the RedHat custom provider is lost (e.g., after a config reset or
reinstall), run the restore script:

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh --dry-run
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh
```

Then follow Step 3 (verify) and Step 4 (test).

---

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | LiteLLM proxy is running with all endpoints healthy | `scripts/verify.sh` checks S1a, S1b |
| S2 | Custom provider JSON exists with correct engine, base_url, models, and fast_model | `scripts/verify.sh` checks S2a–S2e |
| S3 | config.yaml has custom_redhat entry with a default model set | `scripts/verify.sh` checks S3a, S3b |
| S5 | `restore.sh` is idempotent: default = strongest served model, only the custom_redhat `model:` line changes, re-run converges | `restore.sh --dry-run` after apply prints `DRY_RUN_RESULT=CONVERGED` |
| S4 | Provider JSON models match live LiteLLM models | `scripts/verify.sh` check S4 |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash scripts/verify.sh 2>&1 \| grep S1` | Both S1a and S1b show ✅ |
| T2 | S2 | `bash scripts/verify.sh 2>&1 \| grep S2` | All S2a–S2e show ✅ |
| T3 | S3 | `bash scripts/verify.sh 2>&1 \| grep S3` | Both S3a and S3b show ✅ |
| T4 | S4 | `bash scripts/verify.sh 2>&1 \| grep S4` | S4 shows ✅ |
| T5 | S1–S4 | `bash scripts/verify.sh` | Exit code 0, all checks pass |
| T6 | S2 | `bash scripts/restore.sh && bash scripts/verify.sh` | Restore + verify both succeed |
| T7 | S5 | `bash scripts/restore.sh --dry-run \| grep DRY_RUN_RESULT` (after apply) | `DRY_RUN_RESULT=CONVERGED` |
| T8 | S5 | `bash scripts/restore.sh --dry-run --default-model nope; echo $?` | `1` (unserved model rejected) |

## Gotchas

| # | Issue | Detail |
|:-:|-------|--------|
| 1 | **Desktop provider switch picks `claude-sonnet-4-6`** | Goose Desktop 1.59.0 Switch Model dialog restores a provider's model from `saved_model`, but `goose serve` 1.59.0 never sends that field. Desktop falls back to `kF()`: the first listed model matching `/claude-sonnet-4/`, `/claude-4/`, `/gpt-4o/`, … (Claude 5.x names match none). For Red Hat that is `claude-sonnet-4-6`; on confirm Desktop writes it to `providers.custom_redhat.model` + `active_provider`, overwriting the configured default. Verified 2026-11-13. Workaround: switch via the bottom-bar **Recent** entry (e.g. `claude-opus-5-5 — custom_redhat`), or type the name and pick `Use: "<name>"` before confirming. If Desktop already saved `claude-sonnet-4-6`, `restore.sh` (≥ 1.11.0) resets `providers.custom_redhat.model` to the strongest served model. Same bug affects `gcp_vertex_ai` (see `goose-gcp-provider` gotcha #8). |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| RedHat not in provider list | Missing JSON file | Run `scripts/restore.sh` |
| "Connection refused" | LiteLLM proxy not running | `systemctl --user start litellm-proxy` |
| Provider shows but won't connect | `base_url` wrong | Verify `http://host.containers.internal:4000` is correct |
| Only 1 model available | Models not listed in JSON | Run `scripts/restore.sh` to regenerate |
| Config lost after update | Goose config reset | Run `scripts/restore.sh` |
| Timeout on long requests | `timeout_seconds` too low | Edit JSON, increase from 600 |
| Switching to Red Hat in Desktop selects `claude-sonnet-4-6` | Gotcha #1 (`saved_model` not sent by goose serve) | Use the Recent entry or type the model name in the switcher; already saved → `scripts/restore.sh` (resets the default), then restart Desktop |


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
