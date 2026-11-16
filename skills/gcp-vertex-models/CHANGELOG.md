# gcp-vertex-models Changelog


| Updated | Change |
|---------|--------|
| 2026-11-16 11:22 | v1.1.0 — Move select-sa.sh from litellm-vertex-ai-proxy (credential discovery is a capability, not proxy deployment); Move detect-sa.sh from litellm-vertex-ai-proxy; report GCP credential store state; Resolve credentials via select-sa.sh when GOOGLE_APPLICATION_CREDENTIALS is unset; warn instead of silently using application default credentials; B6: add crc-ols as consumer, credential signals, S6/S7 specs and T6-T9 tests for select-sa/detect-sa |
| 2026-11-13 19:53 | v1.0.1 — Doc: list goose-gcp-provider as consumer; Doc: goose-gcp-provider listed as consumer |
| 2026-11-13 19:37 | v1.0.0 — Initial skill: probe-models.sh moved from litellm-vertex-ai-proxy v3.3.0 (adds JSON cache); models.sh list/default/rank; verify.sh S1–S5; signals refresh vertex models, vertex model list, vertex default model; gcp-vertex-models v1.0.0: new skill (refresh vertex models, vertex model list, vertex default model) |
