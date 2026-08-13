# goose-litellm-provider Changelog


| Updated | Change |
|---------|--------|
| 2026-08-10 15:39 | v1.6.0 — Removed claude-sonnet-4-5; fixed context_limit (opus/sonnet: 1M, haiku: 200k); fixed config.yaml default model to claude-opus-4-6 |
| 2026-08-10 15:25 | v1.5.0 — Added claude-haiku-4-5 to models; changed fast_model from claude-sonnet-4-6 to claude-haiku-4-5; updated Vertex AI region from global to us-east5 in LiteLLM config |
| 2026-08-10 12:55 | v1.4.0 — Removed pyyaml dependency from verify.sh (replaced with awk); consolidated Steps 1-2 (inline curl commands) into single pre-flight check using verify.sh; renumbered steps (6→5); 5-principle skill check clean |
| 2026-08-10 10:38 | v1.3.0 — Set fast_model to claude-sonnet-4-6; added Model Selection Architecture section; added scripts/verify.sh and scripts/restore.sh; added Specification and Tests sections; consolidated workflow steps; added defensive template warning; added user-invocable and disable-model-invocation to frontmatter; normalized changelog versions |
| 2026-07-06 19:25 | v1.2.0 — Removed MaaS content (moved to dedicated `goose-maas-provider` skill); restored as local-proxy-only; updated description, tags, and related_skills |
| 2026-07-06 19:14 | v1.1.0 — Added MaaS remote provider config (now removed) |
| 2026-07-06 18:04 | v1.0.0 — Initial skill, capturing RedHat custom provider configuration |
