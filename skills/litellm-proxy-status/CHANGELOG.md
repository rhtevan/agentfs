# litellm-proxy-status Changelog


| Updated | Change |
|---------|--------|
| 2026-11-13 19:42 | v1.2.0 — litellm-proxy-status v1.2.0: models.sh list/default (litellm model list, litellm default model); v1.2.0: add litellm model list, litellm default model queries; Tests section; Add queries litellm model list and litellm default model (scripts/models.sh, ranking shared with gcp-vertex-models); add Tests section; v1.2.0: add litellm model list, litellm default model queries; Tests section; Fix check-status.sh: trace_step called with text instead of numeric step (printf invalid number -> exit 1 under set -e); add trace_init/trace_end; Fix pre-existing bug: check-status.sh aborted at step 1 (trace_step given text, trace-lib expects numeric step); add trace_init/trace_end |
| 2026-11-08 18:04 | v1.1.0 — Create check-status.sh with trace instrumentation; Full QOO upgrade: Overview, Specification, Rules, Workflow with script, Output Contract, Error Handling, Troubleshooting |
| 2026-11-05 19:31 | v1.0.0 — Add model-tier to frontmatter |
| 2026-06-19 16:43 | v1.0 — Initial skill |
