---
type: Postmortem
title: "vLLM Model Deployment on Multi-GPU Cloud Instances"
description: "128K context VRAM calculations, InstructLab container runtime, tensor parallelism, and model selection gotchas"
tags: [vllm, granite, llm, gpu, nvidia, l4, tensor-parallelism, context-window, rhel-ai]
timestamp: 2026-08-08T12:09:00-04:00
---

# vLLM Model Deployment on Multi-GPU Cloud Instances

## Hardware Profile: rhel-ai

| Component | Spec |
|-----------|------|
| GPUs | 4× NVIDIA L4 |
| VRAM per GPU | 23 GB (21.95 GiB usable) |
| Total VRAM | ~92 GB |
| Compute Capability | 8.9 (Ada Lovelace) |
| System RAM | 181 GB |
| Disk | 782 GB available on /var |
| vLLM | 0.8.4 (inside InstructLab container) |

## 128K Context Window: VRAM Reality Check

The KV cache VRAM formula:

```
KV cache ≈ 2 × num_layers × num_kv_heads × head_dim × context_length × 2 bytes (FP16)
```

### Granite 4.1 30B (BF16, tp=4)

| Component | Usage (per GPU) |
|-----------|-----------------|
| Model weights (30B / 4 GPUs) | ~15 GiB |
| KV cache overhead | ~5 GiB |
| Runtime overhead | ~1 GiB |
| **Total per GPU** | **~21 / 21.95 GiB** |

**128K didn't fit.** The KV cache for 131,072 tokens exceeded the
available memory at 0.95 GPU utilization. Maximum achievable:
**98,304 tokens (~96K)**.

### Granite 4.1 8B (BF16, tp=2)

| Component | Usage (per GPU) |
|-----------|-----------------|
| Model weights (8B / 2 GPUs) | ~8 GiB |
| KV cache (128K ctx) | ~10 GiB |
| Runtime overhead | ~1 GiB |
| **Total per GPU** | **~19 / 21.95 GiB** |

**128K fits with tp=2.** Single GPU (tp=1) only supports ~27K tokens.
Using 2 GPUs with tensor parallelism achieves full 128K.

## Model Selection Mistakes

### Qwen3 72B: Not 128K

Initially recommended as the "best open model" for rhel-ai.
**Disqualified** because Qwen3 models max at **40,960 tokens** natively
(not 128K). The HuggingFace config shows `max_position_embeddings: 40960`.
Extending beyond that requires custom RoPE scaling which degrades quality.

### Granite 4.1 "14B": Doesn't Exist

Initially stated Granite 4.1 comes in 8B and 14B. **Corrected:**
the lineup is 2B, 3B, 8B, and **30B** (not 14B). This was verified
by checking HuggingFace model configs.

### AWQ Quantization: Not Needed

Initially planned to build a custom container with `autoawq` for
INT4 quantization. **Unnecessary** because:
- vLLM 0.8.4 has built-in AWQ kernel support
- No official AWQ-quantized Granite 4.1 models exist
- BF16 (no quantization) fits on 4× L4 for both 8B and 30B
- HuggingFace token not needed (Granite is Apache 2.0, not gated)

## InstructLab Container as vLLM Runtime

The `registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0` image
bundles vLLM 0.8.4 but uses `ilab` as its default entrypoint.

### Required Overrides

```bash
podman run -d \
  --entrypoint python3 \
  registry.redhat.io/rhelai1/instructlab-nvidia-rhel9:1.5.0 \
  -m vllm.entrypoints.openai.api_server \
  --host 0.0.0.0 --port 9000 \
  --model ibm-granite/granite-4.1-8b \
  --tensor-parallel-size 2 \
  --max-model-len 131072 \
  --gpu-memory-utilization 0.95 \
  --disable-custom-all-reduce \
  --dtype bfloat16
```

### Key Gotchas

| Issue | Detail | Fix |
|-------|--------|-----|
| HF cache path mismatch | Container: `/opt/app-root/src/.cache/huggingface`, Host: `/var/home/cloud-user/.cache/huggingface` | Volume mount mapping |
| Custom allreduce fails | 4× PCIe-only GPUs don't support custom allreduce | `--disable-custom-all-reduce` |
| No SELinux `:Z` needed | rhel-ai doesn't need relabeling on mounts | Omit `:Z` suffix |
| Entrypoint override | Default entrypoint is `ilab`, not vLLM | `--entrypoint python3 ... -m vllm.entrypoints.openai.api_server` |
| Home directory path | `/var/home/cloud-user` not `/home/cloud-user` | Use full path in volume mounts |

## Cold Start Times

Model weights are loaded from disk on every container start.
No GPU memory is preserved across `podman stop` → `podman start`.

| Model | Weights Size | Cold Start Time |
|-------|:------------:|:---------------:|
| g350m (0.35B) | ~700 MB | ~30 seconds |
| g8b-128k (8B, tp=2) | ~16 GB | ~3 minutes |
| g30b-96k (30B, tp=4) | ~55 GB | **~17-20 minutes** |

### Mitigation Options

| Approach | Improvement |
|----------|-------------|
| Keep container running | Zero load time |
| `podman pause` / `unpause` | Instant — GPU memory preserved |
| Pin HF cache to tmpfs/RAM | ~2-3× faster reads (needs 55 GB spare RAM) |

The 30B cold start is dominated by **disk I/O** — EBS volume on AWS,
not local NVMe. Each of the 12 safetensor shards takes ~80-90 seconds.
