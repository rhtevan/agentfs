# litellm-vertex-ai-proxy Changelog


| Updated | Change |
|---------|--------|
| 2026-08-10 16:44 | v3.0.0 — Extracted all inline execution code to scripts: setup.sh (config + systemd + start), detect-sa.sh (GCP detection), test-sa.sh (SA permission test); SKILL.md now contains only script invocations and reference tables; added Gotcha #7 (setup.sh discovers all models); added T8–T11 tests; workflow reduced from 8 steps to 6 |
| 2026-08-10 16:05 | v2.1.0 — Added Gotchas section: no model listing API, global region 404, region availability, 429 vs 404, context window differences, SA key requirement |
| 2026-08-10 15:45 | v2.0.0 — Updated model list (removed sonnet-4-5, added haiku-4-5); documented us-east5 as explicit region; added scripts/verify.sh and scripts/probe-models.sh; added Specification and Tests; fixed frontmatter |
| 2026-07-06 14:37 | v1.1.0 — Made agent-agnostic: removed Hermes-specific config, updated description and troubleshooting |
| 2026-06-19 16:11 | v1.0.0 — Initial skill |
