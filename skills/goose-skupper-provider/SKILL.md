---
name: goose-skupper-provider
description: >
  Configure Goose to use a Skupper VAN model endpoint as a custom provider,
  exposing remote GPU-hosted models via localhost:8000. Supports setup
  (default) and teardown capabilities.
metadata:
  version: "1.1.0"
  tags: [goose, provider, skupper, van, remote-model]
  signals:
    - "skupper provider"
    - "skupper model provider"
    - "goose skupper"
    - "van provider"
    - "remote model provider"
    - "remove skupper provider"
    - "teardown skupper provider"
---

# goose-skupper-provider

Configure Goose to use a Skupper VAN model endpoint as a custom provider, exposing remote GPU-hosted models via localhost:8000

## Capabilities

| Capability | Description | Default |
|------------|-------------|---------|
| **setup** | Configure Goose to use the Skupper VAN model endpoint | ✅ |
| **teardown** | Remove the Skupper provider configuration from Goose | |

## Usage

- `goose skupper provider` → runs **setup** (default)
- `goose skupper provider setup` → runs **setup** explicitly
- `remove skupper provider` / `teardown skupper provider` → runs **teardown**

## Steps

### Determine capability

Parse the user's request to determine which capability to run:
- If the user says "teardown", "remove", "delete", "undo", or "clean up" → **teardown**
- Otherwise → **setup** (default)

### Setup (default)

1. **Read the provider configuration instructions**
   ```
   load_skill(name: "goose-skupper-provider/PROVIDER.md")
   ```

2. **Follow PROVIDER.md § Setup** — it contains the full procedure for:
   - Verifying the Skupper VAN link is active
   - Discovering available models on the remote endpoint
   - Configuring Goose to use the Skupper-exposed model as a custom provider
   - Testing the provider connection

### Teardown

1. **Read the provider configuration instructions**
   ```
   load_skill(name: "goose-skupper-provider/PROVIDER.md")
   ```

2. **Follow PROVIDER.md § Teardown** — it contains the full procedure for:
   - Identifying the Skupper provider block in Goose profiles.yaml
   - Removing the provider configuration
   - Verifying the removal

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-04 | v1.1.0 — Added setup/teardown capabilities with setup as default; teardown removes Skupper provider block from Goose profiles.yaml |
| 2025-07-05 | v1.0.0 — Initial skill — configure Goose to use a Skupper VAN model endpoint |
