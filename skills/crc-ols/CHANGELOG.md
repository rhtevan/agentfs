# crc-ols Changelog


| Updated | Change |
|---------|--------|
| 2026-08-17 09:58 | v2.2.0 — Added self-hosted models via Skupper as OLS provider: documented setup pattern (dummy credentials, in-cluster Skupper service URL), added to Provider Types Reference table, added dependency notes for skupper-model-provider and hosted-model-ctl. |
| 2026-07-14 14:50 | v2.1.1 — Fixed `name` field to match directory name (`crc-ols`) per Agent Skills open standard (agentskills.io/specification). |
| 2026-07-14 14:03 | v2.1 — Credential security hardening: replaced --from-literal with file-based secret creation, added security warnings, 401 troubleshooting. Added Keywords/Signals column to Usage table and Cross-Cutting Capabilities section. Validated full add-provider + switch-default workflow against live MaaS LiteLLM endpoint. |
| 2026-07-14 13:26 | v2.0 — Enhanced with multi-provider management: add-provider, list, switch-default, remove-provider operations. Added Provider Types Reference table. |
| 2026-06-19 12:42 | v1.0 — Initial skill |
