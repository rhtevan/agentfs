---
title: Class-Specific Baselines
parent: deployment-fitting-guide
created: 2026-10-14
tags: [deployment, evaluation, baselines, opus, jev, genai, sdm]
---

# Class-Specific Baselines

Each deployment is scored against the **best-in-class reference** for its
deployment class. Using the wrong baseline produces misleading scores —
a decision model scored against a generative AI baseline will look
artificially weak on traits that don't apply to its workload.

## Baseline Selection Criteria

A valid baseline must be:

1. **Best-in-class** — the quality ceiling users can access today
2. **Commercially available** — a real product, not a research prototype
3. **Experienced by users** — establishes the expectation your deployment
   is measured against ("I've used X, how does this compare?")
4. **Measurable on all 4 traits** — must have known speed, context,
   and resource characteristics

## Defined Classes

### Gen AI (LLM) — Generative language models

Use case: chat, reasoning, code generation, agentic tool calling,
document analysis.

| Trait | Baseline | Value | Rationale |
|-------|----------|-------|-----------|
| **Quality** | Opus 4.6 | 100% | Frontier cloud model, highest general capability |
| **Speed** | Opus 4.6 | ~100 tok/s | Cloud-served throughput, user's mental model of "normal fast" |
| **Context** | Opus 4.6 | ~200K effective | Reliably handles ~200K tokens with quality |
| **Size** | Single consumer GPU | 24 GB (1 GPU) | "Can I run it on one card?" — the smallest useful self-hosted unit |

### Decision (SDM) — Semantic Decision Models

Use case: classification, routing, scoring, policy decisions,
typed structured output (choice/noul/score).

| Trait | Baseline | Value | Rationale |
|-------|----------|-------|-----------|
| **Quality** | Jev 1.13 | 100% (95.23% arena) | Highest decision accuracy, commercially available hosted service |
| **Speed** | Jev 1.13 | 70ms TTFT | Median latency for hosted Jev; establishes speed expectation |
| **Context** | Jev 1.13 | 32K (state + question) | Proven effective context for decision workloads |
| **Size** | Single consumer GPU | 24 GB (1 GPU) | Same universal hardware unit |

## Scoring Against Baseline

Each trait is scored as **percentage of baseline** (0–100 scale).

- Score of 100 = matches baseline
- Score above 100 = exceeds baseline (cap at 100 in aggregate)
- Score below 100 = gap from baseline

### Size scoring — inverted

Size is scored as efficiency: **baseline VRAM ÷ deployment VRAM × 100**.
A deployment using 8 GB scores `24/8 × 100 = 300` → capped at 100.
A deployment using 88 GB scores `24/88 × 100 = 27`.

Smaller deployments that achieve comparable quality are rewarded.

## Adding New Classes

When a new deployment class emerges (e.g., embedding models,
vision models, speech), define a baseline following the same
four criteria: best-in-class, commercially available, experienced
by users, measurable on all 4 traits.

Example candidates:
- **Embedding models:** Baseline could be OpenAI text-embedding-3-large
- **Vision models:** Baseline could be GPT-4V / Opus vision
- **Speech models:** Baseline could be Whisper large-v3

Each new class gets its own row in the baseline table and its own
quality benchmark suite.
