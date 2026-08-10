---
name: goose-litellm-provider
description: "Configure Goose to use a local LiteLLM proxy as a custom provider, with model discovery and verification"
platforms: [linux]
user-invocable: true
disable-model-invocation: false
metadata:
  version: "1.6.0"
  tags: [goose, litellm, custom-provider, redhat, configuration]
  signals: ["goose litellm", "configure goose litellm", "redhat provider"]
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

## Model Selection Architecture

Goose uses two separate model settings for this provider. They are
independent — neither overwrites the other.

| Setting | Where | Purpose |
|---|---|---|
| **Default model** | `config.yaml` → `providers.custom_redhat.model` | Main conversation model |
| **Fast model** | `custom_redhat.json` → `fast_model` | Lightweight model for auxiliary calls (tool-selection, classification, session titles) |

## Reference Configuration

The custom provider is defined as a JSON file under
`~/.config/goose/custom_providers/` with a matching entry in
`~/.config/goose/config.yaml`.

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_redhat.json`

> ⚠️ **Use this exact schema.** Do NOT write from memory or
> improvise field names. Copy this template and substitute only
> the marked placeholders.

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
    model: claude-opus-4-6       # default model for conversation
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
| `fast_model` | `claude-haiku-4-5` | Lighter model for auxiliary calls (does not affect default model) |
| `models` | (see JSON) | One entry per model with 128K context limit |

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

**Option A — Script (recommended):**

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh
```

Optionally override defaults:

```bash
bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh \
  --default-model claude-opus-4-6 \
  --fast-model claude-sonnet-4-6
```

**Option B — Interactive wizard:**

```bash
goose configure
```

1. Select **Custom Providers** → **Add A Custom Provider**
2. API Type → **OpenAI Compatible**
3. Name → `RedHat`
4. API URL → `http://localhost:4000`
5. Authentication Required → **No**
6. Available Models → `claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5`
7. Streaming Support → **Yes**

Then activate: **Configure Providers** → **RedHat** → choose default model.

> **Note:** The interactive wizard does not set `fast_model`. After using
> Option B, manually edit `custom_redhat.json` to add
> `"fast_model": "claude-sonnet-4-6"`.

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

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| RedHat not in provider list | Missing JSON file | Run `scripts/restore.sh` |
| "Connection refused" | LiteLLM proxy not running | `systemctl --user start litellm-proxy` |
| Provider shows but won't connect | `base_url` wrong | Verify `http://localhost:4000` is correct |
| Only 1 model available | Models not listed in JSON | Run `scripts/restore.sh` to regenerate |
| Config lost after update | Goose config reset | Run `scripts/restore.sh` |
| Timeout on long requests | `timeout_seconds` too low | Edit JSON, increase from 600 |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-10 15:39 | v1.6.0 — Removed claude-sonnet-4-5; fixed context_limit (opus/sonnet: 1M, haiku: 200k); fixed config.yaml default model to claude-opus-4-6 |
| 2026-08-10 15:25 | v1.5.0 — Added claude-haiku-4-5 to models; changed fast_model from claude-sonnet-4-6 to claude-haiku-4-5; updated Vertex AI region from global to us-east5 in LiteLLM config |
| 2026-08-10 12:55 | v1.4.0 — Removed pyyaml dependency from verify.sh (replaced with awk); consolidated Steps 1-2 (inline curl commands) into single pre-flight check using verify.sh; renumbered steps (6→5); 5-principle skill check clean |
| 2026-08-10 10:38 | v1.3.0 — Set fast_model to claude-sonnet-4-6; added Model Selection Architecture section; added scripts/verify.sh and scripts/restore.sh; added Specification and Tests sections; consolidated workflow steps; added defensive template warning; added user-invocable and disable-model-invocation to frontmatter; normalized changelog versions |
| 2026-07-06 19:25 | v1.2.0 — Removed MaaS content (moved to dedicated `goose-maas-provider` skill); restored as local-proxy-only; updated description, tags, and related_skills |
| 2026-07-06 19:14 | v1.1.0 — Added MaaS remote provider config (now removed) |
| 2026-07-06 18:04 | v1.0.0 — Initial skill, capturing RedHat custom provider configuration |
