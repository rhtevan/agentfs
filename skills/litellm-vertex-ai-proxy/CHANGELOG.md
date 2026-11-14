# litellm-vertex-ai-proxy Changelog


| Updated | Change |
|---------|--------|
| 2026-11-13 19:53 | v3.4.1 — Doc: native gcp_vertex_ai section points to goose-gcp-provider; Doc: native gcp_vertex_ai section now points to goose-gcp-provider skill |
| 2026-11-13 19:39 | v3.4.0 — litellm-vertex-ai-proxy v3.4.0: depend on gcp-vertex-models; refresh-models.sh; dry-run convergence signal; refresh-models.sh: fix summary filter; v3.4.0: depend on gcp-vertex-models; add refresh litellm models workflow (refresh-models.sh); probe-models.sh now deprecated wrapper; Model discovery moved to new gcp-vertex-models skill (dependency); probe-models.sh kept as deprecated wrapper until v4.0.0; new signal refresh litellm models + scripts/refresh-models.sh (dry-run default, preserves live host/port/SA, --apply chat-tests all models); setup.sh --dry-run prints DRY_RUN_RESULT=CONVERGED|PENDING with model/region diff |
| 2026-11-13 13:59 | v3.3.0 — Rewrite probe-models.sh: SA auth via google-auth, publisher catalog candidates, global+regional matrix, 200/429/404/403 states, json/table/names output; setup.sh consumes probe-models.sh JSON: SA auth (no gcloud token), explicit per-model vertex_location, --regions/--prefer flags; Remove stale model table; probe-models.sh as source of truth; document LiteLLM /v1/models semantics; fix gotchas 1/2/8; add native gcp_vertex_ai section; Rewrite probe-models.sh (SA auth, global+regional matrix, publisher catalog, json/table output); setup.sh consumes probe, explicit per-model vertex_location, no gcloud token; SKILL.md drops stale model table, fixes global-region/listing gotchas, documents /v1/models semantics and native gcp_vertex_ai alternative |
| 2026-11-08 22:22 | v3.2.0 — Add Rules section with anti-fabrication; Bump version to 3.2.0; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation |
| 2026-11-05 19:31 | v3.1.2 — Add model-tier to frontmatter |
| 2026-10-26 10:33 | v3.1.2 — Add select-sa.sh: non-interactive SA selection that rejects default compute SA; update workflow Step 1 to use it |
| 2026-10-26 10:25 | v3.1.1 — Add default compute SA guardrails: detect-sa.sh warns, test-sa.sh warns, SKILL.md prereqs block usage |
| 2026-09-09 14:02 | v3.1.0 — Added --host flag to setup.sh for configurable bind address (default 127.0.0.1); verify.sh detects bind address from live service; added Gotcha #8 (loopback blocks container access); documented --host 0.0.0.0 for container/sandbox use cases |
| 2026-08-10 16:44 | v3.0.0 — Extracted all inline execution code to scripts: setup.sh (config + systemd + start), detect-sa.sh (GCP detection), test-sa.sh (SA permission test); SKILL.md now contains only script invocations and reference tables; added Gotcha #7 (setup.sh discovers all models); added T8–T11 tests; workflow reduced from 8 steps to 6 |
| 2026-08-10 16:05 | v2.1.0 — Added Gotchas section: no model listing API, global region 404, region availability, 429 vs 404, context window differences, SA key requirement |
| 2026-08-10 15:45 | v2.0.0 — Updated model list (removed sonnet-4-5, added haiku-4-5); documented us-east5 as explicit region; added scripts/verify.sh and scripts/probe-models.sh; added Specification and Tests; fixed frontmatter |
| 2026-07-06 14:37 | v1.1.0 — Made agent-agnostic: removed Hermes-specific config, updated description and troubleshooting |
| 2026-06-19 16:11 | v1.0.0 — Initial skill |
