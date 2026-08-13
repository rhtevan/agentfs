# goose-maas-provider Changelog


| Updated | Change |
|---------|--------|
| 2026-08-10 22:22 | v1.4 — Added `qwen36-35b-a3b` (Qwen 3.6 35B-A3B MoE) and `deepseek-r1-distill-qwen-14b` to model list in provider JSON, reference configuration, recovery script, and model compatibility matrix |
| 2026-07-06 20:06 | v1.3 — **Goose Desktop is incompatible with MaaS** — tool calling fails under all tested Desktop configurations (streaming on/off, toolshim on/off); CLI with `GOOSE_TOOLSHIM: true` is the only working approach; updated Desktop section, troubleshooting |
| 2026-07-06 20:00 | v1.2 — Added `GOOSE_TOOLSHIM: true` requirement; `supports_streaming: false` for Desktop; documented Desktop vs CLI differences |
| 2026-07-06 19:39 | v1.1 — **Breaking**: reasoning models (`gpt-oss-120b`, `qwen3-14b`, `deepseek-r1-*`) are fundamentally incompatible with Goose's OpenAI streaming parser — goose drops tool_calls that follow `reasoning_content` chunks. Changed default model to `llama-scout-17b`. Added all available models to provider JSON. Updated model compatibility matrix, troubleshooting, recovery script. Config settings (`reasoning: false`, `preserves_thinking: false`) are necessary but NOT sufficient for reasoning models. |
| 2026-07-06 19:25 | v1.0 — Initial skill; extracted MaaS-specific content from `goose-litellm-provider`, added critical reasoning model fixes (`reasoning: false`, `preserves_thinking: false`), documented failure modes with evidence from real sessions, API key keyring handling, diagnostic tests |
