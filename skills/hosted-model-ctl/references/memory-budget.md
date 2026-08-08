---
type: Reference
title: "GPU Memory Budgets and Layer Tuning"
description: "VRAM usage breakdowns for all hosted models across both host profiles"
tags: [gpu, vram, memory, tuning]
timestamp: 2026-08-08T13:57:00-04:00
---

# GPU Memory Budgets and Layer Tuning

## GPU Layer Tuning (g8b, 4 GB VRAM)

| Context Size | Max GPU Layers | Prompt Speed | Gen Speed |
|:------------:|:--------------:|:------------:|:---------:|
| 4,096 | 25 | 53.9 tok/s | 10.8 tok/s |
| 16,384 | 18 | 44.6 tok/s | 8.3 tok/s |

## Memory Budget — rhtevan-work (4 GB VRAM)

### vLLM — g1b (bitsandbytes INT4)

| Component | Usage |
|-----------|-------|
| Model weights | ~1.17 GiB |
| Peak activation | ~0.36 GiB |
| KV cache | ~1.92 GiB |
| **Total** | **~3.5 / 3.68 GiB** |

### llama.cpp — g8b (GGUF Q4_K_M, 18 GPU layers)

| Component | Usage |
|-----------|-------|
| 18 GPU layers | ~2.5 GiB |
| KV cache (16K ctx) | ~1.0 GiB |
| CPU: remaining layers + overhead | ~5 GiB system RAM |
| **GPU Total** | **~3.5 / 3.68 GiB** |

## Memory Budget — rhel-ai (4× L4, 92 GB VRAM)

### vLLM — g30b-96k (BF16, tp=4)

| Component | Usage (per GPU) |
|-----------|-----------------|
| Model weights (30B / 4 GPUs) | ~15 GiB |
| KV cache (98K ctx) | ~5 GiB |
| Overhead | ~1 GiB |
| **Total per GPU** | **~21 / 21.95 GiB** |

### vLLM — g8b-128k (BF16, tp=2)

| Component | Usage (per GPU) |
|-----------|-----------------|
| Model weights (8B / 2 GPUs) | ~8 GiB |
| KV cache (128K ctx) | ~10 GiB |
| Overhead | ~1 GiB |
| **Total per GPU** | **~19 / 21.95 GiB** |
