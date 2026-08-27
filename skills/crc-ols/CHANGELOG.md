# crc-ols Changelog


| Updated | Change |
|---------|--------|
| 2026-08-27 19:33 | v3.2.0 — Added Skupper provider liveness check to list.sh — probes /v1/models endpoint via CRC router pod and detects model name mismatches or unreachable backends. Added spec S7 and tests T5/T6. |
| 2026-08-27 19:22 | v3.1.0 — Added model validation in switch-provider.sh (prevents runtime 404 from model name mismatch). Added 'switch ols model' signal for within-provider model switching. Added defaultModel mismatch gotcha. |
| 2026-08-27 19:12 | v3.0.0 — Signal refactor: 5 unambiguous signals (install/list/add/switch/remove ols). Added scripts/list.sh, scripts/switch-provider.sh, scripts/remove-provider.sh. Renamed switch-default to switch-provider (provider+model pair). Added Gotchas (6 issues), Specification (6 items), Tests (4 cases). Updated Skupper model naming convention. |
| 2026-08-27 10:29 | v2.2.1 — Fix skupper-model provider model name: granite-4.1-8b → granite-4.1-8b-fp8 to match g8b-fp8-spec-128k profile |
| 2026-08-17 09:58 | v2.2.0 — Added self-hosted models via Skupper as OLS provider: documented setup pattern (dummy credentials, in-cluster Skupper service URL), added to Provider Types Reference table, added dependency notes for skupper-model-provider and hosted-model-ctl. |
| 2026-07-14 14:50 | v2.1.1 — Fixed `name` field to match directory name (`crc-ols`) per Agent Skills open standard (agentskills.io/specification). |
| 2026-07-14 14:03 | v2.1 — Credential security hardening: replaced --from-literal with file-based secret creation, added security warnings, 401 troubleshooting. Added Keywords/Signals column to Usage table and Cross-Cutting Capabilities section. Validated full add-provider + switch-default workflow against live MaaS LiteLLM endpoint. |
| 2026-07-14 13:26 | v2.0 — Enhanced with multi-provider management: add-provider, list, switch-default, remove-provider operations. Added Provider Types Reference table. |
| 2026-06-19 12:42 | v1.0 — Initial skill |
