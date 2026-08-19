# hosted-model-ctl Changelog


| Updated | Change |
|---------|--------|
| 2026-08-19 | v5.4.1 — Fixed report operation: added explicit agent instruction to present script output as-is (not summarize/reformat). Fixed signal phrases: `hosted model report`, `hosted model machine spec`, `hosted model host report` (scoped to `hosted model` prefix for reliable routing). |
| 2026-08-19 | v5.4.0 — Added `report` operation (S8) with `report.sh` script. Generates 3-section platform report: basic specs, accelerator specs, model recommendations by VRAM tier. Added `references/model-landscape.md` curated model database. New signals: `hosted model report`, `machine spec`, `host report`. Runtime preference: vLLM/llm-d first, llama.cpp when VRAM insufficient. Minimum 64K context target with trade-off guidance for constrained hosts. Updated rhtevan-work gotcha: nvidia-smi now available. |
| 2026-08-17 | v5.3.0 — Added `--enable-auto-tool-choice --tool-call-parser granite` to vllm-ilab engine in setup.sh (required for OLS tool calling via Skupper). Fixed `local` keyword used outside function context in setup.sh (llama-cpp and vllm-ilab paths). |
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
