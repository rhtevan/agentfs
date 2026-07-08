---
name: headroom-proxy-status
description: "Check the health, configuration, and runtime status of the local Headroom context-optimization proxy service"
version: 1.1.0
platforms: [linux]
metadata:
  tags: [headroom, proxy, status, health, systemd, compression, context-optimization]
  related_skills: [litellm-proxy-status, goose-litellm-provider]
---

# Headroom Proxy Status Check

Check the health, configuration, and runtime status of the local Headroom context-optimization proxy.

## Steps

1. **Check systemd service status**
   ```bash
   systemctl --user status headroom-proxy
   ```
   Confirm it shows `active (running)`. Note uptime, memory usage, and PID.

2. **Check health endpoint**
   ```bash
   curl -s http://127.0.0.1:8787/health | python3 -m json.tool
   ```
   Verify status is `healthy` and `ready` is `true`. Note the backend,
   optimization mode, and whether memory/learning are enabled.

3. **Check compression stats**
   ```bash
   curl -s http://127.0.0.1:8787/stats | python3 -m json.tool
   ```
   Report the summary: total API requests, compression percentage,
   tokens saved, cost savings, and the primary model in use.

   Key fields to extract from the stats response:
   - `summary.compression.requests_compressed` — how many requests had compression applied
   - `summary.compression.avg_compression_pct` — average compression percentage
   - `summary.compression.total_tokens_removed` — total tokens saved by compression
   - `summary.cost.total_saved_usd` — dollar savings
   - `summary.cost.savings_pct` — savings percentage
   - `config.target_ratio` — the configured compression target (e.g. 0.5 = keep ~50%)
   - `config.min_tokens_to_crush` — minimum token threshold before compression kicks in
   - `config.force_kompress` — whether Kompress is forced on all content
   - `summary.uncompressed_requests` — breakdown of why requests were NOT compressed
     (e.g. `prefix_frozen`, `no_compressible_content`)

4. **Check stats history** (optional, for trend data)
   ```bash
   curl -s http://127.0.0.1:8787/stats-history | python3 -m json.tool
   ```
   Show durable compression history if available.

5. **Show service configuration**
   ```bash
   cat ~/.config/systemd/user/headroom-proxy.service
   ```
   Display the systemd unit including upstream URL, flags, and startup command.

6. **Show Goose custom provider configuration**
   ```bash
   cat ~/.config/goose/custom_providers/custom_headroom.json
   ```
   Display the Goose provider definition (base URL, models, settings).

7. **Check recent logs** (only if there are issues)
   ```bash
   journalctl --user -u headroom-proxy --no-pager -n 20
   ```

## Report Format

Present a summary table:

| Item | Status |
|---|---|
| Service | active/inactive, uptime |
| Health | healthy/unhealthy |
| Version | headroom version |
| Mode | token/cache |
| Upstream | OpenAI API URL (e.g. LiteLLM on :4000) |
| Optimize | enabled/disabled |
| Kompress ML | enabled/disabled (`disable_kompress` field) |
| Target ratio | value (e.g. 0.5 = keep ~50%) or unset |
| Compression | requests compressed, avg compression %, tokens saved |
| Uncompressed reasons | prefix_frozen count, no_compressible_content count |
| Cost savings | USD saved, savings % |
| Port | 8787 |
| Key flags | target-ratio, intercept-tool-results, ccr, rate-limit, memory, etc. |
| Goose provider | custom_headroom — base_url, models |

## Traffic Chain

```
Goose (custom_headroom) → Headroom Proxy (:8787) → LiteLLM (:4000) → Vertex AI (Claude)
                           ↑ context compression        ↑ routing
```

## Troubleshooting

If the service is not running:
```bash
systemctl --user start headroom-proxy
```

If the service fails to start, check logs:
```bash
journalctl --user -u headroom-proxy --no-pager -n 50
```

If health shows unhealthy upstream, verify LiteLLM is running:
```bash
systemctl --user status litellm-proxy
curl -s http://127.0.0.1:4000/health | python3 -m json.tool
```

If Goose cannot connect, verify the provider config:
```bash
cat ~/.config/goose/custom_providers/custom_headroom.json
grep custom_headroom ~/.config/goose/config.yaml
```

If compression is showing 0% despite long conversations:
- Check that `--lossless` is NOT set (it restricts to format-native compaction only)
- Verify `target_ratio` is set (without it, Kompress uses a very conservative auto threshold)
- Check `uncompressed_requests` in stats for why requests were skipped
- Verify `disable_kompress` is `false` in the health config
- Ensure conversations are long enough — `min_tokens_to_crush` (default 500) must be exceeded

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-07 15:54 | v1.1 — Added Kompress ML, target ratio, and uncompressed reasons to report format; expanded compression stats extraction; added compression troubleshooting; removed `--lossless` from key flags example |
| 2026-07-06 21:31 | v1.0 — Initial skill |
