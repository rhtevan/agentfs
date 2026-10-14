---
title: Weighted Scoring System
parent: deployment-fitting-guide
created: 2026-10-14
tags: [deployment, evaluation, scoring, formula, interpretation]
---

# Weighted Scoring System

A single aggregate score for comparing deployments within the same
class, computed from the four trait scores weighted to reflect
user experience and trait correlations.

## Formula

```
Deployment Score = (Q × 0.30) + (S × 0.30) + (C × 0.30) + (Z × 0.10)
```

Where:
- **Q** = Quality score (% of class baseline)
- **S** = Speed score (% of class baseline)
- **C** = Context score (% of class baseline, effective not claimed)
- **Z** = Size score (% of class baseline, inverted — smaller = higher)

## Weight Rationale

### Why 0.30 / 0.30 / 0.30 / 0.10?

The three user-facing traits (Quality, Speed, Context) share equal
weight at 0.30 each. Size is de-weighted to 0.10.

**Why Size is only 0.10:**
Size positively correlates with both Quality and Context (RULER
paper: Yi-34B >> Yi-6B on same training data, for both quality
at 4K and context degradation rate). Giving Size heavy weight
would triple-count the same underlying advantage — model capacity.
A bigger model already scores higher on Quality and Context;
rewarding it again on Size over-inflates large-model scores.

**Why Quality doesn't get extra weight:**
Quality is the most important trait — wrong output causes harm.
But at 0.30 in a balanced scheme, it already has 3× the influence
of Size (0.10). Increasing Quality weight would under-represent
Speed and Context, which are genuinely independent signals that
users feel.

**Why equal weights for Q/S/C:**
We lack empirical data to justify one being more important than
another across all use cases. Interactive workloads favor Speed;
batch workloads favor Quality; document-heavy workloads favor
Context. Equal weights avoid encoding a use-case assumption into
the formula.

## Small Model Reward

The scoring naturally rewards efficient deployments. A small model
that achieves high quality scores well on both Quality (high) and
Size (high, because inverted). A large model with mediocre quality
gets penalized on both Quality (low) and Size (low). The formula
rewards engineering efficiency without any special bonus mechanism.

Example:
- 4B model, 99% quality, 8 GB → Q=99, Z=100 → both contribute positively
- 12B model, 94% quality, 13 GB → Q=94, Z=46 → quality close but size penalty

## Interpretation Bands

| Score | Band | Meaning |
|:-----:|------|---------|
| **85–100** | Production-ready | Near cloud parity. Deployment can substitute for baseline in most use cases. |
| **70–84** | Viable | Suitable for targeted workloads. Known gaps but acceptable for specific tasks. |
| **50–69** | Usable | Significant trade-offs. Requires workflow adaptation or architectural mitigation. |
| **< 50** | Gap analysis required | Deployment has fundamental limitations. Identify which trait(s) drag the score and whether architectural changes can compensate. |

## Worked Examples

### Gen AI Class (Opus 4.6 Baseline)

#### Opus 4.6 (the baseline itself)

| Trait | Raw | Score | Weighted |
|-------|-----|:-----:|:--------:|
| Quality | 100% | 100 | 30.0 |
| Speed | ~100 tok/s | 100 | 30.0 |
| Context | ~200K effective | 100 | 30.0 |
| Size | Cloud (0 local) | 100 | 10.0 |
| **Total** | | | **100.0** |

#### `g8b-fp8-spec-128k` (Granite 4.2 8B on 4× L4)

| Trait | Raw | Score | Weighted |
|-------|-----|:-----:|:--------:|
| Quality | ~60% of Opus | 60 | 18.0 |
| Speed | ~50 tok/s | 50 | 15.0 |
| Context | ~24K effective vs 200K | 12 | 3.6 |
| Size | 88 GB / 4 GPU | 27 | 2.7 |
| **Total** | | | **39.3** |

Interpretation: Gap analysis required. Context (12%) is the primary
drag. Architectural mitigation (e.g., SDM + rule engine carrying state
to keep individual LLM calls under 16K) is the recommended approach.

### Decision Class (Jev 1.13 Baseline)

#### Decision 1.0 Lux 9B (hypothetical on 2× L4)

| Trait | Raw | Score | Weighted |
|-------|-----|:-----:|:--------:|
| Quality | 84.38% decisions vs Jev 95.23% | 89 | 26.7 |
| Speed | ~50ms vs Jev 70ms | 100 | 30.0 |
| Context | 16K effective vs Jev 32K | 50 | 15.0 |
| Size | ~18 GB / 2 GPU | 67 | 6.7 |
| **Total** | | | **78.4** |

Interpretation: Viable for targeted workloads. Quality is strong,
speed exceeds baseline. Context is the gap (16K vs 32K).

#### Decider 4B v2 (hypothetical on 1× L4)

| Trait | Raw | Score | Weighted |
|-------|-----|:-----:|:--------:|
| Quality | 94.46% vs Jev 95.23% | 99 | 29.7 |
| Speed | ~47ms vs Jev 70ms | 100 | 30.0 |
| Context | 8K effective vs Jev 32K | 25 | 7.5 |
| Size | ~8 GB / 1 GPU | 100 | 10.0 |
| **Total** | | | **77.2** |

Interpretation: Viable for targeted workloads. Near-baseline quality,
excellent efficiency. Context (25%) is the limiting factor — 8K limits
document-heavy decision workloads.

## Stress Tests

These scenarios validated the weight balance:

| Scenario | Q | S | C | Z | Score | Band | Verdict |
|----------|:-:|:-:|:-:|:-:|:-----:|------|---------|
| Fast but wrong (60% quality, 100% speed) | 60 | 100 | 80 | 90 | 81 | Viable | ✅ Correct — usable for low-stakes batch work |
| Slow but reliable (95% quality, 20% speed) | 95 | 20 | 85 | 70 | 67 | Usable | ✅ Correct — speed is the known trade-off |
| Small and accurate (99% quality, 1 GPU) | 99 | 100 | 25 | 100 | 77.2 | Viable | ✅ Correct — context is the gap |
| Big and mediocre (70% quality, 4 GPU) | 70 | 40 | 60 | 27 | 53.7 | Usable | ✅ Correct — no trait excels |
