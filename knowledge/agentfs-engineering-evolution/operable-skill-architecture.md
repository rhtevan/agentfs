---
title: Operable Skill Architecture
parent: agentfs-engineering-evolution
created: 2026-10-19
tags: [operable-skill, architecture, lifecycle, evolution, harness, CNL]
---

# Operable Skill Architecture

- **Type:** Pattern
- **Status:** Active
- **Source:** Session analysis — defining the anatomy and lifecycle of skills
  engineered for mid-range model operability

## Summary

An Operable Skill is a skill designed so that a mid-range (14B-class)
model can execute it reliably (≥90% success rate) with the help of
deterministic scripts and bounded semantic judgment services (SDM).
The architecture separates concerns into four layers: bones (scripts),
muscle (CNL prose), controller (LLM + SDM), and harness (runtime).

## Skill Anatomy — Four Layers

| Layer | Role | Provider | When Created |
|-------|------|----------|--------------|
| **Bones** (scripts) | Deterministic execution: state gathering, data transformation, structured output | `skill-gen` at authorship | Build time |
| **Muscle** (CNL prose) | Orchestration logic: decision routing, step sequencing, output formatting | `skill-gen` at authorship | Build time |
| **Controller** (LLM + SDM) | Executes the skill: LLM orchestrates steps, SDM handles bounded semantic judgments | Runtime environment | Run time |
| **Harness** (runtime) | Execution environment: runs the skill, captures observations, feeds evolution loop | Goose session/recipe CLI | Run time |

### Bones — Deterministic Scripts

Scripts handle everything that does not require judgment:
- Gathering state (file counts, directory structure, git status)
- Resolving scope (USER vs PROJECT)
- Formatting output (tables, reports, diffs)
- Making API calls (SDM endpoint, external services)

Scripts are the skeleton that removes accidental complexity from the
agent's reasoning path. They run identically regardless of which model
operates them.

**MCACS alignment:** Modularity (small, composable units), Separation
of Concerns (HOW is in scripts, not prose), Coupling (zero model-
capability dependency).

### Muscle — CNL Prose Instructions

CNL (Controlled Natural Language) prose tells the controller what to do,
not how to do it:
- Which scripts to run and in what order
- What decisions to make based on script output
- How to format the final response

CNL authoring rules:
1. One instruction per sentence.
2. Active imperative voice.
3. Single vocabulary — one term per concept.

**MCACS alignment:** Abstraction (interface, not implementation),
Cohesion (each block addresses one concern), Coupling (parseable by
mid-range models without frontier reasoning).

### Controller — LLM + SDM

The controller is the operator that executes the skill:
- **LLM** reads the SKILL.md, follows CNL instructions, calls scripts
  via shell, and formats output.
