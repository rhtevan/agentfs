---
title: Operable Runtime — CECX Scoring
parent: agentfs-engineering-evolution
created: 2026-10-19
updated: 2026-10-29
tags: [operable, runtime, measurement, feedback, evolution, CECX, QSCZ]
---

# Operable Runtime — CECX Scoring

- **Type:** Convention
- **Status:** Active
- **Source:** Session analysis — aligning QSCZ deployment fitting with skill execution feedback

## Summary

Four measurable traits for evaluating runtime skill execution
correctness — the runtime half of the Operable axis. Build-time
Operable readiness (BMBT) is measured separately. Together BMBT
and CECX form the complete Operable evaluation.

Modeled after the QSCZ deployment fitting guide. QSCZ evaluates
**deployments** (model + engine + hardware). CECX evaluates
**skill executions** (skill + model + harness) as a unit.

## The Four Observation Traits

### 1. Correctness (Cr)

**What it measures:** Did the skill produce the right result? Steps
completed, output accuracy, no hallucination.

**How to measure:** SDM scores each output dimension as pass/fail with
confidence. Aggregate = % of dimensions passing.

**QSCZ analog:** Quality. Both measure output reliability. Correctness
is weighted higher (0.40 vs 0.30) because a wrong skill result is a
hard failure — there is no "usable but slow" band for wrong answers
in automation.

### 2. Efficiency (Ef)

**What it measures:** How many inference hops, tool calls, and retries
to reach the result?

**How to measure:** Count tool calls, tokens consumed, retries, and
backtrack steps. Score as % of baseline (frontier model run). Lower
count = higher score.

**QSCZ analog:** Speed. Both measure resource cost of reaching the
result. Speed measures wall-clock latency. Efficiency measures
cognitive and compute waste.

### 3. Comprehension (Cm)

**What it measures:** Did the model understand and retain the skill
instructions throughout execution?

**How to measure:** Count steps where the model ignored or forgot an
instruction, made scope errors, or hallucinated references. Zero
deviations = perfect score.

**QSCZ analog:** Context. Both measure effective operational range.
Context measures how much state fits in a window. Comprehension
measures how much instruction the model actually follows across the
execution span.

### 4. Complexity (Cx)

**What it measures:** How much cognitive load does the skill impose on
the operator model?

**How to measure:** Inference Hop Count, Concern Count, Accidental
Complexity Ratio (from MCACS metrics). Lower = higher score. Inverted
scoring — simpler skill scores higher.

**QSCZ analog:** Size. Both are structural properties that manifest
through other traits at runtime. High complexity causes low
comprehension and low efficiency, just as large size correlates with
speed and cost. Both are de-weighted (0.10) to avoid triple-counting.

## Scoring Formula

```
Skill Execution Score = (Cr × 0.40) + (Ef × 0.25) + (Cm × 0.25) + (Cx × 0.10)
```

### Weight Rationale

- **Cr at 0.40:** Wrong output is a hard failure in automation. No
  "usable but wrong" band exists. Weighted higher than QSCZ Quality
  (0.30) because skill results feed downstream actions.
- **Ef at 0.25:** Wasted tool calls and tokens cost money and time.
  Independent signal from correctness — a model can get the right
  answer wastefully.
- **Cm at 0.25:** The key signal for model-skill fit. Low comprehension
  means the skill needs re-engineering for this model tier, regardless
  of whether it stumbled into a correct answer.
- **Cx at 0.10:** Design-time property. Already manifests through Cm
  and Ef at runtime. Same triple-counting argument as QSCZ Size.

## Interpretation Bands

| Score | Band | Action |
|:-----:|------|--------|
| 90–100 | Operable | Skill works reliably on this model tier. No changes needed. |
| 75–89 | Tunable | Specific trait drag identified. Targeted skill upgrade. |
| 50–74 | Re-engineer | Multiple traits failing. MCACS analysis needed. Likely needs script extraction or SDM integration. |
| < 50 | Redesign | Skill architecture fundamentally mismatched to operator model. Rebuild with `skill-gen` using MCACS gates. |

## Failure Attribution — CECX to MCACS

When a score falls below threshold, map the trait gap to an MCACS
principle for upgrade direction:

| Low Trait | Primary MCACS Deficiency | Upgrade Direction |
|-----------|--------------------------|-------------------|
| Low Correctness | Abstraction (leaky interface), Coupling (model-capability assumption) | Extract scripts, add SDM for judgment calls |
| Low Efficiency | Modularity (too many hops), SoC (accidental complexity in prose) | Split into smaller modules, move HOW to scripts |
| Low Comprehension | Cohesion (mixed concerns), Coupling (frontier reasoning required) | Co-locate related steps, simplify CNL prose |
| Low Complexity | Modularity (monolithic), SoC (concerns not separated) | Decompose, delegate to subscripts |

## SDM Role in Observation

SDM serves double duty during observation:

1. **Correctness scoring:** The harness sends `{expected, actual,
   dimension}` to SDM. SDM returns `{pass: bool, confidence: float,
   reasoning: string}`. Aggregate pass rate = Cr score.
2. **Comprehension scoring:** The harness sends instruction-step pairs
   to SDM. SDM evaluates whether the model's action matched the
   instruction's intent. Aggregate = Cm score.

This keeps observation quantitative and model-independent. The adjuster
does not need to be a frontier model to read a structured score card.

## Observation Record Schema

Each skill execution produces a structured observation record:

```json
{
  "skill": "readme-audit",
  "version": "1.2.0",
  "model": "qwen3-14b-fp8",
  "harness": "goose-recipe",
  "timestamp": "2026-10-19T11:30:00Z",
  "scores": {
    "correctness": 72,
    "efficiency": 85,
    "comprehension": 60,
    "complexity": 90
  },
  "aggregate": 73.5,
  "band": "Re-engineer",
  "dimensions": [
    {"name": "scope_resolution", "pass": false, "confidence": 0.92, "reasoning": "Used PROJECT scope instead of USER"},
    {"name": "data_gathering", "pass": true, "confidence": 0.88, "reasoning": "Correctly read index.md"},
    {"name": "output_format", "pass": false, "confidence": 0.95, "reasoning": "Fabricated alignment data"}
  ],
  "efficiency_detail": {
    "tool_calls": 14,
    "baseline_tool_calls": 8,
    "retries": 2,
    "backtrack_steps": 1,
    "tokens_consumed": 12400
  },
  "comprehension_detail": {
    "total_steps": 6,
    "deviations": 2,
    "deviation_types": ["scope_error", "hallucinated_reference"]
  },
  "mcacs_attribution": {
    "primary": "Cohesion",
    "secondary": "Abstraction",
    "upgrade_direction": "Extract gather-state.sh for scope resolution"
  }
}
```

## Implementation Requirements

1. **Observation record schema** — JSON artifact produced per execution.
2. **Harness instrumentation** — Hook into goose session/recipe to
   capture tool call counts, step completions, error events.
3. **SDM correctness endpoint** — Input: expected vs actual per
   dimension. Output: pass/fail + confidence.
4. **Baseline establishment** — Run T1–T8 on frontier model. Record
   CECX scores as 100% baseline (analogous to QSCZ Opus baseline).
