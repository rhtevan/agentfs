---
title: Tokenomics Alignment — QOO and AI Model Tiering Economics
parent: agentfs-engineering-evolution
created: 2026-10-26
tags: [tokenomics, ROI, model-tiering, FinOps, cost-optimization, QOO]
---

# Tokenomics Alignment

- **Type:** Reference
- **Status:** Active
- **Source:** Analysis of Red Hat AI Tokenomics article (Oct 2026) against
  AgentFS QOO engineering evolution

## Summary

The AgentFS QOO (Quality, Operable, Observable) evolution and the AI
tokenomics model-tiering strategy converge on the same architecture
from different perspectives. QOO arrives from engineering quality
(MCACS, reduce complexity, bounded judgment). Tokenomics arrives
from business economics (route cheap traffic to cheap models, reserve
frontier for high-value work). The result is identical: multi-tier
model routing with well-engineered skills that minimize token
consumption.

## Direct Alignment

| Tokenomics Concept | QOO Implementation |
|--------------------|-------------------|
| Don't fly all-first-class — route tasks to model sized for them | Three model roles: frontier (skill-gen, skill-evolve), mid-range 14B (skill operation), SDM (bounded judgment at 1 token/decision) |
| Model tiering and routing | Operable Skills run on 14B. Frontier reserved for authoring and evolution. SDM handles evaluation. |
| Cheaper tokens won't fix the bill — volume grows faster than price drops | Reduce tokens per execution: Script Coverage ≥80% (scripts = zero tokens), Inference Hop Count ≤2 (fewer LLM calls), SDM at 1 output token per question |
| FinOps Model Choice Quality Score Alignment | CECX scoring: measures gap between required quality and actual model performance per skill per model tier |
| Domain-tuned 30B beats general frontier | SDM as domain-specific evaluator: bounded semantic judgment on well-defined dimensions, not general reasoning |
| Agent complexity multiplies tokens | MCACS Modularity: Inference Hop Count ≤2, Script Coverage ≥80%. Every hop moved to script eliminates tokens. |

## New Ideas from Article

### 1. Gateway / Control Plane

Article describes single AI gateway routing traffic across model tiers
with RBAC, guardrails, token-level observability. QOO currently uses
manual routing (env vars, port numbers). A gateway would make routing
declarative: skill-gen → frontier, skill execution → 14B,
evaluation → SDM, automatically by context.

**Status:** Infrastructure concern beyond current QOO scope. Validates
multi-model architecture but not actionable in current phases.

### 2. Showback — Token Cost as Developer Behavior Change

Article insight: "Once teams see consumption data, showback changes
developer behavior at the API boundary."

**Actionable:** Add token cost tracking to execution traces.
`trace-lib.sh` captures steps. Adding token counts enables:
- "This skill costs 8,200 tokens per execution on 14B"
- "After re-engineering: 3,100 tokens" (62% reduction)
- Concrete ROI metric for MCACS evolution work

Token data is available from SDM responses (`usage.total_tokens`)
and could be inferred from LLM tool call responses.

### 3. Volume Multiplier Quantified

Google: 9.7T tokens/month (May 2024) → 3.2 quadrillion (May 2026).
Bank of America Erica: 3 billion cumulative interactions.

Validates focus on reducing tokens per execution rather than just
making skills "work" on cheaper models. An Operable Skill with 80%
script coverage runs on 14B using dramatically fewer tokens because
scripts consume zero inference tokens.

### 4. Customization as Competitive Advantage

"A smaller, domain-customized model will often beat a general frontier
model on your specific enterprise use case."

Aligns with SDM's role: not a general reasoning model, but a bounded
semantic judgment service. The QOO schemas define the "domain" —
AgentFS skill evaluation. SDM is effectively a domain-customized
evaluator.

## What QOO Covers That Tokenomics Doesn't

| QOO Concept | Tokenomics Gap |
|-------------|---------------|
| Skill evolution feedback loop | Article discusses routing, not improving skills based on execution data |
| Observable execution traces | Article mentions gateway observability, not skill-level execution tracing |
| SDM as evaluation engine | Article treats tiering as cost optimization. QOO uses the tiered model to measure quality of cheaper model's work |
| QOO as design-time quality gates | Article focuses on runtime routing. QOO applies quality standards at authorship so skills are born efficient |

## Key Insight

Well-engineered skills are inherently cheaper to run. MCACS quality
and token economics are not separate concerns — they converge.
Reducing Inference Hop Count reduces tokens. Increasing Script
Coverage eliminates tokens. Using SDM for bounded judgment costs
1 token per decision instead of hundreds for LLM reasoning. The
engineering improvement IS the cost optimization.

## Source

Ashish Nainwal, "AI tokenomics: Balancing open-weight and frontier
models for optimal ROI," Red Hat Blog, October 14, 2026.
https://www.redhat.com/en/blog/ai-tokenomics-balancing-open-weight-and-frontier-models-optimal-roi
