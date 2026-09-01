# Model Landscape Reference

> Curated open-source models for self-hosted inference.
> Minimum context: 64K (128K preferred). Runtime: vLLM/llm-d preferred.
> See also: [deployment-profiles.md](./deployment-profiles.md) for curated deployment combos.
> Last updated: 2026-09-01 18:45

## VRAM Tier Definitions

| Tier | Total VRAM | TP | Example Setup |
|------|:----------:|:--:|---------------|
| **Micro** | ≤4 GB | 1 | 1× RTX A500 Laptop (4 GB) |
| **Small** | 16–24 GB | 1–2 | 1× RTX 4090 (24 GB), 1× L4 (23 GB) |
| **Medium** | 46–48 GB | 2 | 2× L4 (46 GB) |
| **Large** | 90–96 GB | 4 | 4× L4 (90 GB), 2× A100-40 (80 GB) |
| **XLarge** | 160+ GB | 4–8 | 4× A100-80 (320 GB), 8× H100 |

## Model Database

### IBM Granite

| Model           | Params |   Native Ctx    | BF16 Wt | FP8 Wt | Q4 Wt  | KV@128K | Tool Calling  | HF Repo                     |
| --------------- | :----: | :-------------: | :-----: | :----: | :----: | :-----: | :-----------: | --------------------------- |
| Granite 4.1 3B  |   3B   |      128K       |  ~6 GB  | ~3 GB  | ~2 GB  |  ~4 GB  |   ✅ hermes    | ibm-granite/granite-4.1-3b  |
| Granite 4.1 8B  |   8B   |      128K       | ~16 GB  | ~8 GB  | ~5 GB  |  ~8 GB  |   ✅ hermes    | ibm-granite/granite-4.1-8b  |
| Granite 4.1 30B |  30B   |      128K       | ~60 GB  | ~30 GB | ~17 GB | ~16 GB  |   ✅ hermes    | ibm-granite/granite-4.1-30b |
| Granite 4.2 3B  |   3B   | 128K (512K ext) |  ~6 GB  | ~3 GB  | ~2 GB  |  ~4 GB  | ✅ qwen3_coder | ibm-granite/granite-4.2-3b  |
| Granite 4.2 8B  |   8B   | 128K (512K ext) | ~16 GB  | ~8 GB  | ~5 GB  |  ~8 GB  | ✅ qwen3_coder | ibm-granite/granite-4.2-8b  |
| Granite 4.2 30B |  30B   | 128K (512K ext) | ~60 GB  | ~30 GB | ~17 GB | ~16 GB  | ✅ qwen3_coder | ibm-granite/granite-4.2-30b |

> **Granite 4.2 notes:** Built-in reasoning via `<think>...</think>` chain-of-thought (default on).
> Same GraniteForCausalLM architecture as 4.1 (same weights size, same KV cache).
> Requires `--tool-call-parser qwen3_coder` (not hermes) and `--reasoning-parser nemotron_v3`.
> FP8 variants available (`granite-4.2-{3b,8b,30b}-fp8`). GGUF variants available.
> Thinking budget: code gen tasks need max_tokens >= 8192; short tasks have 70-80% reasoning overhead.
> Temperature must be 1.0 with top_p=0.95 per IBM recommendation.
> Thinking can be disabled via `chat_template_kwargs: {enable_thinking: false}`.
>
> **4.2 + llama.cpp caveat:** llama.cpp has no reasoning parser — thinking tags appear inline
> in response content. Not recommended for constrained GPU (4 GB) deployments where the
> 3B model is used. Stick with 4.1 3B for llama.cpp on low-VRAM hardware.

### Qwen

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Qwen3 4B | 4B | 128K | ~8 GB | ~4 GB | ~2.5 GB | ~5 GB | ✅ hermes | Qwen/Qwen3-4B |
| Qwen3 8B | 8B | 128K | ~16 GB | ~8 GB | ~5 GB | ~8 GB | ✅ hermes | Qwen/Qwen3-8B |
| Qwen3 32B | 32B | 128K | ~64 GB | ~32 GB | ~18 GB | ~16 GB | ✅ hermes | Qwen/Qwen3-32B |
| **Qwen3.8 27B** | 27B | 128K | ~54 GB | ~27 GB | ~15 GB | ~14 GB | ✅ hermes | Qwen/Qwen3.8-27B-FP8 |
| Qwen3-Coder 30B-A3B | 30.5B (3.3B active) | 256K | ~61 GB | ~30 GB | ~17 GB | ~12 GB | ✅ hermes | Qwen/Qwen3-Coder-30B-A3B-Instruct |

> **Qwen3.8-27B notes:** Vision-language model (text+image+video). IFBench 79.5
> (vs Opus 4.6 at 62.5), SWE-bench Pro 61.7. Arch: `Qwen2ForCausalLM` — supported
> Arch: `Qwen2ForCausalLM` — supported by vLLM nightly. Use `--tool-call-parser qwen3_xml`
> and `--reasoning-parser qwen3`. FP8 variant available directly from HF (`Qwen3.8-27B-FP8`).
>
> **Qwen3-Coder-30B-A3B notes:** MoE (128 experts, 8 active). Purpose-built for
> agentic coding — CLINE/IDE integration, 256K native context. Non-thinking mode
> only. MoE routing needs vLLM MoE support validation.

