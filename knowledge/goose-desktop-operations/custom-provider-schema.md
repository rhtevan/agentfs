---
type: Reference
title: "Goose Desktop Custom Provider JSON Schema"
description: "Required fields, poison-JSON safeguard, and schema validation for custom providers"
tags: [goose, custom-provider, json-schema, poison-json, desktop]
timestamp: 2026-08-26T12:07:00-04:00
---

# Goose Desktop Custom Provider JSON Schema

## How Custom Providers Work

Goose Desktop loads **all** JSON files in
`~/.config/goose/custom_providers/` at startup. Each file defines
a provider with its name, endpoint, models, and configuration.

## Poison-JSON Risk

> ⚠️ **One malformed JSON file breaks ALL providers — not just
> the broken one.** Goose Desktop fails to parse the providers
> directory and all custom providers (MaaS, Red Hat, Headroom,
> Skupper, etc.) disappear from Settings.

This was a production incident (see `skupper-vllm-deployment`
knowledge bundle, Incident 1).

## Required Fields (22)

All custom provider JSON files must contain exactly these fields:

```json
{
  "name": "custom_<name>",
  "engine": "openai",
  "display_name": "<Display Name>",
  "description": "<description>",
  "api_key_env": "",
  "base_url": "http://...",
  "models": [
    {
      "name": "<model-id>",
      "context_limit": 131072,
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

## Common Schema Mistakes

| Wrong (from memory/training) | Correct (Goose-specific) |
|------------------------------|-------------------------|
| `"auth": {"type": "none"}` | `"requires_auth": false` + `"api_key_env": ""` |
| `"default_params": {"timeout": 300}` | `"timeout_seconds": 300` |
| `"name": "Skupper"` | `"name": "custom_skupper"` |
| Missing `display_name` | `"display_name": "Skupper"` |
| Missing null fields | All 22 fields must be present |

## Three-Layer Defense

| Layer | What | How |
|:-----:|------|-----|
| 1 | Generate valid JSON | Python `json.dumps` (never bash heredoc) |
| 2 | Round-trip validation | Parse output back, check all 22 fields |
| 3 | Post-write validation | Read from disk, validate independently, restore backup on failure |

## Rule

> **NEVER write custom provider JSON manually.** Always use the
> skill's `setup.sh` script, which enforces all three layers.
> The `goose-skupper-provider` skill implements this pattern.
