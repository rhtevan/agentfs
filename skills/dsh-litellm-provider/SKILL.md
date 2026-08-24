---
name: dsh-litellm-provider
description: >
  configure dsh litellm, dsh litellm provider,
  dsh custom provider
platforms: ['linux']
writes-files: true
metadata:
  author: agentfs
  version: "1.1.0"
  tags: [dsh, deepseek-harness, litellm, custom-provider, configuration]
  related_skills: [dsh-setup, litellm-vertex-ai-proxy, litellm-proxy-status]
user-invocable: true
disable-model-invocation: false
---

# Configure DSH with Local LiteLLM Proxy Provider

Set up DeepSeek Harness to use a **local LiteLLM proxy** as a custom
OpenAI-compatible provider. This writes the provider configuration to
DSH's `settings.yaml` so the Claude models served by LiteLLM (via
Vertex AI) are available as model routes in the DSH WebUI.

For DSH installation, see the `dsh-setup` skill first.

## Prerequisites

- DSH installed and launchable (see skill `dsh-setup`)
- LiteLLM proxy running locally at `http://127.0.0.1:4000`
  (see skill `litellm-vertex-ai-proxy` to set one up)
- Use skill `litellm-proxy-status` to verify the proxy is healthy
  before proceeding

## Architecture

DSH stores settings in `~/.dsh/settings.yaml` (or `$DSH_HOME/settings.yaml`).
The `llm-pi-ai` plugin manages model providers. A custom provider needs:

| Field | Purpose |
|-------|----------|
| `baseURL` | LiteLLM endpoint: `http://127.0.0.1:4000/v1` |
| `api` | Protocol: `openai-completions` |
| `apiKeyEnv` | Env var holding a dummy API key (DSH requires non-empty) |
| `models` | List of model IDs matching LiteLLM's `model_name` entries |
| `compat` | Protocol compatibility flags for LiteLLM |

## Reference Configuration

**File:** `~/.dsh/settings.yaml` (relevant section)

> ⚠️ **Use this exact schema.** Do NOT write from memory or
> improvise field names. Copy this template and substitute only
> the marked placeholders.

```yaml
llm-pi-ai:
  providers:
    litellm-vertex-ai:
      apiKeyEnv: LITELLM_VERTEX_AI_API_KEY
      api: openai-completions
      baseURL: http://127.0.0.1:4000/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: claude-opus-4-6
          input: [text, image]
        - id: claude-sonnet-4-6
          input: [text, image]
        - id: claude-haiku-4-5
          input: [text, image]
```

### Compatibility Flags

| Flag | Value | Why |
|------|-------|-----|
| `supportsDeveloperRole` | `false` | LiteLLM proxies `role: "developer"` as-is but Vertex AI Claude doesn't accept it. Forcing `false` makes DSH send `role: "system"` instead. |
| `maxTokensField` | `max_tokens` | LiteLLM uses the OpenAI `max_tokens` field, not `max_completion_tokens`. |

### Image Input

All three Claude models support vision. The `input: [text, image]`
declaration on each model tells DSH to allow image attachments in the
WebUI for those models.

## Steps

### Setup

1. **Run the setup script**
   ```bash
   bash ~/.agents/skills/dsh-litellm-provider/scripts/setup.sh
   ```
   This script:
   - Verifies LiteLLM proxy is reachable at `http://127.0.0.1:4000`
   - Queries LiteLLM's `/v1/models` endpoint to discover available models
   - Writes (or merges) the provider block into `~/.dsh/settings.yaml`
   - Backs up the existing settings file before modifying

2. **Verify the configuration**
   ```bash
   bash ~/.agents/skills/dsh-litellm-provider/scripts/verify.sh
   ```

3. **Test in DSH** — launch DSH (via `dsh-launcher` or the desktop
   entry), open Settings → Models, and confirm the `litellm-vertex-ai`
   provider appears with the expected models.

### Restore (after DSH update)

DSH updates may reset `settings.yaml`. Re-run setup:

```bash
bash ~/.agents/skills/dsh-litellm-provider/scripts/setup.sh
```

The script is idempotent — it detects an existing provider block and
updates it in place.

## Gotchas

- **`~/.dsh/` is created on first DSH launch.** If you run this skill
  before ever launching DSH, the directory won't exist. The setup
  script creates it if missing.
- **Model IDs must match exactly** between LiteLLM's `config.yaml`
  (`model_name`) and this provider's `models[].id`. The setup script
  auto-discovers them from the running proxy.
- **Dummy API key required.** The local LiteLLM proxy has no
  authentication, but DSH rejects providers with an empty API key.
  The setup script exports `LITELLM_VERTEX_AI_API_KEY=sk-litellm-local-no-auth`
  as a dummy value and sets `apiKeyEnv: LITELLM_VERTEX_AI_API_KEY`.
  The env var must be set in the shell environment where DSH launches
  (the `dsh-launcher` script handles this automatically).
- **`supportsDeveloperRole: false` is critical.** Without this flag,
  DSH sends `role: "developer"` for system prompts, which Vertex AI
  Claude rejects through LiteLLM.
- **Settings format may change.** DSH is in developer preview. The
  `llm-pi-ai` plugin's settings schema could change across versions.
  The setup script includes a version check and warns if the expected
  structure is missing.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|----------------|
| S1 | Write LiteLLM provider to `~/.dsh/settings.yaml` | `verify.sh` checks provider block exists |
| S2 | Auto-discover models from running LiteLLM proxy | `setup.sh` queries `/v1/models` and populates model list |
| S3 | Idempotent — re-running setup updates in place | Run `setup.sh` twice, `settings.yaml` has no duplicates |
| S4 | Backup existing settings before modification | `.dsh/settings.yaml.bak` created |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `bash scripts/verify.sh` | Provider block found with correct baseURL |
| T2 | S2 | `bash scripts/setup.sh && grep 'claude-' ~/.dsh/settings.yaml` | Model IDs match LiteLLM output |
| T3 | S3 | `bash scripts/setup.sh && bash scripts/setup.sh && grep -c 'litellm-vertex-ai' ~/.dsh/settings.yaml` | Count is 1 (no duplicates) |
| T4 | S4 | `bash scripts/setup.sh && ls ~/.dsh/settings.yaml.bak` | Backup exists |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