### Meta Llama

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Llama 3.1 8B | 8B | 128K | ~16 GB | ~8 GB | ~5 GB | ~8 GB | ✅ llama3 | meta-llama/Llama-3.1-8B-Instruct |
| Llama 3.3 70B | 70B | 128K | ~140 GB | ~70 GB | ~40 GB | ~20 GB | ✅ llama3 | meta-llama/Llama-3.3-70B-Instruct |

### Google Gemma

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Gemma 3 12B | 12B | 128K | ~24 GB | ~12 GB | ~7 GB | ~8 GB | ⚠️ limited | google/gemma-3-12b-it |
| Gemma 3 27B | 27B | 128K | ~54 GB | ~27 GB | ~15 GB | ~14 GB | ⚠️ limited | google/gemma-3-27b-it |
| **Gemma 4 31B** | 30.7B | 256K | ~62 GB | ~31 GB | ~17 GB | ~16 GB | ✅ gemma4 | google/gemma-4-31B-it |
| Gemma 4 26B-A4B | 25.2B (3.8B active) | 256K | ~50 GB | ~25 GB | ~14 GB | ~12 GB | ✅ gemma4 | google/gemma-4-26B-A4B-it |
| Gemma 4 12B | 12B | 256K | ~24 GB | ~12 GB | ~7 GB | ~8 GB | ✅ gemma4 | google/gemma-4-12B-it |

