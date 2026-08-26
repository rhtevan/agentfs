---
type: Reference
title: "GPU Memory Budgets"
description: "VRAM usage breakdowns for all deployment profiles"
tags: [gpu, vram, memory, tuning, speculative-decoding]
timestamp: 2026-08-25T22:36:00-04:00
---

# GPU Memory Budgets

> See also: [deployment-profiles.md](./deployment-profiles.md) for profile definitions.
> See also: [model-landscape.md](./model-landscape.md) for model catalog.
> See also: [benchmark-report.md](./benchmark-report.md) for measured performance.

---

## rhtevan-work (1× RTX A500, 4 GB GDDR6, 128 GB/s)

### Profile: `g3b-16k` ✅ Default

Granite 4.1 3B Q4_K_M via llama.cpp, 1 slot, 16K context.

| Component | Usage |
|-----------|-------|
| Model weights (Q4_K_M, all layers on GPU) | ~1.7 GiB |
| KV cache (16K ctx, 1 slot) | ~1.5 GiB |
| Overhead | ~0.3 GiB |
| **GPU Total** | **~3.5 / 3.76 GiB** |
| **Headroom** | **~0.3 GiB** |

> 16K context is the VRAM ceiling on this GPU. 32K requires ~2.5 GB KV cache → OOM.
> Reducing slots from 4 to 1 freed KV memory but context ceiling unchanged.

### Profile: `g350m-2k`

Granite 4.0 350M FP16 via vLLM, 2K context.

| Component | Usage |
|-----------|-------|
| Model weights (FP16) | ~0.7 GiB |
| CUDA graphs + overhead | ~1.5 GiB |
| KV cache (2K ctx) | ~0.2 GiB |
| **GPU Total** | **~2.4 / 3.76 GiB** |

> Speed-only profile (44 tok/s). Model too small for quality tasks.

---

## rhel-ai (4× NVIDIA L4, 21.95 GB/GPU, 300 GB/s each)

### Profile: `g8b-fp8-spec-128k` ✅ Default

Granite 4.1 8B FP8 + Granite 4.1 3B FP8 draft, TP=4, CUDA graphs enabled.
**Measured: 58-79 tok/s, 93.8% VRAM utilization, 97-100% GPU compute.**

| Component | Usage (per GPU) |
|-----------|:---:|
| Target weights (8B FP8 / 4 GPUs) | ~2.0 GiB |
| Draft weights (3B FP8 / 4 GPUs) | ~0.75 GiB |
| CUDA graphs (compiled execution paths) | ~10.0 GiB |
| KV cache (128K ctx) | ~8.8 GiB |
| **Total per GPU** | **~21.6 / 21.95 GiB** |
| **Headroom** | **~0.35 GiB** (5% safety margin via `--gpu-memory-utilization 0.95`) |

> Three optimizations stack multiplicatively:
> 1. FP8 quantization — halves weight reads (16→8 GB target, 6→3 GB draft)
> 2. CUDA graphs — eliminates Python/framework dispatch overhead
> 3. Speculative decoding — 5 candidate tokens verified per weight read
>
> `draft_tensor_parallel_size` must equal target `tensor_parallel_size` (vLLM constraint).

### Profile: `g8b-spec-128k`

Granite 4.1 8B BF16 + Granite 4.1 3B BF16 draft, TP=4, `--enforce-eager`.
**Measured: 19-25 tok/s.**

| Component | Usage (per GPU) |
|-----------|:---:|
| Target weights (8B BF16 / 4 GPUs) | ~4.0 GiB |
| Draft weights (3B BF16 / 4 GPUs) | ~1.5 GiB |
| Overhead (enforce-eager, no CUDA graphs) | ~0.5 GiB |
| KV cache (128K ctx) | ~15.0 GiB |
| **Total per GPU** | **~21.0 / 21.95 GiB** |
| **Headroom** | **~0.95 GiB** |

> Safer fallback: BF16 preserves full precision, `--enforce-eager` avoids
> CUDA graph memory overhead. 3× slower than FP8 variant but identical quality
> on all 7 benchmark tests.

---

## Historical Benchmarked Configurations (Not Active Profiles)

These configurations were benchmarked but are not maintained as profiles.
Results documented in [benchmark-report.md](./benchmark-report.md).

### Gemma 4 31B FP8-block (TP=4, 128K) — 13.4 tok/s

| Component | Usage (per GPU) |
|-----------|:---:|
| Model weights (FP8-block / 4 GPUs) | ~7.75 GiB |
| Overhead (enforce-eager, no CUDA graphs) | ~0.5 GiB |
| KV cache (128K ctx) | ~3.5 GiB |
| **Total per GPU** | **~11.75 / 21.95 GiB** |

> **Must use `--enforce-eager`.** CUDA graphs add ~10 GiB/GPU → OOM.
> BF16 variant does NOT fit (78 GB model > 88 GB total VRAM).
> Must use `RedHatAI/gemma-4-31B-it-FP8-block` (block-wise FP8 quantization).

### Qwen3.8-27B FP8 (TP=4, 128K) — 11.8 tok/s

| Component | Usage (per GPU) |
|-----------|:---:|
| Model weights (27B FP8 / 4 GPUs) | ~3.5 GiB |
| Overhead (enforce-eager) | ~0.5 GiB |
| KV cache (128K ctx) | ~3.5 GiB |
| **Total per GPU** | **~7.5 / 21.95 GiB** |

> Plenty of headroom but bandwidth-limited at 11.8 tok/s.
> Thinking mode can exhaust token budget on complex tasks.

---

## Key Constraints

### Memory Bandwidth = Token Speed

```
tok/s ≈ Total GPU Bandwidth (GB/s) ÷ Model Weights (GB) × efficiency
```

L4 GPUs use GDDR6 (300 GB/s each), not HBM. This caps large model inference.
Speculative decoding is the primary software lever to overcome this.

### CUDA Graphs vs --enforce-eager

| Mode | Extra VRAM/GPU | Speed Impact | When to Use |
|------|:---:|:---:|---|
| CUDA graphs (default) | ~10 GiB | 2-3× faster | FP8 models with small weights |
| `--enforce-eager` | ~0.5 GiB | Baseline | Large models, BF16, or tight VRAM |

### Speculative Decoding Memory

Draft model runs TP=4 alongside target (vLLM constraint). Memory per GPU:
- 3B BF16 draft: ~1.5 GiB/GPU
- 3B FP8 draft: ~0.75 GiB/GPU
- Speculative token buffers: ~0.1 GiB/GPU (negligible)
