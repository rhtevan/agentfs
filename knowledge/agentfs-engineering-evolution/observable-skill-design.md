---
title: Observable Skill Design
parent: agentfs-engineering-evolution
created: 2026-10-22
updated: 2026-10-23
tags: [observable-skill, SDM, evaluation, trace, schemas, QOO]
---

# Observable Skill Design

- **Type:** Pattern
- **Status:** Active
- **Source:** Session analysis — designing SDM-integrated skill observation
  with minimal execution impact and efficient score persistence

## Summary

An Observable Skill produces structured execution traces that are
scored by SDM on demand. All three evaluation schemas (Quality,
Operable, Observation) are universal — no per-skill schemas needed.
Evaluation is async, triggered by `skill-evolve` or manual command.
Scores persist per-skill in `scores.yaml`.

## Core Design Decisions

### 1. Three Universal Schemas (QOO)

All schemas are universal, centrally maintained at
`~/.agents/skills/schemas/`:

| Schema | What It Evaluates | When | Evidence Source |
|--------|-------------------|------|----------------|
| `quality.yaml` | Skill design against MCACS principles | Build time (authoring, audit) | `gather-skill-state.sh` + SDM evaluation |
| `observable.yaml` | Measurement readiness — trace instrumentation, CNL, anti-fabrication, SDM delegation (4 dims) | Build time (authoring, audit) | `gather-skill-state.sh` + SDM evaluation |
| `operable.yaml` | Build-time structural readiness (BMBT, 4 dims) + runtime execution correctness (CECX, 7 dims) | Build time + Run time | BMBT: filesystem + SDM. CECX: execution trace from `trace-lib.sh` |

**Why universal, not per-skill:** Most observation dimensions apply to
every skill (did the agent fabricate data, hallucinate, complete all
steps, follow correct order). Only the evidence varies per execution.
One schema to maintain, not 60+.

### 2. Two-Tier Evidence Preparation

SDM has limited context window. Evidence must be compact (~100 tokens),
never raw prose.

| Tier | Type | Examples | Computed By |
|------|------|----------|-------------|
| **Deterministic** | Countable, filesystem-observable | script count, line count, has scripts/, trace_step calls | `gather-skill-state.sh` (shell script) |
| **Semantic** | Requires understanding content meaning | concern count, accidental complexity, CNL compliance | SDM via `sdm-evaluate.sh` (zero-shot bounded judgments) |

**Build time (Quality + Observable):** `gather-skill-state.sh` computes
deterministic Tier 1 facts. `sdm-evaluate.sh` evaluates semantic
dimensions via SDM (1 token/question, ~115-200ms). Results persisted
to `scores.yaml`. No frontier-subjective assessment needed.

**Run time (Operable):** Execution traces from `trace-lib.sh` are
structured JSONL with explicit facts. A shell script extracts
deterministic metrics (step count, error count, actions executed).
SDM judges bounded questions on those facts.

No frontier model session needed at run time. No weaker model
self-evaluation. Just scripts + SDM.

### 3. `scores.yaml` — Per-Skill QOO Scores

Produced by the objective evaluation pipeline:
`gather-skill-state.sh` → `sdm-evaluate.sh` → `scores.yaml`.

No frontier-subjective assessment. SDM is the oracle (1 token/question).
The frontier model is the evaluation toolchain OPERATOR (constructs
SDM requests), not the evaluator.

```yaml
# <skill>/scores.yaml — computed by evaluation pipeline
skill: agentfs-readme-audit
version: "3.0.1"
qoo-qualified: true
qualification-basis:
  - "scripts/gather-state.sh"
  - "CNL-compliant SKILL.md"
  - "Anti-fabrication rules"
latest:
  quality: 72.5
  observable: 85.0
  operable: null  # Populated after runtime trace evaluation
  band: Tunable
  evaluated: "2026-10-27T23:00:00Z"
history: []
```

Recomputed by `skill-evolve` or `skill-check` when the evaluation
pipeline is run.

### 4. Agent-Agnostic Audit Trail

