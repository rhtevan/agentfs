# goose-litellm-provider Changelog


| Updated | Change |
|---------|--------|
| 2026-11-13 21:13 | v1.11.0 — restore.sh: default = strongest served model (litellm default model), ranked models (5-5 before 5), dry-run CONVERGED/PENDING with change list, sets providers.custom_redhat.model via line-level edit + post-check + backup, chat test before switching default, --no-default, GOOSE_CONFIG_DIR override; restore.sh: proxy-down run leaves the default model alone; strongest-model lookup only accepted on success and when served; SKILL.md: default = strongest served model (claude-opus-5-5); restore.sh dry-run → apply with flags table and apply behaviour; gotcha #1 now notes restore.sh resets a Desktop-overwritten model; S5/T7/T8 |
| 2026-11-13 20:20 | v1.10.2 — doc: Gotchas section — Desktop 1.59.0 provider switch picks claude-sonnet-4-6 (saved_model bug); troubleshooting row |
| 2026-11-13 19:41 | v1.10.1 — Point model-list reference to litellm model list / refresh litellm models (probe moved to gcp-vertex-models); Doc: model-list pointer now references litellm model list / refresh litellm models (probe moved to gcp-vertex-models) |
| 2026-11-13 14:00 | v1.10.0 — restore.sh generates models array from live LiteLLM /model/info; default model claude-opus-5; Schema example no longer authoritative; document dynamic_models semantics; update default/fast model examples; restore.sh builds models list from live LiteLLM /model/info (real context limits); SKILL.md documents dynamic_models semantics and drops stale 3-model lists |
| 2026-11-09 20:44 | v1.9.0 — Add --dry-run flag parsing; Add dry-run exit block with DRY_RUN_RESULT signal |
| 2026-11-08 22:48 | v1.8.0 — Add Rules, bump to 1.8.0; Add trace-lib.sh; Add trace-lib.sh |
| 2026-11-05 19:31 | v1.7.0 — Add model-tier to frontmatter |
| 2026-09-09 21:27 | vv1.7.0 — Changed base_url from localhost:4000 to host.containers.internal:4000 in restore.sh, verify.sh, and SKILL.md. Enables dual-resolution for host and container environments. |
| 2026-08-10 15:39 | v1.6.0 — Removed claude-sonnet-4-5; fixed context_limit (opus/sonnet: 1M, haiku: 200k); fixed config.yaml default model to claude-opus-4-6 |
| 2026-08-10 15:25 | v1.5.0 — Added claude-haiku-4-5 to models; changed fast_model from claude-sonnet-4-6 to claude-haiku-4-5; updated Vertex AI region from global to us-east5 in LiteLLM config |
| 2026-08-10 12:55 | v1.4.0 — Removed pyyaml dependency from verify.sh (replaced with awk); consolidated Steps 1-2 (inline curl commands) into single pre-flight check using verify.sh; renumbered steps (6→5); 5-principle skill check clean |
| 2026-08-10 10:38 | v1.3.0 — Set fast_model to claude-sonnet-4-6; added Model Selection Architecture section; added scripts/verify.sh and scripts/restore.sh; added Specification and Tests sections; consolidated workflow steps; added defensive template warning; added user-invocable and disable-model-invocation to frontmatter; normalized changelog versions |
| 2026-07-06 19:25 | v1.2.0 — Removed MaaS content (moved to dedicated `goose-maas-provider` skill); restored as local-proxy-only; updated description, tags, and related_skills |
| 2026-07-06 19:14 | v1.1.0 — Added MaaS remote provider config (now removed) |
| 2026-07-06 18:04 | v1.0.0 — Initial skill, capturing RedHat custom provider configuration |
