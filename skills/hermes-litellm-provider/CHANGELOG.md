# hermes-litellm-provider Changelog


| Updated | Change |
|---------|--------|
| 2026-11-13 21:07 | v2.5.0 — restore.sh: default = strongest served model (litellm default model), models ranked, dry-run CONVERGED/PENDING, line-level block edit with post-check (no whole-file yaml re-dump), unserved --default-model is an error; doc: default = strongest served model; dry-run → apply workflow; line-level edit described; restore.sh: backup goes to ~/.hermes/backups/config/config.yaml.agentfs.<stamp> (Hermes sweeps config.yaml.bak.<digits> siblings into that dir); doc: backup location in Hermes backups/config dir |
| 2026-11-13 20:55 | v2.4.2 — fix: S4 follows Hermes discovery semantics — models: mapping + discover_models true is metadata (info only); fail only when pinned (discover_models false or list/string models:); doc: models field is per-model metadata, not an allowlist, when discover_models is true; doc: Spec S4 wording matches new check |
| 2026-11-13 20:42 | v2.4.1 — default model claude-opus-4-6 → claude-opus-5 (proxy models still discovered from /v1/models); doc: reference config examples updated to current proxy models (claude-opus-5 default) |
| 2026-11-09 20:34 | v2.4.0 — Add --dry-run flag parsing; Add dry-run exit block with DRY_RUN_RESULT signal before config mutation |
| 2026-11-08 22:21 | v2.3.0 — Add Rules section with anti-fabrication; Bump version to 2.3.0; CNL upgrade: add MUST to Steps 1,3,4; Add trace-lib.sh instrumentation; Add trace-lib.sh instrumentation |
| 2026-11-05 19:31 | v2.2.0 — Add model-tier to frontmatter |
| 2026-08-10 15:39 | v2.2.0 — Removed claude-sonnet-4-5 from reference config |
| 2026-08-10 15:26 | v2.1.0 — Added claude-haiku-4-5 to reference config models; updated LiteLLM Vertex AI region from global to us-east5 |
| 2026-08-10 14:10 | v2.0.0 — Rewrote to match live Hermes config schema (providers: hash, not custom_providers: list); added scripts/verify.sh (11 checks) and scripts/restore.sh (surgical update with backup); added Model Selection Architecture section; added Specification and Tests sections; removed hardcoded dummy api_key; documented hermes model persistence bug; added user-invocable and disable-model-invocation; updated related_skills |
| 2026-06-19 16:38 | v1.0.0 — Initial skill |
