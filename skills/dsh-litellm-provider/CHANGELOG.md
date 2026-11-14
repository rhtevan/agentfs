# dsh-litellm-provider Changelog

| Updated | Change |
|---------|--------|
| 2026-11-13 21:04 | v1.2.0 — setup.sh: --dry-run (CONVERGED/PENDING), models ranked, agent-default-model = strongest served model (--default-model/--no-default/--force-default), line-level block edit with post-check, timestamped backups; setup.sh: converged message says when the default model is not managed; verify.sh: new check — agent-default-model is served by LiteLLM (+ strongest-model info); latest timestamped backup shown; doc: no runtime discovery in DSH, agent-default-model section, dry-run workflow + flags, S5/T5/T6 |
| 2026-11-13 20:42 | v1.1.1 — doc: settings.yaml example updated to current proxy models; list is generated from /v1/models |
| 2026-11-09 11:14 | v1.1.0 — CNL restructure: replaced numbered list Steps with ### Step N + agent MUST pattern and Output Contract |
| 2026-11-08 22:50 | v1.2.0 — Add Rules + trace; Add trace-lib.sh; Add trace-lib.sh |
| 2026-11-05 19:30 | v1.1.0 — Add model-tier to frontmatter |
| 2026-08-24 16:57 | v1.1.0 — Fixed: DSH rejects empty apiKeyEnv; now uses LITELLM_VERTEX_AI_API_KEY with dummy value; fixed verify.sh bash arithmetic under set -e; fixed model grep patterns for YAML indent |
| 2026-08-24 14:25 | v1.0.1 — Fixed markdown rendering: added missing blank lines around code fence in Restore section |
| 2026-08-24 13:47 | v1.0.0 — Initial skill: auto-discover models from LiteLLM, write DSH settings.yaml, compat flags for Vertex AI Claude, verify, idempotent merge |
