---
title: Sizing Guidance — Context and Parameters
parent: deployment-fitting-guide
created: 2026-10-15
tags: [deployment, sizing, context-window, parameters, rules-of-thumb, gpu, vram]
---

# Sizing Guidance — Context and Parameters

Practical rules of thumb for choosing model size (parameters) and
context window when planning a deployment. Derived from RULER
benchmark data, operational experience, and the fitting framework.

## Context Window Rules of Thumb

### Rule 1: Effective context = claimed ÷ 4 to ÷ 8 for sub-14B models

For models under 14B parameters with standard attention, budget your
architecture assuming effective context is one-quarter to one-eighth
of the advertised window. Evidence:

- Granite 4.2 8B: claims 128K, effective ~16-32K
- Qwen3 14B: hard limit 40K (`max_position_embeddings=40960`),
  effective ~20-32K estimated
- RULER benchmark: 7B models collapse before 32K on needle retrieval

**Always check `max_position_embeddings` in config.json.** The
claimed context in marketing may differ from the architectural limit.

### Rule 2: If you need >32K effective, you need >30B or cloud

The RULER data is clear: sub-14B models with standard attention
degrade past 32K. The Yi ablation (6B vs 34B, same training) shows
this is a capacity problem, not a training problem. Only models with
hybrid attention (Gated DeltaNet in Qwen3.8) or very large parameter
counts sustain quality at 64K+.

### Rule 3: Architectural mitigation beats bigger context windows

Instead of throwing 128K at an 8B model, use multi-tier architecture:

```
SDM (4K-8K)  → fast, high-quality decisions within effective range
Drools (∞)   → rule engine carries state, never forgets
LLM (16-32K) → called only for generation tasks within its sweet spot
```

Each component operates in its quality zone. The rule engine carries
state instead of bloating LLM context.

### Rule 4: Match context to workload, don't over-provision

VRAM cost of KV cache scales linearly with configured context:

| Context | Approx KV cache (14B FP8) |
|:-------:|:-------------------------:|
| 32K     | ~6 GB                     |
| 40K     | ~8 GB                     |
| 64K     | ~12 GB                    |
| 128K    | ~24 GB                    |

Over-provisioning context wastes VRAM on KV cache the model can't
usefully attend to, while reducing headroom for CUDA graphs and
speculative decoding buffers.

## Parameter Size Rules of Thumb

### Rule 5: The 8B-14B range is the self-hosted sweet spot

| Parameter Size | VRAM (FP8) | GPUs (L4) | Sweet Spot |
|:-:|:-:|:-:|---|
| 3B-4B | 3-4 GB | 1 | Decision/SDM, edge deployment, draft models |
| 7B-9B | 7-9 GB | 1-2 | General-purpose workhorse, best speed/quality on 1 GPU |
| 12B-14B | 12-14 GB | 2-4 | Quality jump over 8B, speculative decoding viable |
| 27B-34B | 27-34 GB | 2-4 | Long-context quality, but ~12 tok/s on L4 (bandwidth-bound) |
| 70B+ | 70+ GB | 4+ | Approaching cloud quality, cost-prohibitive for single-user |

### Rule 6: Bigger is smarter at the same context, but slower

RULER ablation: Yi-34B >> Yi-6B on same training data, for both
quality at 4K and context degradation rate. More parameters = more
internal state = better attention across the window.

But on bandwidth-limited GPUs (L4 GDDR6), 27B+ models run at
~12 tok/s regardless of TP configuration. The quality gain is
real but the speed penalty is severe for agentic workloads.

### Rule 7: Size scoring inverts — don't go bigger without a reason

In the fitting framework, Size is scored as efficiency (smaller =
higher). A 4B model at 99% quality scores well on both Quality
and Size. You need a trait-specific reason to go bigger — usually
Context or Quality on complex tasks.

### Rule 8: Match parameter count to context requirement

Start from the workload's context requirement, not the model size:

```
Need ≤8K effective   → 4B-9B models are sufficient
Need 8K-32K effective → 9B-14B, or 8B with architectural mitigation
Need 32K-64K effective → 27B+ with hybrid attention, or cloud
Need 64K+ effective  → Cloud, or multi-tier architecture
```

## Hardware Interaction: L4 GDDR6

On NVIDIA L4 GPUs (300 GB/s bandwidth, 24 GB VRAM, GDDR6):

```
Theoretical max tok/s = Total Bandwidth / Model FP8 Weight Size

4× L4 (1,200 GB/s) ÷  8 GB (8B FP8)  ≈ 150 tok/s theoretical
4× L4 (1,200 GB/s) ÷ 14 GB (14B FP8) ≈  86 tok/s theoretical
4× L4 (1,200 GB/s) ÷ 27 GB (27B FP8) ≈  44 tok/s theoretical

Actual efficiency: 35-53% of theoretical (TP overhead, attention compute)
```

Speculative decoding improves efficiency by verifying multiple tokens
per weight read. Draft model speculation with same-family models
(Granite 8B+3B, Qwen3 14B+4B) delivers 1.5-2× speedup.

## Measured Deployments (rhel-ai, 4× L4)

| Profile | Params | Context | Content tok/s | Fitting Score |
|---------|:------:|:-------:|:-------------:|:-------------:|
| g8b-fp8-spec-128k | 8B | 128K (24K eff.) | 47 | 39.3 |
| qw14b-32k | 14B | 32K | 23.5 | 38.9 |
| qw14b-40k | 14B | 40K | 41.2 | 39.0 |
| Qwen3.8-27B (solo) | 27B | 128K | 11.8 | 36.0 |
| Gemma 4 31B (solo) | 31B | 128K | 13.4 | 38.5 |

The 8B with speculative decoding remains competitive with 14B+
on overall fitting score despite lower quality, because the speed
advantage (47 vs 23.5-41.2 tok/s) compensates.
