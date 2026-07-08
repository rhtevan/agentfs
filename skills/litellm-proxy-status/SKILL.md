---
name: litellm-proxy-status
description: "Check the health, configuration, and runtime status of the local LiteLLM proxy service"
version: 1.0.0
platforms: [linux]
metadata:
  tags: [litellm, proxy, status, health, systemd]
  related_skills: [litellm-vertex-ai-proxy, hermes-litellm-provider]
---

# LiteLLM Proxy Status Check

Check the health, configuration, and runtime status of the local LiteLLM proxy.

## Steps

1. **Check systemd service status**
   ```bash
   systemctl --user status litellm-proxy
   ```
   Confirm it shows `active (running)`. Note uptime, memory usage, and PID.

2. **Check health endpoint**
   ```bash
   curl -s http://127.0.0.1:4000/health | python3 -m json.tool
   ```
   Verify all models show as healthy with zero unhealthy endpoints.

3. **List available models**
   ```bash
   curl -s http://127.0.0.1:4000/v1/models | python3 -m json.tool
   ```
   List all model IDs the proxy is serving.

4. **Show configuration**
   ```bash
   cat ~/.config/litellm/config.yaml
   ```
   Display the current model list, project, location, and settings.

5. **Show service configuration**
   ```bash
   cat ~/.config/systemd/user/litellm-proxy.service
   ```
   Display the systemd unit including the credentials path and startup command.

6. **Check recent logs** (only if there are issues)
   ```bash
   journalctl --user -u litellm-proxy --no-pager -n 20
   ```

## Report Format

Present a summary table:

| Item | Status |
|---|---|
| Service | active/inactive, uptime |
| Health | healthy/unhealthy endpoint count |
| Models | list of model names |
| Port | 4000 |
| Credentials | service account email from key file |
| Config | ~/.config/litellm/config.yaml |

## Troubleshooting

If the service is not running:
```bash
systemctl --user start litellm-proxy
```

If the service fails to start, check logs:
```bash
journalctl --user -u litellm-proxy --no-pager -n 50
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 16:43 | v1.0 — Initial skill |