**Decision:** Scripts self-report execution traces via `trace_step()`
function. The LLM does not capture the trace.

**Trace convention:**
- Traces go to `~/.agents/.traces/<skill>-<timestamp>.jsonl`
- The operating model sets `AGENTFS_TRACE` env var before running
  scripts. One instruction.
- Scripts source `~/.agents/scripts/trace-lib.sh` and call
  `trace_init()`, `trace_step()`, `trace_end()`.

```
~/.agents/.traces/
├── readme-audit-20261023T210000.jsonl    ← pending
├── crc-status-20261023T211500.jsonl      ← pending
└── .evaluated/                            ← processed
    └── readme-audit-20261022T170000.jsonl
```

### 5. Async On-Demand Evaluation

**Decision:** No sync evaluation. No Mode A (inline tail-call).
Evaluation runs on demand, never during skill execution.

The operating model's job is to execute the skill and deliver results.
Adding "also evaluate yourself" breaks separation of concerns. The
weaker model never evaluates.

**Three triggers:**

| Trigger | When | How |
|---------|------|-----|
| Manual | Developer wants scores | `bash ~/.agents/scripts/evaluate-pending.sh` |
| Pre-evolve | `skill-evolve` needs scores | `skill-evolve` calls `evaluate-pending.sh` as first step |
| Post-benchmark | T1–T8 run complete | Test harness evaluates all traces |

**`evaluate-pending.sh`:**
1. Finds unevaluated traces in `~/.agents/.traces/`
2. Runs `sdm-evaluate.sh` for each against `operable.yaml`
3. Updates per-skill `scores.yaml`
4. Moves traces to `.traces/.evaluated/`

No cron. No git hooks. No event bus. Files on disk + script that
processes them when asked.

### 6. Score Persistence — `scores.yaml`

**Decision:** Per-skill `scores.yaml` file. Committed to repo (not
gitignored). Separate from CHANGELOG.

CHANGELOG records what changed and why (human/model decisions).
Scores are machine-generated metrics. Different purpose, different
audience.

```yaml
# <skill>/scores.yaml — QOO evaluation history
# Generated by skill-evolve. Do not edit manually.
skill: agentfs-readme-audit
latest:
  version: "2.1.0"
  quality: 37.8
  observable: 20.5
  operable: null
  band: Redesign
  evaluated: 2026-10-23T21:00:00Z
  by_model:
    claude-sonnet-4: {operable: 96.2, band: Operable}
    qwen3-14b-fp8: {operable: 68.4, band: Re-engineer}
history:
  - version: "2.0.0"
    quality: 35.0
    observable: 18.0
    operable: null
    evaluated: 2026-10-20T15:00:00Z
  - version: "2.1.0"
    quality: 37.8
    observable: 20.5
    operable: {claude-sonnet-4: 96.2, qwen3-14b-fp8: 68.4}
    evaluated: 2026-10-23T21:00:00Z
```

CHANGELOG gets one summary line referencing the scores:

```
## v2.1.0 (2026-10-23)
- Extracted gather-state.sh for deterministic data gathering
- QOO scores: Q=37.8 O=20.5 (Redesign → target: Tunable)
```

### 7. Who Evaluates When

| Phase | Who Evaluates | How | Model Required |
|-------|--------------|-----|:-:|
| Build time (Quality, Observable) | Evaluation pipeline | `gather-skill-state.sh` → `sdm-evaluate.sh` → `scores.yaml` | No — script + SDM only |
| Run time (Operable) | `sdm-evaluate.sh` + `evaluate-pending.sh` | Script extracts trace facts, SDM judges | No — script + SDM only |
| Evolve time | Frontier model via `skill-evolve` | Reads `scores.yaml`, diagnoses gaps, produces upgrade spec | Yes — frontier |

## Revised Directory Structure

