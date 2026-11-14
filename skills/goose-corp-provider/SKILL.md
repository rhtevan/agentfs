---
name: goose-corp-provider
description: >
  configure goose corp, goose corp provider, corp model provider,
  rotate corp key, corp status
argument-hint: "setup | rotate-key | status | list-models"
metadata:
  author: agentfs
  version: "1.0.0"
  model-tier: T2
  tags: [goose, corp, custom-provider, redhat, model-service]
  related_skills: [goose-maas-provider, goose-litellm-provider, goose-skupper-provider]
user-invocable: true
disable-model-invocation: false
---

# Configure Goose with Red Hat Corp Model Service

Set up Goose to use the Red Hat Corp model service
(`models.corp.redhat.com`) as a custom provider. The service hosts
open-weight models (Granite, Qwen, DeepSeek, Nemotron, etc.) and
proxies external models (Claude, Gemini) behind a unified
OpenAI-compatible API with bearer-token authentication.

API keys rotate every 30 days. This skill handles initial setup,
key rotation, model discovery, and status checks. The API key is
stored in GNOME Keyring via `goose configure` — it never enters a
goose session or touches a file under version control.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0.0 |
| **Trigger** | `hey setup corp provider`, `hey rotate corp key`, `hey corp status` |
| **Dependencies** | `goose`, `curl`, `jq`, `secret-tool` (GNOME Keyring) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Discover available models from Corp endpoint | `scripts/probe-models.sh` returns model list |
| S2 | Create custom_corp provider JSON and config.yaml entry | `scripts/setup.sh` writes files, `jq` validates JSON |
| S3 | Store API key securely in GNOME Keyring | `scripts/check-key.sh` confirms key presence |
| S4 | Validate API key against live endpoint | `scripts/test.sh` gets HTTP 200 on chat completion |
| S5 | Rotate API key without entering goose session | `scripts/store-key.sh` (user-run) stores new key |
| S6 | List currently configured models | `scripts/probe-models.sh` outputs model table |

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

Do NOT ask the user for their API key in the goose session.
The key MUST be stored out-of-band via `goose configure` or
`store-key.sh`. Asking for the key in-session leaks it to
conversation history and the LLM provider.

## Prerequisites

- Goose installed (`goose` CLI or Goose Desktop)
- Network access to `https://models.corp.redhat.com` (Red Hat VPN)
- GNOME Keyring available (`secret-tool` command works)
- `jq` installed (`which jq`)

---

## Operation: `setup`

Full initial setup of the Corp provider for Goose.

### Step 1 — Verify Endpoint Connectivity

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/probe-models.sh --check
```

Exit 0 means the endpoint is reachable. Exit 1 means network
failure — the user likely needs VPN.

### Step 2 — Discover Available Models

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/probe-models.sh
```

Read the output. Present the model list to the user and confirm
which model to set as default. Recommend a chat-capable model
(not embedding or reranker models).

### Step 3 — Create Provider Configuration

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/setup.sh --model MODEL_ID
```

Replace `MODEL_ID` with the user's chosen default model.
The script writes `custom_corp.json` and patches `config.yaml`.

### Step 4 — Store API Key (🔒 Out-of-Band Gate)

The API key must be stored outside this goose session.

**Agent action:** Instruct the user to open a **separate terminal**
and run:

    goose configure

Then select Configure Providers → Corp → enter the API key when
prompted.

**Gate condition:** User confirms they have completed the step.

**Verification:**

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/check-key.sh
```

Exit 0 means the key is present. Exit 1 means the key was not
stored — repeat the gate.

### Step 5 — Validate End-to-End

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/test.sh
```

Exit 0 means a chat completion succeeded. The Corp provider is
ready. Instruct the user to restart Goose to activate the new
provider.

---

## Operation: `rotate-key`

API keys expire every 30 days. Rotation does not require a goose
session.

### Step 1 — Instruct User to Rotate

**Agent action:** Instruct the user to run the following in a
**separate terminal** (not in this goose session):

    bash ~/.agents/skills/goose-corp-provider/scripts/store-key.sh

The script prompts for the new key, validates it against the
Corp endpoint, and stores it in GNOME Keyring. It is the only
script in this skill that is interactive — it is designed to be
run directly by the user, never by the agent.

**Gate condition:** User confirms the script exited successfully.

### Step 2 — Verify

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/check-key.sh
```

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/test.sh
```

Both must exit 0.

---

## Operation: `status`

Quick health check of the Corp provider configuration.

### Step 1 — Run Status Checks

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/check-key.sh
```

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/test.sh
```

Report results. If either fails, guide the user through the
appropriate fix (rotate-key for auth failures, setup for missing
config).

---

## Operation: `list-models`

### Step 1 — Query Available Models

```bash
bash ~/.agents/skills/goose-corp-provider/scripts/probe-models.sh
```

Present the model list to the user.

---

## Reference Configuration

### Custom Provider JSON

**File:** `~/.config/goose/custom_providers/custom_corp.json`

> ⚠️ **Use this exact schema.** Do NOT write from memory or
> improvise field names. The `setup.sh` script generates this
> file — do not create it manually.

### config.yaml Provider Entry

```yaml
providers:
  custom_corp:
    enabled: true
    model: <default-model>
    configured: true
```

---

## Output Contract

All scripts output structured diagnostics:
- `✅` prefix for success conditions
- `❌` prefix for failure conditions
- `⚠️` prefix for warnings
- Exit codes follow the Error Contract (0/1/2/3)

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `probe-models.sh` | ✅ (read-only) | Network error — check VPN. |
| `setup.sh` | ✅ | Backs up existing files. Safe to retry. |
| `check-key.sh` | ✅ (read-only) | Key missing — run `goose configure`. |
| `test.sh` | ✅ (read-only) | Auth failure — rotate key. Network failure — check VPN. |
| `store-key.sh` | ✅ | User-run only. Validates before storing. |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `probe-models.sh` exit 1 "connection refused" | Not on VPN | Connect to Red Hat VPN |
| `check-key.sh` exit 1 "not found in keyring" | Key not stored | Run `goose configure` → Corp |
| `test.sh` exit 1 "HTTP 401" | Key expired or invalid | Run `store-key.sh` to rotate |
| `test.sh` exit 1 "HTTP 403" | Key lacks permissions | Get a new key from the Corp portal |
| Corp not in `goose configure` menu | `custom_corp.json` missing | Re-run `setup.sh` |
| "missing required key CUSTOM_CORP_API_KEY" | Keyring locked | Unlock GNOME Keyring, re-run `goose configure` |
| Model returns empty response | Model not available/loaded | Try a different model from `probe-models.sh` |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
