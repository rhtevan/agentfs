# Deployment Fitting Guide — Applied

This document applies the Deployment Fitting Guide framework to
hosted-model-ctl deployment profiles. For the full methodology,
see the knowledge bundle: `~/.agents/knowledge/deployment-fitting-guide/`.

## Quick Reference

### Formula

```
Deployment Score = (Q × 0.30) + (S × 0.30) + (C × 0.30) + (Z × 0.10)
```

### Interpretation Bands

| Score | Band |
|:-----:|------|
| 85–100 | Production-ready — near cloud parity |
| 70–84 | Viable — suitable for targeted workloads |
| 50–69 | Usable — significant trade-offs |
| < 50 | Gap analysis required |

## Baselines for Current Profiles

### Gen AI Class (all current profiles)

| Trait | Baseline | Value |
|-------|----------|-------|
| Quality | Opus 4.6 | 100% |
| Speed | Opus 4.6 | ~100 tok/s |
| Context | Opus 4.6 | ~200K effective |
| Size | 1 consumer GPU | 24 GB |

### Decision Class (future SDM profiles)

| Trait | Baseline | Value |
|-------|----------|-------|
| Quality | Jev 1.13 | 100% (95.23% arena) |
| Speed | Jev 1.13 | 70ms TTFT |
| Context | Jev 1.13 | 32K |
| Size | 1 consumer GPU | 24 GB |

## Profile Fitting Scores

### rhel-ai

| Profile | Class | Q | S | C | Z | Score | Band |
|---------|-------|:-:|:-:|:-:|:-:|:-----:|------|
| **g8b-fp8-spec-128k** | Gen AI | 60 | 50 | 12 | 27 | **39.3** | Gap analysis |
| g8b-spec-128k | Gen AI | 60 | 22 | 12 | 14 | **29.9** | Gap analysis |

**g8b-fp8-spec-128k breakdown:**
- Quality (60): ~60% of Opus on reasoning, tool calling, instruction following
- Speed (50): ~50 tok/s vs Opus ~100 tok/s (speculative decoding + FP8)
- Context (12): ~24K effective vs 200K (8B model degradation beyond 16–32K)
- Size (27): 88 GB across 4× L4 vs 24 GB baseline

**g8b-spec-128k breakdown:**
- Quality (60): Same model, BF16 — comparable quality
- Speed (22): ~22 tok/s vs 100 tok/s (no CUDA graphs, BF16 weight reads)
- Context (12): Same effective context limitation
- Size (14): ~16 GB target + ~6 GB draft = larger footprint per GPU

### rhtevan-work

| Profile | Class | Q | S | C | Z | Score | Band |
|---------|-------|:-:|:-:|:-:|:-:|:-----:|------|
| **g3b-16k** | Gen AI | 30 | 37 | 7 | 100 | **32.2** | Gap analysis |
| g350m-2k | Gen AI | 5 | 44 | 1 | 100 | **25.0** | Gap analysis |

**g3b-16k breakdown:**
- Quality (30): ~30% of Opus — passes basic tests, can't do complex reasoning
- Speed (37): 37 tok/s vs 100 tok/s
- Context (7): ~14K effective vs 200K (3B model, Q4 quantized)
- Size (100): 3.4 GB on 1 GPU — fits well under 24 GB baseline

**g350m-2k breakdown:**
- Quality (5): Cannot complete real tasks — too small
- Speed (44): 44 tok/s — fast for its size
- Context (1): 2K configured vs 200K
- Size (100): 1.5 GB — minimal footprint

### Qwen3 14B (benchmarked 2026-10-15)

| Profile | Class | Q | S | C | Z | Score | Band |
|---------|-------|:-:|:-:|:-:|:-:|:-----:|------|
| **qw14b-32k** | Gen AI | 70 | 24 | 16 | 55 | **38.0** | Gap analysis |
| **qw14b-40k** | Gen AI | 60 | 41 | 20 | 27 | **39.0** | Gap analysis |

**qw14b-32k breakdown (measured on 2× L4, TP=2):**
- Quality (70): Passes all 7 benchmark tests. Richer output than Granite 8B on
  reasoning, code gen, and multi-step tasks. 14B model with strong benchmarks
  (MMLU ~79%, GPQA ~79%) but not frontier-class.
- Speed (24): 23.5 content tok/s vs 100 tok/s baseline. Half the bandwidth
  (2× L4 = 600 GB/s) and reasoning overhead on short outputs. Agentic use
  measured ~27 tok/s content (short responses have better content ratio).
- Context (16): 32K configured / 200K baseline. Effective context estimated
  ~32K for 14B dense standard attention.
- Size (55): 44 GB (2× L4) / 24 GB baseline. Uses half the hardware of g8b-fp8-spec.

**qw14b-40k breakdown (measured on 4× L4, TP=4):**
- Quality (60): Passes all 7 benchmark tests. Structured skill execution strong
  (75). Unstructured novel tasks weak (50) — hallucinated geolocation and weather
  data without tool verification in agentic session. Blended: 60.
- Speed (41): 41.2 content tok/s vs 100 tok/s baseline. 75% faster than 32k profile.
- Context (20): 40K configured / 200K baseline. 40K is the model's hard limit
  (`max_position_embeddings=40960`, no RoPE scaling). Original 64K target failed.
- Size (27): 88 GB (4× L4) / 24 GB baseline. All GPUs consumed.

**Strategic note:** qw14b-32k leaves GPU 2+3 free for a co-hosted Decision
model. qw14b-40k is 75% faster but consumes all GPUs. Same model quality —
speed vs GPU availability is the trade-off.

## Notes

- Quality scores are estimates from operational experience, not formal
  benchmarks. A standardized task suite would improve precision.
- Context scores use estimated effective context, not claimed/configured.
- Size scores use inverted scaling: `min(100, baseline_GB / deployment_GB × 100)`.
- All self-hosted profiles score low against cloud baselines by design —
  the value proposition is data sovereignty, zero per-token cost, and
  offline capability, which the fitting score does not capture.
