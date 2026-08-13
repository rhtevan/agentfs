# hosted-model-ctl Changelog


| Updated | Change |
|---------|--------|
| 2026-08-12 | v5.2.0 — Split S5 into S5a (stop single alias, others unaffected) and S5b (stop all). Added negative assertion to T5a verifying models on other hosts are preserved. Added Scoping Safety gotcha. Prompted by skupper-model-provider v7.2.0 scoped-shutdown incident. |
| 2026-08-12 | v5.1.0 — Changed default rhel-ai model from `g30b-96k` to `g8b-128k`. Removed ambiguous bare signals (`model list/start/stop/status`); added `hosted model teardown`/`teardown hosted model` signals. Added teardown operation via `stop.sh --remove`. Clarified signal boundaries with `skupper-model-provider`. |
| 2026-08-08 | v5.0 — Complete rewrite: all operations as scripts; added Specification and Tests sections; compact tables; moved memory budgets to references/; proper heading hierarchy; applied skill-check 4 principles |
| 2026-08-08 | v4.0 — rhtevan-work port 8000→10000; consistent with Skupper listener |
| 2026-08-07 | v3.2 — rhel-ai port 8000→9000; port 8000 for Skupper |
| 2026-08-06 | v3.1 — Renamed local-model-ctl → hosted-model-ctl |
| 2026-08-06 | v3.0 — Added rhel-ai host profile, g30b-96k, g8b-128k |
| 2026-08-04 | v2.3 — Reverted g8b to 16K/18 GPU layers |
| 2026-08-04 | v2.0 — Multi-model support, llama.cpp engine |
| 2026-08-04 | v1.0 — Initial creation |