```
~/.agents/
├── scripts/                              ← shared infrastructure
│   ├── sdm-call.sh                       ← single SDM decision call
│   ├── sdm-evaluate.sh                   ← multi-dimension evaluator
│   ├── trace-lib.sh                      ← trace capture library
│   ├── gather-skill-state.sh             ← deterministic skill analysis
│   └── evaluate-pending.sh              ← batch trace evaluator
│
├── .traces/                              ← execution traces (gitignored)
│   ├── <skill>-<timestamp>.jsonl         ← pending
│   └── .evaluated/                       ← processed
│
└── skills/
    ├── schemas/                          ← universal QOO standards
    │   ├── quality.yaml                  ← MCACS quality (6 dims)
    │   ├── observable.yaml                ← build-time observability (6 dims)
    │   ├── operable.yaml                 ← runtime execution correctness (CECX, universal)
    │   ├── sdm-endpoint.md               ← API reference
    │   └── README.md                     ← schema format spec
    │
    └── <skill>/                          ← produced by skill-gen
        ├── SKILL.md                      ← muscle (CNL prose)
        ├── scripts/                      ← bones (source trace-lib.sh)
        ├── CHANGELOG.md
        └── scores.yaml                   ← objective QOO scores (SDM-evaluated, committed)
```

## AGENTS.md — Non-Observable Artifact

AGENTS.md is a passive system prompt document loaded into the model
context window. It cannot self-instrument or produce audit trails.
Observable is N/A. Quality and Operable apply, but require
**adapted schemas** — the universal SKILL schemas (`quality.yaml`,
`operable.yaml`) measure SKILL-specific properties.

| Property | SKILL | AGENTS.md |
|----------|:-----:|:---------:|
| Quality | ✅ MCACS via SDM (`quality.yaml`) | ✅ MCACS via SDM (`quality-agents-md.yaml` — adapted dims) |
| Observable | ✅ 4 dims (trace, CNL, anti-fab, SDM) | ❌ N/A (passive document, no self-instrumentation) |
| Operable (build) | ✅ BMBT via SDM | ✅ BMBT via SDM (`operable-agents-md.yaml` — bones=scripts, muscle=CNL rules, harness=benchmark) |
| Operable (runtime) | ✅ trace JSONL → CECX | ✅ benchmark → adapted CECX (`operable-agents-md.yaml`) |

AGENTS.md does have BMBT: bones (post-write.sh, checkpoint.sh,
seed-agents-md.sh), muscle (6 CNL rules), controller (model),
harness (benchmark.sh T1-T8). But the evidence source is benchmark
results, not trace JSONL, so the SDM questions must be adapted.

**Build-time Quality:** `gather-skill-state.sh --target agents-md` →
`sdm-evaluate.sh quality-agents-md.yaml` → `artifacts/agents-md/scores.yaml`.
Handled by `agentfs-setup` ("upgrade agentfs").

**Build-time + Runtime Operable:** `benchmark.sh` frontier 1 run +
target 5 runs → `sdm-evaluate.sh operable-agents-md.yaml` →
`artifacts/agents-md/scores.yaml`.
Handled by `agentfs-eval` ("eval agentfs").

**Scores history (2026-10-28 to 2026-10-29):**
- Quality 32.2 → N/A (schema misapplication discovered; adapted schema pending)
- Operable 70.8 → 93.3 (v7.6.0 Self-Contained Actions; raw benchmark pass rate, not SDM-computed)
- Gaps resolved: R3 Post-Write 0%→100%, R7 Scope 40%→100%
- Gaps remaining: T1 Canary 80%, readme-audit dispatch 80% (both model-level)

## Relationship to Existing Concepts

- **Operable Skill Architecture:** Observable is a sibling QOO axis
  that measures measurement readiness — a prerequisite for runtime
  Operable CECX scoring, not a subset of Operable.
- **CECX Scoring:** CECX constitutes the runtime portion of the
  Operable axis. Build-time Operable readiness (BMBT) is measured
  separately. Together they form the complete Operable evaluation.
- **SDM Integration:** SDM Pattern 2 (evaluation engine) implemented
  through this design. SDM receives only pre-computed facts.
- **MCACS Measurement:** Quality schema dimensions map directly to
  MCACS per-principle metrics. SKILL and AGENTS.md use different
  dimension sets adapted to their nature (imperative vs declarative).
