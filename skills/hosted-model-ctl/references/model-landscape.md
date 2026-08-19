# Model Landscape Reference

> Curated open-source models for self-hosted inference.
> Minimum context: 64K (128K preferred). Runtime: vLLM/llm-d preferred.
> Last updated: 2026-08-19

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

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Granite 4.1 3B | 3B | 128K | ~6 GB | ~3 GB | ~2 GB | ~4 GB | ✅ granite | ibm-granite/granite-4.1-3b |
| Granite 4.1 8B | 8B | 128K | ~16 GB | ~8 GB | ~5 GB | ~8 GB | ✅ granite | ibm-granite/granite-4.1-8b |
| Granite 4.1 30B | 30B | 128K | ~60 GB | ~30 GB | ~17 GB | ~16 GB | ✅ granite | ibm-granite/granite-4.1-30b |

### Qwen

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Qwen3 4B | 4B | 128K | ~8 GB | ~4 GB | ~2.5 GB | ~5 GB | ✅ hermes | Qwen/Qwen3-4B |
| Qwen3 8B | 8B | 128K | ~16 GB | ~8 GB | ~5 GB | ~8 GB | ✅ hermes | Qwen/Qwen3-8B |
| Qwen3 32B | 32B | 128K | ~64 GB | ~32 GB | ~18 GB | ~16 GB | ✅ hermes | Qwen/Qwen3-32B |
| Qwen3.8 27B | 27B | 128K | ~54 GB | ~27 GB | ~15 GB | ~14 GB | ✅ hermes | Qwen/Qwen3.8-27B |

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

### Mistral

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Mistral Small 3.2 24B | 24B | 128K | ~48 GB | ~24 GB | ~14 GB | ~12 GB | ✅ mistral | mistralai/Mistral-Small-3.2-24B-Instruct-2506 |

### Microsoft Phi

| Model | Params | Native Ctx | BF16 Wt | FP8 Wt | Q4 Wt | KV@128K | Tool Calling | HF Repo |
|-------|:------:|:----------:|:-------:|:------:|:-----:|:-------:|:------------:|----------|
| Phi-4 Mini 14B | 14B | 128K | ~28 GB | ~14 GB | ~8 GB | ~8 GB | ⚠️ limited | microsoft/Phi-4-mini-instruct |

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

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|
| 1 | Qwen3 32B | vLLM | FP8 | 4 | 128K | ~48 GB | ~30-40 |
| 2 | Granite 4.1 8B | vLLM | BF16 | 2 | 128K | ~24 GB | ~50-70 |
| 3 | Granite 4.1 30B | vLLM | FP8 | 4 | 128K | ~46 GB | ~20-30 |

Co-hosting combos (TP=2 + TP=2):
- Granite 8B BF16 + Qwen3.8 27B FP8 → enterprise + reasoning
- Granite 8B BF16 + Mistral Small 24B FP8 → general + coding
- Granite 8B BF16 + Gemma 3 27B FP8 → enterprise + multilingual
- Qwen3 8B BF16 + Qwen3.8 27B FP8 → light + heavy reasoning

### XLarge Tier (160+ GB) — 70B+ models

| Rank | Model | Runtime | Quant | TP | Context | Est. VRAM | Tok/s |
|:----:|-------|:-------:|:-----:|:--:|:-------:|:---------:|:-----:|
| 1 | Llama 3.3 70B | vLLM | FP8 | 4 | 128K | ~90 GB | ~20-30 |
| 2 | Llama 3.3 70B | vLLM | BF16 | 8 | 128K | ~160 GB | ~25-35 |
| 3 | Qwen3 32B | vLLM | BF16 | 4 | 128K | ~80 GB | ~35-45 |

## vLLM Deployment Flags Reference

| Flag | When to use |
|------|------------|
| `--enforce-eager` | Required with bitsandbytes quantization (CUDAGraph incompatible) |
| `--disable-custom-all-reduce` | Required for PCIe interconnect (no NVLink) |
| `--enable-auto-tool-choice` | Enable tool/function calling |
| `--tool-call-parser granite` | IBM Granite models |
| `--tool-call-parser hermes` | Qwen3 models |
| `--tool-call-parser llama3` | Llama 3.x models |
| `--tool-call-parser mistral` | Mistral models |
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
