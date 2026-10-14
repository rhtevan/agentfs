---
title: The Four Deployment Traits
parent: deployment-fitting-guide
created: 2026-10-14
tags: [deployment, evaluation, traits, quality, speed, context, size]
---

# The Four Deployment Traits

Four measurable characteristics that matter most in practical deployment
and use of AI models. These traits evaluate the **deployment as a whole**
(model + engine + quantization + hardware), not a single model in isolation.

## The Traits

### 1. Quality

**What it measures:** Output reliability — instruction following, tool
discovery and calling, format compliance, factual accuracy, calibration
at the context length actually used.

**Why it matters:** Wrong output is the only trait that causes *harm*,
not just inconvenience. Users lose trust. Hardest to recover from.

**How to measure:** Score representative task suite against class baseline
(e.g., % of Opus output quality on your workloads).

### 2. Speed

**What it measures:** End-to-end latency as the user experiences it —
TTFT (Time To First Token), TPS (tokens per second), speculative
acceptance rate, cold start time.

**Why it matters:** Users feel every millisecond. The difference between
"tool" and "obstacle." Different workloads have different speed
bottlenecks: TTFT for interactive chat, TPS for long generation,
ms/decision for SDM calls.

**How to measure:** Tok/s for generative models, ms latency for
decision models, measured at deployment level (including speculative
decoding, quantization effects).

### 3. Context

**What it measures:** Effective context window — the length where output
quality stays above your acceptance threshold. Not the claimed/advertised
context length.

**Why it matters:** Limits how much state you can feed per request.
When exceeded, manifests as hallucination, instruction forgetting,
and degraded quality. Users feel the *absence* of context as unexpected
model behavior.

**How to measure:** Effective context from benchmarks (RULER methodology)
or empirical observation on your tasks. Always measure effective, never
trust claimed.

**Key research:**
- RULER (NVIDIA, 2024): Models claiming 32K+ often effective at only
  4K–16K. Smaller models degrade faster — Yi-6B vs Yi-34B on same
  training data showed 34B significantly better at long context.
- Lost in the Middle (Stanford, 2023/TACL 2024): U-shaped attention —
  models attend to beginning and end, degrade in the middle.
- Intrinsic Entropy Scaling (2025): Model state must grow proportionally
  to L^β for effective long-context modeling.

### 4. Size

**What it measures:** Total resource footprint — VRAM consumed, GPUs
required, quantization choices. Answers: "can I run it, and what else
can I co-locate?"

**Why it matters:** Determines what hardware you need, what you can
afford, and whether you have room for additional workloads. Operator
constraint, not directly user-facing.

**How to measure:** Total GPU VRAM consumed by the deployment (including
KV cache, draft models). Scored as efficiency — smaller deployments
that achieve comparable quality score higher.

**Scoring direction:** Inverted — smaller = higher score. A 4B model
on 1 GPU scoring 99% quality is a better engineering outcome than
a 34B model on 4 GPUs scoring 95% quality.

## Correlations Between Traits

The four traits are not independent. Understanding their correlations
prevents double-counting in weighted scoring.

```
Size ──────────► Quality       POSITIVE: bigger model = more capable
  │                            (RULER: Yi-34B >> Yi-6B, same training)
  │
  ├──────────► Context        POSITIVE: bigger model = better effective context
  │                            (RULER: 34B holds at 32K, 7B collapses at 16K)
  │
  └──────────► Speed          NEGATIVE: bigger model = slower
                               (more parameters to read per token)

Context ─────► Quality        POSITIVE then NEGATIVE
                               (more info = better, until capacity exceeded)

Speed ──────── Quality        UNCORRELATED
                               (fast wrong answer is still wrong)
```

**Implication for weighting:** Size should be de-weighted because its
benefits are already captured through Quality and Context scores.
A big model that's high quality and long context gets rewarded
via those traits — giving Size heavy weight would triple-count
the same underlying capacity advantage.

## Traits Considered and Rejected

### Concurrency / Throughput Under Load
Everything changes from 1 user to 10. KV cache pressure, VRAM
contention, latency spikes. Rejected as a standalone trait because:
- Most self-hosted deployments currently serve single users
- Under load, concurrency manifests as degraded Speed and Quality
- Can be added as a fifth trait for production-scale evaluations

### Quantization Tolerance
Same model at FP32/BF16/FP8/Q4 behaves differently. Rejected
because it surfaces through existing traits: Size (FP8 halves
footprint) and Quality (if quantization hurts, quality drops).
Measure the effect, not the mechanism.

### Training Data / Knowledge Cutoff
Matters for general chat, irrelevant for well-architected systems
where the model gets facts from tools, RAG, or rule engines rather
than parametric memory.
