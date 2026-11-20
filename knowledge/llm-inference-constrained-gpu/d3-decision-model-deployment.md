---
type: Decision
title: "D3 Decision Model Deployment on L4 GPUs"
created: 2026-10-15
tags: [d3, decision-model, vllm, gpu, l4, qwen3.5, gdn, cuda-graphs]
evidence: "Deployed on 2×L4 (Ada sm_89, 23 GB each). vLLM 0.32.0rc1, vllm-sr/d3 (27B) and vllm-sr/d3-flash (9B), FP8 quantization."
---

# D3 Decision Model Deployment on L4 GPUs

Decision 3.0 (vllm-sr/d3) is a family of purpose-built Structured Decision
Models on the Qwen3.5 architecture (d3 27B is fine-tuned from `Qwen/Qwen3.8-27B`; d3-flash from Qwen3.5-9B; d3-mini from Qwen3.5-4B — HF `base_model`, verified 2026-11-16). Deploying them on NVIDIA L4 GPUs reveals
several architecture-specific constraints not documented elsewhere.

## D3 Family Sizing

All D3 models use the Qwen3.5 GDN (Gated Delta Networks) hybrid attention
architecture: only 1 in 4 layers uses full attention (with KV cache), the
rest use linear attention (O(1) state). This makes context ~4× cheaper
than standard transformers.

| Model | Params | FP8 Size | Decision Index (text) | Fits 1×L4? |
|-------|:------:|:--------:|:---------------------:|:----------:|
| d3-edge | 0.6B | ~0.6 GB | ~35 | ✅ |
| d3-lite | 1.2B | ~1.2 GB | ~38 | ✅ |
| d3-nano | 2.5B | ~2.5 GB | ~42 | ✅ |
| d3-mini | 4B | ~4 GB | ~48 | ✅ |
| d3-flash | 9B | ~9 GB | 55.8 | ✅ |
| d3 (27B) | 27B | ~13 GB/GPU | 66.26 (SOTA) | ❌ (TP=2 on 2×L4) |

All models have `max_position_embeddings: 262144` (262K).

## CUDA Graph OOM: Vision Encoder Profiling

**Finding:** No D3 model can run with CUDA graphs on L4 GPUs.

The Qwen3.5 architecture includes a vision encoder. During CUDA graph
capture, vLLM profiles the encoder with a fixed allocation of **18.4 GB**
regardless of context length, batch size, or `--gpu-memory-utilization`.

```
Model weights:        13.0 GB (FP8, TP=2)
Vision encoder probe: 18.4 GB (fixed)
Total needed:         31.4 GB
Available per GPU:    23.0 GB
```

This allocation is:
- **Fixed** — does not scale with `--max-model-len` or `--max-num-batched-tokens`
- **Architecture-level** — set by the Qwen3.5 model code, not a vLLM parameter
- **Present on all D3 models** — even d3-flash (9B) OOMs during graph capture

All attempted workarounds failed:
- `--max-model-len 512` → same 18.4 GB allocation
- `--gpu-memory-utilization 0.55` → same allocation
- `--max-num-batched-tokens 512` → rejected: must be ≥ max_model_len
- `--limit-mm-per-prompt '{"image":0,"video":0}'` → same allocation

The only option is `--enforce-eager`, which disables CUDA graphs entirely.

## FP8 KV Cache Incompatibility

**Finding:** `--kv-cache-dtype fp8` crashes on the first request that
touches the vision encoder's attention layers.

```
RuntimeError: quantized KV cache is not supported for encoder attention
```

The FP8 KV cache works for decoder (text) attention but the Qwen3.5
vision encoder uses standard attention that cannot use quantized KV.
The first few requests may succeed (decoder-only paths), then crash
when a request triggers encoder processing.

When it worked (briefly), latency dropped from ~470ms to ~38ms —
confirming that KV cache memory pressure is a major factor. This is
an upstream vLLM limitation that may be resolved in future versions.

## Optimization: expandable_segments

`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` provides a ~20%
improvement on short requests by reducing PyTorch's CUDA memory
fragmentation.

| Config | 2-question latency | 4-question latency |
|--------|:---:|:---:|
| Baseline (enforce-eager) | ~300ms | ~490ms |
| + expandable_segments | **~240ms** | **~470ms** |
| + gpu-mem 0.80 | ~270ms | ~470ms (no change) |

## NextToken vs Purpose-Built SDM

Side-by-side benchmark on identical questions (19 total):

