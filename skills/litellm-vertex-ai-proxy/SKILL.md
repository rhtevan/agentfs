---
name: litellm-vertex-ai-proxy
description: "Set up a local LiteLLM proxy for GCP Vertex AI with systemd auto-start and service account credentials"
version: 1.0.0
platforms: [linux]
metadata:
  tags: [litellm, vertex-ai, gcp, proxy, systemd]
  hermes:
    tags: [litellm, vertex-ai, gcp, proxy, systemd]
    related_skills: []
---

# LiteLLM Proxy for GCP Vertex AI

Set up a local LiteLLM proxy that fronts GCP Vertex AI as an OpenAI-compatible endpoint, managed by systemd, with proper service account credentials.

## Overview

This skill deploys LiteLLM locally as a proxy that:
- Exposes `http://127.0.0.1:4000/v1` (OpenAI-compatible)
- Routes requests to GCP Vertex AI (Anthropic Claude models)
- Uses a GCP service account key (no expiring refresh tokens)
- Auto-starts at boot via a systemd user service

Any AI agent or application that supports OpenAI-compatible endpoints can use this proxy. See agent-specific skills (e.g., `hermes-litellm-provider`) for integration guidance.

## Prerequisites

- Linux with systemd (Fedora, RHEL, Ubuntu, etc.)
- `uv` package manager (check: `which uv` or install from https://docs.astral.sh/uv/)
- A GCP project with Vertex AI API enabled
- A GCP service account key (JSON) with `roles/aiplatform.user` permission
- `python3` available

## Inputs

Gather these from the user or detect from the environment:

1. **GCP Project ID** — check `gcloud config get-value project` or env `ANTHROPIC_VERTEX_PROJECT_ID`
2. **Vertex AI Location** — check env `CLOUD_ML_REGION` (common values: `global`, `us-east5`, `us-central1`)
3. **Service Account Key File** — find candidates:
   ```bash
   find ~/.config/gcloud -name "adc.json" -path "*/legacy_credentials/*" 2>/dev/null
   ```
4. **Models to expose** — discover available models by testing the Vertex AI API

## Workflow

### Step 1: Detect GCP Configuration

Gather credentials and project info from the current environment:

```bash
# Current GCP project
gcloud config get-value project 2>/dev/null

# Vertex AI location
echo $CLOUD_ML_REGION

# Active account
gcloud auth list 2>/dev/null

# Find service account key files
find ~/.config/gcloud/legacy_credentials -name "adc.json" 2>/dev/null
```

For each service account key found, extract metadata (do NOT expose private keys):

```python
import json
with open('<key_file_path>') as f:
    d = json.load(f)
print(f"Type:    {d.get('type')}")
print(f"Email:   {d.get('client_email')}")
print(f"Key ID:  {d.get('private_key_id', '')[:12]}...")
```

### Step 2: Test Service Account Permissions

Verify the service account can call Vertex AI before proceeding:

```python
from google.oauth2 import service_account
import google.auth.transport.requests
import urllib.request, json

SCOPES = ['https://www.googleapis.com/auth/cloud-platform']
creds = service_account.Credentials.from_service_account_file('<key_file>', scopes=SCOPES)
creds.refresh(google.auth.transport.requests.Request())

PROJECT = '<project_id>'
LOCATION = '<location>'  # e.g. 'global'
MODEL = 'claude-sonnet-4-6'

# For location 'global', use bare aiplatform.googleapis.com
# For regional, use {location}-aiplatform.googleapis.com
if LOCATION == 'global':
    host = 'aiplatform.googleapis.com'
else:
    host = f'{LOCATION}-aiplatform.googleapis.com'

url = f'https://{host}/v1/projects/{PROJECT}/locations/{LOCATION}/publishers/anthropic/models/{MODEL}:streamRawPredict'

payload = json.dumps({
    'anthropic_version': 'vertex-2023-10-16',
    'max_tokens': 50,
    'stream': False,
    'messages': [{'role': 'user', 'content': 'Say hello in one sentence.'}]
}).encode()

req = urllib.request.Request(url, data=payload, method='POST', headers={
    'Authorization': f'Bearer {creds.token}',
    'Content-Type': 'application/json',
})

try:
    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())
    text = result['content'][0]['text']
    print(f'✅ Success: {text.strip()}')
except urllib.error.HTTPError as e:
    print(f'❌ HTTP {e.code}: {e.read().decode()[:300]}')
```

If the service account gets 403, it needs the **Vertex AI User** role — ask the user to contact their GCP admin.

### Step 3: Discover Available Models

Test which Claude models are available on the project. Try these models:
- `claude-opus-4-6`
- `claude-sonnet-4-6`
- `claude-sonnet-4-5`

Use the same test from Step 2 for each model. Record which ones return 200.

### Step 4: Install LiteLLM

```bash
uv tool install 'litellm[proxy]'
```

Verify: `litellm --version`

### Step 5: Create LiteLLM Config

Write `~/.config/litellm/config.yaml` with all discovered models:

```yaml
model_list:
  - model_name: <model-name>
    litellm_params:
      model: vertex_ai/<model-name>
      vertex_project: <project_id>
      vertex_location: <location>
  # repeat for each available model

litellm_settings:
  drop_params: true
  request_timeout: 120
```

**Important:** LiteLLM auto-constructs the Vertex AI endpoint URL from `vertex_project` + `vertex_location`. No explicit endpoint URL is needed:
- `global` → `https://aiplatform.googleapis.com`
- Regional (e.g. `us-east5`) → `https://us-east5-aiplatform.googleapis.com`

### Step 6: Create systemd User Service

Write `~/.config/systemd/user/litellm-proxy.service`:

```ini
[Unit]
Description=LiteLLM Proxy - OpenAI-compatible gateway to Vertex AI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=GOOGLE_APPLICATION_CREDENTIALS=<path_to_service_account_key.json>
ExecStart=<path_to_litellm_binary> --config /home/<user>/.config/litellm/config.yaml --host 127.0.0.1 --port 4000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

**Key points:**
- `GOOGLE_APPLICATION_CREDENTIALS` must be set explicitly — systemd does not inherit shell environment
- Use a service account key file, NOT user ADC (refresh tokens expire and can't re-auth interactively)
- Bind to `127.0.0.1` only (localhost) for security
- Use the full absolute path to the `litellm` binary (find with `which litellm`)

### Step 7: Enable and Start

```bash
# Allow user services to run at boot (not just at login)
loginctl enable-linger $(whoami)

# Reload, enable, start
systemctl --user daemon-reload
systemctl --user enable litellm-proxy.service
systemctl --user start litellm-proxy.service

# Verify
systemctl --user status litellm-proxy.service
curl -s http://127.0.0.1:4000/v1/models | python3 -m json.tool
```

## Verification

- [ ] `systemctl --user status litellm-proxy` shows `active (running)`
- [ ] `curl http://127.0.0.1:4000/health` returns healthy status
- [ ] `curl http://127.0.0.1:4000/v1/models` lists all configured models
- [ ] A test completion request returns a valid response:
  ```bash
  curl -s http://127.0.0.1:4000/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"<model-name>","messages":[{"role":"user","content":"Say hello"}],"max_tokens":50}'
  ```

## Management

```bash
systemctl --user status litellm-proxy     # check status
systemctl --user restart litellm-proxy    # restart after config changes
systemctl --user stop litellm-proxy       # stop
journalctl --user -u litellm-proxy -f     # follow logs
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Service fails to start | Wrong binary path | Check `which litellm`, use full path in service file |
| 403 from Vertex AI | SA missing IAM role | Grant `roles/aiplatform.user` to the service account |
| Credentials expire | Using user ADC instead of SA key | Switch to service account key file |
| Port 4000 already in use | Another process on that port | Change port in service file and config |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 14:37 | v1.1 — Made agent-agnostic: removed Hermes-specific config (Step 8), updated description and troubleshooting |
| 2026-06-19 16:11 | v1.0 — Initial skill |
