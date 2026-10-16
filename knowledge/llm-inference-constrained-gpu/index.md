---
title: LLM Inference on Constrained GPUs
bundle-version: "1.0"
created: 2026-08-04
tags: [llm, inference, gpu, vllm, llama-cpp, podman, nvidia, quantization, agentfs]
---

# LLM Inference on Constrained GPUs

Knowledge bundle capturing patterns, gotchas, and architectural decisions
for deploying LLM inference servers on NVIDIA GPUs with limited VRAM
(≤ 4 GB). Derived from real-world deployment sessions with IBM Granite
models on an RTX A500 Laptop GPU.

## Concepts

| Document | Topic |
|----------|-------|
| [vllm-vs-llamacpp-gpu-philosophy.md](./vllm-vs-llamacpp-gpu-philosophy.md) | Fundamental architectural difference: GPU-first vs CPU-first inference |
| [containerized-inference-pattern.md](./containerized-inference-pattern.md) | Reusable pattern for GPU-accelerated containerized model serving |
| [gpu-layer-tuning-methodology.md](./gpu-layer-tuning-methodology.md) | How to find optimal GPU layer count for llama.cpp on limited VRAM |
| [context-window-agentfs-requirements.md](./context-window-agentfs-requirements.md) | Minimum context window requirements for AgentFS compatibility |
| [fedora-nvidia-container-gotchas.md](./fedora-nvidia-container-gotchas.md) | Fedora-specific NVIDIA + Podman pitfalls and workarounds |
| [vllm-quantization-pitfalls.md](./vllm-quantization-pitfalls.md) | vLLM quantization failure modes and solutions |
| [speculative-decoding-tradeoffs.md](./speculative-decoding-tradeoffs.md) | When speculative decoding hurts: bandwidth-bound GPUs, TP overhead, vLLM V1 scheduler issues |
| [d3-decision-model-deployment.md](./d3-decision-model-deployment.md) | D3 Decision Model on L4: CUDA graph OOM (vision encoder), FP8 KV crash, optimization, NextToken vs SDM comparison |

## Log

| Date | Change |
|------|--------|
| 2026-10-15 | Added D3 decision model deployment concept |
| 2026-10-15 | Added speculative decoding tradeoffs concept (L4 benchmark evidence) |
| 2026-08-04 | Initial bundle creation from deployment session on rhtevan-work |