| Model | Accuracy | 4q Latency | Extra GPUs | Decision Index |
|-------|:--------:|:----------:|:----------:|:--------------:|
| qw14b NextToken | 19/19 | 170ms | 0 | ~45-52 (est.) |
| d3-flash 9B | 17/19 | 215ms | 1 | 55.8 |
| d3-27B | 19/19 | 470ms | 2 | 66.26 |

Key observations:
- NextToken on a 14B generalist matched the 27B purpose-built SDM on
  accuracy for these test questions
- D3-Flash (9B) made errors on trick questions that both larger models
  handled correctly
- D3-27B provides better **calibration** — it hedges more appropriately
  on uncertain questions (0.73 vs 0.95 confidence on ambiguous scenarios)
- D3-27B uses a different API schema (`/v1/systemone`) with richer
  score-type response structure (label + confidence on ordinal scales)

## Dedicated SDM: d3-27b-32k on 4×L4 (2026-11-16)

Profile `d3-27b-32k`: TP=4, `--max-model-len 32768`, `--quantization fp8`,
**`--language-model-only`**, port 9000, vLLM nightly (0.32.0rc1.dev190).

**CUDA graphs now work.** `--language-model-only` sets every modality limit to
0, so vLLM skips the vision-encoder profiling that caused the 18.4 GB OOM. Pooling
models get `cudagraph_mode=PIECEWISE` (capture 24 s, 0.07 GiB). KV cache: 10.46 GiB
per GPU (9.5M tokens, 291× concurrency at 32K). Startup 227 s.

**Architecture mapping is automatic.** The HF checkpoint is a bare `Qwen3_5Model`;
vLLM's config converter sees `decision_config.json` and resolves
`D3ForSequenceClassification` (runner `pooling`, `D3Strategy`). Check the log line
`Resolved architecture: D3ForSequenceClassification`.

**Prefix caching is disabled for pooling models** (`enable_prefix_caching=False`).
Each question re-prefills the full state, so latency scales linearly with question
count (~1.6 s per question at ~3K tokens). NextToken models share the state prefix.

| Real AgentFS payload | Qwen3-14B cold | Qwen3-14B warm | **D3-27B (always cold)** |
|----------------------|:---:|:---:|:---:|
| 6q, ~3K-token evidence | 1.29 s | 0.10 s | **9.8 s** |
| 4q, ~3K-token evidence | 1.17 s | 0.07 s | **6.4 s** |
| 6q, ~530-token evidence | 0.43 s | 0.08 s | **1.9 s** |
| 4q, ~520-token evidence | 0.31 s | 0.07 s | **1.2 s** |

**AgentFS accuracy** (`sdm-validate.sh`, 61 skills × quality/observable/operable,
vs saved Qwen3-14B baseline):

| Metric | Qwen3-14B (NextToken) | D3-27B |
|--------|:---:|:---:|
| Ground truth `trace_instrumentation` | 56/61 | **61/61** |
| Ground truth `sdm_delegation` | 53/61 | **59/61** |
| Ground truth total | 109/122 (89.3%) | **120/122 (98.4%)** |
| Uncertain band (score 50) | 16/854 | 39/854 |
| Mean confidence | 0.954 | 0.880 |
| Mean end-to-end per evaluation (quality/operable/observable) | 4.2 / 4.2 / 2.8 s | 6.8 / 5.8 / 3.4 s |

Pass/fail agreement 88.4% (quality 82.0%). Disagreements are mostly D3 passing
where Qwen failed (prose_executability 16, inference_hop_count 11,
sdm_delegation 10) — on the ground-truth dimension D3 is the one that is right.
Largest split: `interface_opacity` (Qwen pass / D3 fail in 29 skills), no
verbatim fact, spot check inconclusive.

**Diagnostics are constant:** `D3Strategy` returns `label_mass=1.0`,
`argmax_is_label=true` — `sdm-evaluate.sh` reliability checks never fire.

## Deployment Recipe

Final config for D3-27B on 2×L4:

```bash
podman run -d \
  --name model-d3-27b-8k \
  --device nvidia.com/gpu=all \
  -e CUDA_VISIBLE_DEVICES=2,3 \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  --net host --shm-size 10G \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  docker.io/vllm/vllm-openai:nightly \
  --model vllm-sr/d3 \
  --tensor-parallel-size 2 \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.95 \
  --quantization fp8 \
  --enforce-eager
```

VRAM: ~20.8 GB / 23.0 GB per GPU. Cold start: ~2.5 min.
