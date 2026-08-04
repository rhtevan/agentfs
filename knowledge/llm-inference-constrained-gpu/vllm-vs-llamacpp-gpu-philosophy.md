---
title: "vLLM vs llama.cpp: GPU-First vs CPU-First Inference"
created: 2026-08-04
tags: [vllm, llama-cpp, gpu, cpu-offload, architecture]
---

# vLLM vs llama.cpp: GPU-First vs CPU-First Inference

vLLM and llama.cpp take fundamentally opposite approaches to GPU memory
management. This distinction determines which engine works on
constrained GPUs.

## vLLM: GPU-First (Offload to CPU)

- **Default compute device:** GPU
- **Philosophy:** "I'm a GPU engine; spill excess weights to CPU RAM"
- **`--cpu-offload-gb N`** moves N GB of weights FROM GPU TO CPU
- **Model loads to GPU first**, then offloads layers to CPU
- **Fatal flaw on small GPUs:** If the model doesn't fit in VRAM even
  momentarily during loading, the process OOMs before offloading begins
- **Best for:** Models that fit entirely on GPU (with or without quantization)

## llama.cpp: CPU-First (Offload to GPU)

- **Default compute device:** CPU
- **Philosophy:** "I'm a CPU engine; push layers to GPU for acceleration"
- **`--n-gpu-layers N`** moves N layers FROM CPU TO GPU
- **Model loads to CPU RAM first**, then selected layers move to GPU
- **Graceful on small GPUs:** Starts on CPU (always succeeds if RAM
  sufficient), GPU is a bonus accelerator
- **Best for:** Models too large for GPU, hybrid CPU+GPU inference

## Practical Impact

| Scenario | vLLM | llama.cpp |
|----------|:----:|:---------:|
| Model fits in VRAM | ✅ Best performance | ✅ Works, slightly slower |
| Model slightly exceeds VRAM | ❌ OOM during load | ✅ Partial GPU offload |
| Model far exceeds VRAM | ❌ Cannot start | ✅ CPU + few GPU layers |
| CPU-only (no GPU) | ⚠️ Experimental | ✅ Native, optimized |

## Decision Rule

> If the model (quantized) fits in GPU VRAM with room for KV cache,
> use **vLLM** for maximum throughput. Otherwise, use **llama.cpp**
> with `--n-gpu-layers` tuned to available VRAM.

## Source

Derived from deployment of `granite-4.0-1b` (vLLM, INT4 bitsandbytes)
and `granite-4.1-8b` (llama.cpp, GGUF Q4_K_M) on an NVIDIA RTX A500
Laptop GPU (4 GB VRAM).
