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
| `quality.yaml` | Skill design against MCACS principles | Build time (authoring, audit) | Frontier model computes `qoo-profile.yaml` |
| `operable.yaml` | Structural compliance with Operable architecture | Build time (authoring, audit) | Frontier model computes `qoo-profile.yaml` + `gather-skill-state.sh` |
| `observation.yaml` | Execution correctness — universal agent behavior | Run time (post-execution) | Execution trace from `trace-lib.sh` |

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
| **Semantic** | Requires understanding content meaning | concern count, accidental complexity, CNL compliance | Frontier model (writes `qoo-profile.yaml` at authorship) |

**Build time (Quality + Operable):** The frontier model running
`skill-gen` or `skill-check` already has the full SKILL.md in context.
It computes semantic metrics directly and writes `qoo-profile.yaml`.
`gather-skill-state.sh` computes deterministic facts.
`sdm-evaluate.sh` merges both into compact evidence for SDM.

**Run time (Observation):** Execution traces from `trace-lib.sh` are
structured JSONL with explicit facts. A shell script extracts
deterministic metrics (step count, error count, actions executed).
SDM judges bounded questions on those facts.

No frontier model session needed at run time. No weaker model
self-evaluation. Just scripts + SDM.

### 3. `qoo-profile.yaml` — Per-Skill Semantic Metrics

Written by the frontier model at skill authorship time as part of
the `skill-gen` workflow. Contains semantic metrics that require
content understanding:

```yaml
# <skill>/qoo-profile.yaml — computed by skill-gen at authorship
computed-by: claude-sonnet-4
computed-at: 2026-10-23T21:40:00Z
metrics:
  action_steps: 6
  scripted_steps: 5
  script_coverage_pct: 83
  concern_count: 2
  concerns: [data_gathering, formatting]
  accidental_lines: 12
  total_lines: 95
  accidental_pct: 13
  model_assumptions: 1
  model_assumption_list: [scope_resolution_implicit]
  cnl_violations: 0
  cnl_compliance_pct: 100
```

Recomputed by `skill-evolve` or `skill-check` when the frontier model
audits the skill.

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
2. Runs `sdm-evaluate.sh` for each against `observation.yaml`
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
  operable: 20.5
  observation: null
  band: Redesign
  evaluated: 2026-10-23T21:00:00Z
  by_model:
    claude-sonnet-4: {observation: 96.2, band: Operable}
    qwen3-14b-fp8: {observation: 68.4, band: Re-engineer}
history:
  - version: "2.0.0"
    quality: 35.0
    operable: 18.0
    observation: null
    evaluated: 2026-10-20T15:00:00Z
  - version: "2.1.0"
    quality: 37.8
    operable: 20.5
    observation: {claude-sonnet-4: 96.2, qwen3-14b-fp8: 68.4}
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
| Build time (Quality, Operable) | Frontier model via `skill-gen`/`skill-check` | Model computes `qoo-profile.yaml`, calls `sdm-evaluate.sh` | Yes — frontier |
| Run time (Observable) | `sdm-evaluate.sh` + `evaluate-pending.sh` | Script extracts trace facts, SDM judges | No — script + SDM only |
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
    │   ├── operable.yaml                 ← structural compliance (6 dims)
    │   ├── observation.yaml              ← execution correctness (universal)
    │   ├── sdm-endpoint.md               ← API reference
    │   └── README.md                     ← schema format spec
    │
    └── <skill>/                          ← produced by skill-gen
        ├── SKILL.md                      ← muscle (CNL prose)
        ├── scripts/                      ← bones (source trace-lib.sh)
        ├── CHANGELOG.md
        ├── qoo-profile.yaml             ← semantic metrics (frontier-computed)
        └── scores.yaml                   ← QOO evaluation history (committed)
```

## Relationship to Existing Concepts

- **Operable Skill Architecture:** Observable is a property of an
  Operable Skill — universal evaluation schemas apply to all skills.
- **CECX Observation Schema:** CECX scoring formula consumes the
  observation results. CECX is the aggregation; observation schema
  defines the dimensions.
- **SDM Integration:** SDM Pattern 2 (evaluation engine) implemented
  through this design. SDM receives only pre-computed facts.
- **MCACS Measurement:** Quality schema dimensions map directly to
  MCACS per-principle metrics.
