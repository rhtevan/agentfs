---
name: goose-maas-provider
description: >
  configure goose maas, goose maas provider, goose remote provider
platforms: ['linux']
metadata:
  version: "1.6.1"
  model-tier: T4
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
    },
    {
      "name": "qwen36-35b-a3b",
      "context_limit": 128000,
      "input_token_cost": null,
      "output_token_cost": null,
      "currency": null,
      "supports_cache_control": null,
      "reasoning": false
    },
    {
      "name": "deepseek-r1-distill-qwen-14b",
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

### Global Settings — none required

**Do NOT set `GOOSE_TOOLSHIM`.** The scripts never write it and
`verify-config.sh` warns if it is set globally.

Per the official goose docs, `GOOSE_TOOLSHIM` is an *experimental*,
global-only setting for models that emit tool calls as plain text: an
extra **interpreter model** (default: Ollama `mistral-nemo`, or
`GOOSE_TOOLSHIM_BACKEND=local` + `GOOSE_TOOLSHIM_MODEL`) converts that
text into real tool calls. It does **not** rename or strip tool
namespaces (an earlier version of this skill said so — that was wrong).
Enabling it globally would affect every provider and fails without an
interpreter backend.

If a MaaS model turns out to emit text tool calls, either skip that
model or (separate user decision) install Ollama and use it per run:
`GOOSE_TOOLSHIM=true goose run --provider custom_maas ...`.

### Goose Desktop compatibility — retest on 1.60.x

> Findings below were observed on **Goose Desktop v1.41.0** and have
> **not been retested** on the installed v1.60.2. Treat them as history
> until retested.

| Desktop v1.41.0 config | Result |
|---|---|
| `supports_streaming: true` | Response received (tokens counted) but never saved or displayed |
| `supports_streaming: false` | Responses saved; tool calls failed in some sessions |

The provider JSON keeps `"supports_streaming": true` (CLI works with
it). If Desktop on 1.60.x fails to display responses, try `false` and
record the result here.

### Available Models on MaaS

The live list comes from `GET <base_url>/v1/models`; per-model details
(context window, flags) from LiteLLM `GET <base_url>/v1/model/info`.
Do not curl them with the key on the command line — `restore-provider.sh`
and `check-endpoint.sh` use a 0600 header file. Non-chat models (embed,
rerank, guardian, whisper, tts, diffusion) are filtered out.

**The list changes server-side** (e.g. `deepseek-r1-distill-qwen-14b`
and its `openai/` alias disappeared on 2026-11-22). Re-run
`restore-provider.sh` to converge.

**LiteLLM capability flags are unreliable** — `/v1/model/info` and
`/model_group/info` disagree, and were wrong for deepseek (claimed tool
support, has none) and qwen36 (claimed none, works). Only the real
tool-chain test is trusted.

---

## Model Compatibility (goose 1.60.2, tested 2026-11-22)

### Criterion: real tool calls, not `reasoning_content`

The v1.41 finding "goose drops `tool_calls` after `reasoning_content`"
**no longer reproduces on goose 1.60.2**: `gpt-oss-120b` and
`qwen36-35b-a3b` stream reasoning and still drive multi-step tool chains.
What matters is whether the model emits real `tool_calls`.

### Compatibility matrix

| Model | Context (`/v1/model/info`) | `reasoning_content` | Tool-chain test (API, streaming) | In goose CLI (full AgentFS context) |
|---|---|---|---|---|
| `llama-scout-17b` | 400,000 | no | ✅ PASS 4/4 | ✅ works — default |
| `qwen36-35b-a3b` | 16,384 | yes | ✅ PASS 4/4 | ✅ works (small context — compacts often) |
| `qwen3-14b` | 40,960 | thinks inline in `content` | ✅ PASS 4/4 | ✅ works (thinking text visible in replies) |
| `gpt-oss-120b` | 131,072 | yes | ✅ PASS 4/4 | ⚠️ flaky: ~2/7 runs wrote the next tool call inside its reasoning text → turn ends with thinking only. Type "continue". |
| `deepseek-r1-distill-qwen-14b` | 16,384 | yes | ❌ NO_TOOLS | ❌ invented tool output without calling tools (removed from server 2026-11-22) |

`gpt-oss-120b` flakiness is a server-side harmony parsing issue (tool
call left in the analysis channel); it is more frequent with the long
AgentFS system prompt (`~/.config/goose/prompts/system.md`) and after a
failed tool call. Not fixable client-side.

### Provider config requirements

| Setting | Must be | Why |
|---|---|---|
| `"reasoning"` (model) | `false` | Keep false for all MaaS models |
| `"preserves_thinking"` (provider) | `false` | `true` caused 400 errors when resuming sessions (v1.41) |
| `"context_limit"` (model) | server value | Set by `restore-provider.sh` from `/v1/model/info`; too high → goose compacts too late and requests fail |
| Default model | `PASS` in `test-model-compat.sh` | `llama-scout-17b` recommended |

### Diagnostic Test

```bash
bash ~/.agents/skills/goose-maas-provider/scripts/test-model-compat.sh --all [--runs 3]
bash ~/.agents/skills/goose-maas-provider/scripts/test-model-compat.sh --model <model-name>
```

Runs a streaming 2-step tool chain (`shell` → `read_file` → answer)
with simulated tool results — nothing executes locally. Prints
`RESULT <model> PASS|NO_TOOLS|FLAKY|ERROR`. Exit (worst wins): `0` all
PASS · `1` any NO_TOOLS · `5` any FLAKY · `2` error/no key · `3`
keyring locked. Key from the keyring via header file.

`restore-provider.sh` runs `--all` on the live list and **drops
NO_TOOLS models** (FLAKY/ERROR are kept — fail open);
`--skip-tool-check` disables this.

---

## API Key Storage

The MaaS key (`sk-…`) lives in the **GNOME Keyring** inside Goose's
single secrets item (`service=goose username=secrets`), as
`CUSTOM_MAAS_API_KEY` in one JSON map shared with every other goose
key (e.g. `CUSTOM_CORP_API_KEY`). It is **not** an environment
variable and never goes into `config.yaml` or chat.

Goose reads the key only when a provider is built (session start or
provider switch) and caches secrets per process — **restart Goose
Desktop after storing or rotating the key.**

### Storing the Key (user runs it, own terminal)

```bash
bash ~/.agents/skills/goose-maas-provider/scripts/store-key.sh --validate
```

- Checks the keyring lock state over D-Bus first (never triggers an
  unlock prompt); refuses with exit `3` if locked, `4` if the goose
  item exists but is unreadable — it never overwrites a map it could
  not read.
- Shows existing key **names**, prompts hidden, strips whitespace.
- `--validate` (default): `GET /v1/models` via a 0600 header file;
  401/403/unreachable → key **not** saved (exit 1).
- Re-reads the map right before writing, merges, then verifies the new
  key is present **and every previous key survived**.

Alternative: `goose configure` → Configure Providers → MaaS.

### Verifying the Key (names/length only)

```bash
bash ~/.agents/skills/goose-maas-provider/scripts/verify-config.sh
```

Never use `secret-tool search` — it prints secret values.

### Shared helpers — `scripts/lib-keyring.sh`

`keyring_state` (unlocked/locked/unavailable, prompt-free),
`keyring_read_map` / `keyring_get` (rc `0` ok · `1` not set · `3`
locked/unavailable · `4` unreadable; a failed read is never treated as
`{}`), `auth_header_file` (0600 `Authorization` header for `curl -H @file`).

---

## Workflow

### Step 1 — Create / converge the provider (dry run first)

```bash
S=~/.agents/skills/goose-maas-provider/scripts
bash $S/restore-provider.sh --dry-run     # DRY_RUN_RESULT=CONVERGED|PENDING
bash $S/restore-provider.sh               # apply only if PENDING
```

- Writes `custom_maas.json` (atomic, `.bak.<stamp>` only when changed)
  and adds `providers.custom_maas` (line-level insert, `config.yaml`
  backup, YAML post-check with restore on mismatch).
- Never modifies an existing `providers.custom_maas` entry; never
  writes `GOOSE_TOOLSHIM`; `active_provider` changes only with
  `--activate`.
- Model list: live (key in keyring) → existing JSON → static fallback.
- Options: `--url URL` (default: existing `base_url`, else
  `https://maas-rhdp.apps.maas.redhatworkshops.io`), `--model M`
  (default for a new entry `llama-scout-17b`; must be in the list),
  `--force`, `--activate`. Env `GOOSE_CONFIG_DIR`.

### Step 2 — Store the key (user)

Run `store-key.sh --validate` (see above) in your own terminal, then
restart Goose Desktop if it is open.

### Step 3 — Check endpoint and auth

```bash
bash $S/check-endpoint.sh
```

Reachability (`401` without key is fine) plus authenticated
`/v1/models`. Exit `3` if keyring locked; key missing → auth skipped.

### Step 4 — Refresh the live model list

Re-run Step 1 (dry run, then apply if PENDING) — with the key present
the JSON gets the live chat-model list, per-model `context_limit` from
`/v1/model/info`, and NO_TOOLS models are excluded (tool check takes
~1 min).

### Step 5 — Test model compatibility

```bash
bash $S/test-model-compat.sh --all --runs 3
```

Pick a compatible default. To change the default of an existing entry,
edit `providers.custom_maas.model` (the script does not modify existing
entries).

### Step 6 — Verify

```bash
bash $S/verify-config.sh
goose run --provider custom_maas -t "Say hello in one sentence"
```

Optional: `restore-provider.sh --activate` to make MaaS the active
provider.

---

## Recovery Procedure

Lost config → run the [Workflow](#workflow) again. `restore-provider.sh`
recreates the JSON and the config entry; the key survives in the
keyring unless the keyring itself was lost (then Step 2).

---

## Verification Checklist

`verify-config.sh` automates most of these:

- [ ] `custom_maas.json` exists in `~/.config/goose/custom_providers/`
- [ ] `api_key_env` is `CUSTOM_MAAS_API_KEY`
- [ ] Configured default model is in the JSON model list and `PASS`es `test-model-compat.sh`
- [ ] `context_limit` per model matches `/v1/model/info` (set by `restore-provider.sh`)
- [ ] `"reasoning": false` in all model entries
- [ ] `"preserves_thinking": false` in provider
- [ ] `"timeout_seconds"` ≥ 60 (300 recommended, not `null`)
- [ ] `config.yaml` has `providers.custom_maas` with `enabled: true`
- [ ] `GOOSE_TOOLSHIM` **not** set globally
- [ ] `CUSTOM_MAAS_API_KEY` present in the keyring (name/length only)
- [ ] `check-endpoint.sh` → reachable + authenticated model list
- [ ] Desktop streaming behaviour retested on 1.60.x (`supports_streaming: true`)
- [ ] Goose Desktop restarted after config or key changes

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Turn ends with only thinking shown (no tool run, no reply) | Model wrote its tool call inside reasoning (seen with `gpt-oss-120b`) | Type "continue", or switch to `llama-scout-17b` |
| Model claims command output without a tool call | Model cannot call tools (NO_TOOLS) | `test-model-compat.sh --all`; re-run `restore-provider.sh` to drop it |
| Context-length error from MaaS on long sessions | `context_limit` higher than the server window | Re-run `restore-provider.sh` (sets it from `/v1/model/info`) |
| Tool calls appear as plain text (e.g. `<\|start_header_id\|>`) | Model emits text tool calls | Skip that model; toolshim + Ollama per run is a separate decision |
| Desktop: response generated but not shown/saved | Observed on v1.41 with `supports_streaming: true` | Retest on 1.60.x; try `false` and record result |
| 400: "thinking blocks cannot be modified" | `"preserves_thinking": true` | Set `"preserves_thinking": false` |
| Config or key changes not taking effect | Goose caches config/secrets per process | Restart Goose Desktop / start a new CLI session |
| 🔒 exit 3 from any script | GNOME Keyring locked or D-Bus unavailable | Unlock (Passwords and Keys → Login → Unlock, or log in) and re-run |
| exit 4 from store-key / check scripts | goose keyring item unreadable as JSON | Scripts refuse to touch it; inspect in Passwords and Keys |
| HTTP 401 from MaaS | Key missing, invalid or expired | `store-key.sh --validate` |
| "missing required key CUSTOM_MAAS_API_KEY" | Key not stored, or keyring locked at provider build | Store key / unlock keyring, then restart Goose |
| MaaS not in provider list | Missing JSON file | `restore-provider.sh` |
| `--model` rejected by restore-provider | Model not in the (live) list | Pick one from the printed list |
| Timeout on requests | `timeout_seconds` too low or `null` | Set to `300` |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
