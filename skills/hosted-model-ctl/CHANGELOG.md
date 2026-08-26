# hosted-model-ctl Changelog


| Updated | Change |
|---------|--------|
| 2026-08-26 17:31 | v7.4.0 — Rollback g3b-16k to version-agnostic: MODEL_ID changed from granite-4.2-3b to granite-3b, setup.sh auto-detects GGUF (prefers 4.1 over 4.2 — 4.2 thinking not supported by Goose 1.47). Rolled back container to granite-4.1-3b. |
| 2026-08-26 17:06 | v7.3.1 — Fix test.sh chat completion for reasoning models: increase max_tokens to 200, check reasoning_content as fallback |
| 2026-08-26 17:03 | v7.3.0 — Upgrade g3b-16k profile from Granite 4.1 to 4.2 (model ID, GGUF repo, GGUF filename, docs) |
| 2026-08-25 22:30 | v7.2.0 — Removed gemma4-128k and qwen38-128k profiles (11.8-13.4 tok/s not usable vs 58-79 tok/s default). Now 4 profiles total, 2 per host. Cleaned all scripts and references. |
| 2026-08-25 22:07 | v7.1.0 — Profile-only architecture: removed Model Registry and on-demand individual model aliases. All deployments go through profiles. Added g350m-2k profile. Renamed gemma4-31b→gemma4-128k, qwen38-27b→qwen38-128k. Profiles now contain all deployment details (model, engine, image, TP, context, port, speed). Rewrote deployment-profiles.md as canonical reference. Updated setup.sh to accept profile names directly (no --profile flag needed). |
| 2026-08-25 21:51 | v7.0.0 — Major simplification: removed all co-hosting profiles and solo-* naming. New profile naming convention: `<model>-<context>` (g3b-16k, g8b-spec-128k, g8b-fp8-spec-128k). Added speculative decoding support (vllm-spec engine, SPEC_CONFIGS). Added FP8 + CUDA graphs config achieving 58-79 tok/s (vs 13 tok/s baseline). Default profiles: g3b-16k (rhtevan-work), g8b-fp8-spec-128k (rhel-ai). Removed: g350m, g1b, g8b (llamacpp on rhtevan-work), all co-host profiles, all solo-* profiles, legacy vllm-ilab/vllm-bnb engines. All rhel-ai models consolidated to port 9000. Comprehensive benchmark report added to references/. |
| 2026-08-25 16:00 | v6.0.0 — Major update: added deployment profiles system (mutual exclusion per host, profile-aware start/stop/status). Added new models: Qwen3.8-27B, Qwen3-32B, Gemma 4 31B, Gemma 4 26B-A4B, Granite 4.1 3B. Added upstream vLLM v0.27.1 image support (ports 9001/9002) alongside legacy InstructLab image (port 9000). New references/deployment-profiles.md. Updated model-landscape.md with Gemma 4, Qwen3.8, GLM-4, Nemotron entries. Updated memory-budget.md with VRAM budgets for all new models. Default profiles: solo-g3b (rhtevan-work), solo-qwen38 (rhel-ai). Specs: S1b, S3b, S4b, S5c added for profile operations. |
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