> **Gemma 4 31B notes:** Dense model. MMLU-Pro 85.2, GPQA 84.3, LiveCodeBench 80.0,
> Tau2 76.9 (tool calling), Codeforces 2150, AIME 2026 89.2. Native function calling,
> thinking mode, 256K context. Arch: `Gemma4ForConditionalGeneration` — requires
> Requires **vLLM nightly** (v0.27.1+ lacks support; nightly has fix #51757). Apache 2.0 license.
>
> **Gemma 4 26B-A4B notes:** MoE (128 experts, 8 active). Runs at ~4B model speed
> with 26B knowledge. GPQA 82.3, Tau2 68.2. Same vLLM requirement as 31B.
>
> **Gemma 4 12B notes:** Unified encoder-free architecture (no separate vision/audio
> encoder). Supports text, image, audio natively. 256K context.

### Mistral

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Mistral Small 3.2 24B | 24B | 128K | ~48 GB | ~24 GB | ~14 GB | ~12 GB | ✅ mistral | mistralai/Mistral-Small-3.2-24B-Instruct-2506 |

### Microsoft Phi

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Phi-4 Mini 14B | 14B | 128K | ~28 GB | ~14 GB | ~8 GB | ~8 GB | ⚠️ limited | microsoft/Phi-4-mini-instruct |

### Tsinghua GLM

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| GLM-4-32B | 32B | 128K | ~64 GB | ~32 GB | ~18 GB | ~14 GB | ✅ glm4 | THUDM/GLM-4-32B-0414 |

> **GLM-4-32B notes:** Dense 32B from Tsinghua. MIT license. Good at tool calling.
> Arch: `ChatGLMModel` — supported by vLLM 0.8.4+.

### NVIDIA Nemotron

| Model | Params | Native Ctx | Weight Size | Active Params | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-----------:|:-------------:|:------------:|----------|
| Nemotron-3-Nano 30B-A3B | 30B | 128K | ~60 GB (BF16) | 3.5B | ✅ yes | nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B-BF16 |
| Nemotron-3-Super 120B-A12B | 120B | 1M | ~240 GB (BF16) | 12B | ✅ yes | nvidia/NVIDIA-Nemotron-3-Super-120B-A12B-BF16 |

> **Nemotron notes:** Hybrid Mamba-2 + MoE + Attention architecture. Nano fits
> ~60 GB BF16 (tight on 4× L4). Super requires 8× H100-80GB minimum.
> NVIDIA Nemotron Open Model License.

## Tier Recommendations

### Micro Tier (≤4 GB) — vLLM not feasible, llama.cpp required

> vLLM needs full model weights on GPU. Even Granite 3B FP8 (~3 GB) leaves <1 GB
> for KV cache. llama.cpp enables partial GPU offload and CPU fallback.

| Rank | Model | Runtime | Quant | Max Context | Est. VRAM | Tok/s | Trade-off |
|:----:|-------|:-------:|:-----:|:-----------:|:---------:|:-----:|:---------:|
| 1 | Granite 4.1 3B | llama.cpp | Q4_K_M | 16K | ~3.2 GB | ~25-35 | Best context stretch; full GPU offload |
| 2 | Qwen3 4B | llama.cpp | Q4_K_M | 8K | ~3.5 GB | ~20-30 | Stronger reasoning; context limited to 8K |
| 3 | Granite 4.1 8B | llama.cpp | Q4_K_M | 4-16K | 2.5-3.8 GB | ~8-15 | Best quality; partial offload (18-25/32 layers) |

CPU fallback path: Granite 8B Q4 CPU-only → 64K context @ ~2-4 tok/s (needs ~13 GB RAM).

### Small Tier (16-24 GB) — vLLM feasible for ≤8B

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|
| 1 | Granite 4.1 8B | vLLM | FP8 | 1 | 64K | ~12 GB | ~40-50 |
| 2 | Qwen3 8B | vLLM | FP8 | 1 | 64K | ~12 GB | ~40-50 |
| 3 | Granite 4.1 8B | vLLM | BF16 | 1 | 32K | ~20 GB | ~50-60 |

### Medium Tier (46-48 GB, TP=2) — sweet spot for 8-27B

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|
| 1 | Granite 4.1 8B | vLLM | BF16 | 2 | 128K | ~24 GB | ~50-70 |
| 2 | Qwen3.8 27B | vLLM | FP8 | 2 | 128K | ~41 GB | ~25-35 |
| 3 | Mistral Small 24B | vLLM | FP8 | 2 | 128K | ~36 GB | ~30-40 |

### Large Tier (90-96 GB, TP=4) — 30-32B at full context

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s | vLLM |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|:----:|
| 1 | **Gemma 4 31B** | vLLM | BF16 | 4 | 128K | ~78 GB | ~20-30 | nightly |
| 2 | **Qwen3.8 27B** | vLLM | FP8 | 4 | 128K | ~41 GB | ~30-40 | 0.8.4+ |
| 3 | **Gemma 4 31B** | vLLM | FP8 | 4 | **256K** | ~47 GB | ~25-35 | nightly |
| 4 | Qwen3 32B | vLLM | FP8 | 4 | 128K | ~48 GB | ~30-40 | 0.8.4+ |
| 5 | Granite 4.1 30B | vLLM | FP8 | 4 | 128K | ~46 GB | ~20-30 | 0.8.4+ |
| 6 | Granite 4.1 8B | vLLM | BF16 | 2 | 128K | ~24 GB | ~50-70 | 0.8.4+ |

**Speculative decoding** is the recommended strategy for Large Tier on GDDR6 GPUs
(e.g., 4× L4). Rather than deploying a single large model at 11-13 tok/s, use a
smaller target (8B) with a same-family draft model (3B) to achieve 58-79 tok/s.
See [deployment-profiles.md](./deployment-profiles.md) for curated profile definitions
and [benchmark-report.md](./benchmark-report.md) for measured results.

### XLarge Tier (160+ GB) — 70B+ models

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|
| 1 | Llama 3.3 70B | vLLM | FP8 | 4 | 128K | ~90 GB | ~20-30 |
| 2 | Llama 3.3 70B | vLLM | BF16 | 8 | 128K | ~160 GB | ~25-35 |
| 3 | Qwen3 32B | vLLM | BF16 | 4 | 128K | ~80 GB | ~35-45 |

## vLLM Deployment Flags Reference

| Flag | When to use |
|------|------------|
| `--enforce-eager` | Large models on tight VRAM (skips CUDA graphs ~10 GB/GPU overhead). Also required with bitsandbytes quantization. |
| `--disable-custom-all-reduce` | Required for PCIe interconnect (no NVLink) |
| `--enable-auto-tool-choice` | Enable tool/function calling |
| `--tool-call-parser qwen3_coder` | IBM Granite 4.2 models |
| `--tool-call-parser hermes` | IBM Granite 4.1 models (hermes format, not granite parser) |
| `--tool-call-parser hermes` | Qwen3/Qwen3.8 models |
| `--tool-call-parser gemma4` | Gemma 4 models (vLLM nightly) |
| `--tool-call-parser llama3` | Llama 3.x models |
| `--tool-call-parser mistral` | Mistral models |
| `--tool-call-parser glm4` | GLM-4 models |
| `--reasoning-parser nemotron_v3` | IBM Granite 4.2 thinking/reasoning token separation |
| `--reasoning-parser qwen3` | Qwen3.8 thinking/reasoning token separation |
| `--reasoning-parser gemma4` | Gemma 4 reasoning token separation |
| `--speculative-config '{...}'` | Enable speculative decoding (draft_model, ngram, etc.) |
| `--tensor-parallel-size N` | Distribute across N GPUs |
| `--max-model-len N` | Cap context window (prevent OOM) |
| `--gpu-memory-utilization 0.95` | Use more VRAM (default 0.9) |

## llama.cpp Deployment Flags Reference

| Flag | When to use |
|------|------------|
| `--n-gpu-layers N` | Number of layers to offload to GPU (99 = all) |
| `-c N` | Context size in tokens |
| `--host 0.0.0.0` | Listen on all interfaces |
| `--port N` | API port |