- **SDM** handles bounded semantic judgments that the LLM cannot
  reliably perform (e.g., "does this README section align with the
  actual directory structure?").

The LLM is the orchestrator. SDM is the co-processor for judgment.
Neither replaces the other.

**MCACS alignment:** Separation of Concerns (orchestration vs judgment),
Coupling (SDM decouples quality from model capability).

### Harness — Runtime Environment

The harness provides:
- Execution context (working directory, environment variables, tool access)
- Observation capture (tool call counts, step completions, errors)
- Feedback production (CECX observation records)

Current harness: Goose CLI (`goose session` for interactive,
`goose recipe` for automated). The benchmark test suite (T1–T8)
runs through the harness.

## Skill Lifecycle — Author → Operate → Evolve

Three distinct phases, each with a distinct actor:

```
┌─────────────────────────────────────────────────────────┐
│                    SKILL LIFECYCLE                       │
│                                                         │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐        │
│  │  Author  │────►│ Operate  │────►│  Evolve  │──┐     │
│  │          │     │          │     │          │  │     │
│  │ Frontier │     │ Mid-range│     │ Adjuster │  │     │
│  │  Model   │     │  Model   │     │Model/    │  │     │
│  │          │     │ + SDM    │     │ Human    │  │     │
│  └──────────┘     └──────────┘     └──────────┘  │     │
│       ▲                                          │     │
│       └──────────────────────────────────────────┘     │
│                   Upgrade Spec                          │
└─────────────────────────────────────────────────────────┘
```

### Phase 1 — Author (Build Time)

**Actor:** Frontier/engineering model using `skill-gen`.

**Input:** Skill purpose, target pattern, MCACS constraints.

**Output:** SKILL.md (CNL prose) + scripts (deterministic bones).

**Quality gates:** MCACS P1 checklist:
- Inference Hop Count ≤2
- Script Coverage ≥80%
- Concern Count ≤2 per module
- Accidental Complexity ≤20%
- Interface Opacity (no internal references)
- Model Portability Score ≤2

### Phase 2 — Operate (Run Time)

**Actor:** Mid-range model (14B-class) + SDM, within the harness.

**Input:** User request (e.g., `hey check readme`).

**Output:** Skill result + CECX observation record.

**Success criteria:** Skill Execution Score ≥90 (Operable band).

### Phase 3 — Evolve (Improvement Time)

**Actor:** Adjuster model or human, reading CECX observation records.

**Input:** CECX scores, dimension details, MCACS attribution.

**Output:** Upgrade specification — concrete changes to SKILL.md
and/or scripts.

**Process:**
1. Read observation record.
2. Identify lowest-scoring CECX trait.
3. Map to MCACS deficiency via failure attribution table.
4. Produce upgrade spec: which scripts to add/modify, which CNL
   blocks to rewrite, which SDM calls to introduce.
5. Feed upgrade spec back to Author phase.
6. Re-run through Operate phase.
7. Compare CECX scores: v1.0 vs v1.1.

### Version Progression

Each evolution cycle produces a version bump:

```
v1.0 → Execute → CECX: 73.5 (Re-engineer)
  │
  └─ Evolve: extract gather-state.sh, add SDM scope check
  │
v1.1 → Execute → CECX: 88.5 (Tunable)
  │
  └─ Evolve: simplify CNL step 3, add output template
  │
v1.2 → Execute → CECX: 93.0 (Operable) ✓
```

## Three Roles, Three Models

| Role | Model Tier | Capability Required |
|------|-----------|---------------------|
| **Author** | Frontier (Opus/Sonnet 4) | Complex reasoning, system design, MCACS application |
| **Operator** | Mid-range (14B-class) + SDM | Script orchestration, CNL following, tool calling |
| **Adjuster** | Frontier or experienced human | Gap analysis, MCACS diagnosis, upgrade planning |

The key insight: the operating model does not need to be the authoring
model. A well-engineered skill (high Script Coverage, low Inference
Hops, clear CNL) is executable by a model that could never have
written it.

## Observable — Measurement Readiness

Observable is a sibling QOO axis, not a property of Operable. It
measures whether a skill has the instrumentation to produce trustworthy
runtime evidence — a prerequisite for Operable runtime CECX scoring.

**Three independent axes:**

| Axis | Question | When |
|------|----------|------|
| Quality | Is the design sound? (MCACS) | Build time |
| Observable | Can we know what happened? (measurement readiness) | Build time |
| Operable | Can it run / did it run correctly? (BMBT + CECX) | Build time + Runtime |

Observable measures 4 dimensions:
- **Trace instrumentation** — scripts call `trace_step()`, producing
  agent-agnostic JSONL traces in `~/.agents/.traces/`.
- **CNL compliance** — prose follows Controlled Natural Language rules
  so each instruction maps to one observable action.
- **Anti-fabrication** — explicit guards against model-generated output.
- **SDM delegation** — semantic judgments routed to SDM, not inline
  agent reasoning (Pattern C skills only).

All three evaluation schemas are **universal** at
`~/.agents/skills/schemas/`. The evaluation pipeline
(gather-skill-state.sh + sdm-evaluate.sh) computes objective scores
in `scores.yaml`. Evaluation runs async on demand — never during
skill execution.

See [Observable Skill Design](./observable-skill-design.md) for full
design decisions, evidence tiers, evaluation flow, and persistence.

## Relationship to Existing Concepts

- **MCACS Principles:** Design constraints applied during authorship.
- **MCACS Measurement:** Metrics used in P1 checklist and evolution.
- **Operational Patterns:** Operable Skills convert Pattern C (prose-only)
  to Pattern A (script-backed) through script extraction and SDM.
- **Benchmark Test Suite:** T1–T8 are the first instances of harness-
  observed skill executions.
- **CECX Observation Schema:** The feedback format produced by the
  harness and consumed by the adjuster.
- **SDM Integration:** The co-processor that enables mid-range models
  to handle bounded semantic judgments.
