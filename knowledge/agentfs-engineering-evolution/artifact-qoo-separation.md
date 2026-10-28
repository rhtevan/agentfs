---
title: Artifact QOO Separation
parent: agentfs-engineering-evolution
created: 2026-10-27
updated: 2026-10-27
tags: [QOO, artifact, separation-of-concerns, AGENTS.md, measurement]
---

# Artifact QOO Separation

- **Type:** Pattern
- **Status:** Active
- **Source:** Session analysis — discovered while measuring AGENTS.md operability

## Problem

Some skills produce structured artifacts that are consumed by other
models in contexts unrelated to the producing skill's execution.
The producing skill and the produced artifact have different:

- Consumers (executing model vs every model on every turn)
- Correctness criteria (skill workflow vs rule compliance)
- Failure modes (setup errors vs model behavioral variance)
- Measurement frequency (at skill run vs every benchmark run)

Merging their QOO metrics into a single `scores.yaml` conflates
two independent concerns, violating Separation of Concerns.

## Primary Example: agentfs-setup → AGENTS.md

`agentfs-setup` is a skill executed via `hey setup agentfs`. It
scaffolds directories, generates AGENTS.md via `seed-agents-md.sh`,
and runs post-write checks.

AGENTS.md is a generated CNL document loaded as system prompt on
every session of every model across every project. Its operability
is measured by benchmark tests (T1 canary, T2 dispatch, etc.).

| Property | agentfs-setup (skill) | AGENTS.md (artifact) |
|----------|:---------------------:|:--------------------:|
| What | Skill with scripts | Generated CNL document |
| Executor | Model running setup | Every model, every turn |
| Correctness | Files in right places | Model follows rules |
| Failure mode | Missing dir, bad template | Rule ignored, signal rephrased |
| QOO schema | quality + operable | Rule compliance (new) |
| Measurement | At skill execution | Every benchmark run |

## Solution: Sub-Artifact Directory

Skills that produce independently-consumed artifacts store that
artifact's QOO metrics in `artifacts/<name>/` under the skill:

```
~/.agents/skills/agentfs-setup/
├── SKILL.md                    # skill instructions
├── scores.yaml                 # QOO scores for the skill itself
├── scripts/
│   ├── seed-agents-md.sh       # generates AGENTS.md
│   └── ...
└── artifacts/
    └── agents-md/
        ├── scores.yaml         # per-rule benchmark scores for AGENTS.md
        └── baseline.yaml       # baseline metrics snapshot
```

### Directory semantics

- `scores.yaml` at skill root → QOO scores for the skill itself
- `artifacts/<name>/scores.yaml` → benchmark/evaluation scores for the named artifact
- `artifacts/<name>/baseline.yaml` → snapshot of current-state metrics
  (CNL compliance, rule count, conditional blocks, etc.)

### When to use this pattern

A skill needs an `artifacts/` directory when:

1. It produces a structured document consumed by other agents/models
2. That document's operability is measurable independently
3. The document's failure modes differ from the skill's failure modes

Most skills do NOT need this. It applies to:
- `agentfs-setup` → AGENTS.md (system prompt)
- `skill-gen` → generated SKILL.md files (future)
- `goose-setup` → goose configuration files (potential)

### Generalization

The `artifacts/` pattern is a specialization of Separation of Concerns
applied to QOO measurement. It keeps the ownership relationship clear
(agentfs-setup owns AGENTS.md) while allowing independent measurement
and evolution tracking.

## AGENTS.md as a Measurable Artifact

AGENTS.md contains 7 rules. Each rule is independently measurable:

| Rule | Benchmark Test | What It Measures |
|:----:|---------------|-----------------|
| R1 Signal Dispatch | T2, T3 | Keyword extraction + search + load chain |
| R2 Pre-Flight | (future) | Plan production before multi-file changes |
| R3 Post-Write | (future) | post-write.sh execution after .agents/ writes |
| R4 Session Canary | T1 | Canary pattern on turn 1 |
| R5 Conflict Resolution | (not tested) | Position reversal disclosure |
| R6 Checkpoint | (not tested) | checkpoint.sh before destructive ops |
| R7 Scope Rules | (future via T8) | PROJECT vs USER scope compliance |

### Metrics for AGENTS.md artifact QOO

**Structural metrics (Tier 1 — deterministic):**
- Total rules: count of `### N.` headings
- Total lines in rules section
- Action steps per rule (numbered sub-steps)
- Conditional blocks per rule (if/when clauses)
- CNL compliance: passive voice count, sentences per step
- Cognitive load: words per rule, nesting depth

**Behavioral metrics (Tier 2 — from benchmark):**
- Per-rule pass rate on frontier model
- Per-rule pass rate on 14B model
- Per-rule failure mode classification
- Delta between frontier and 14B per rule

## MCACS Assessment Template for AGENTS.md

Each rule can be assessed against the 5 MCACS principles:

| Principle | Question | Red Flag |
|-----------|----------|----------|
| Modularity | Can this rule be changed without affecting others? | Rule references other rules by number |
| Cohesion | Does this rule do exactly one thing? | Multiple concerns in one rule |
| Abstraction | Is the interface unambiguous? | "Use literally" buried in complex sentence |
| Coupling | Does this rule depend on external state? | Rule assumes KGM index structure |
| SoC | Is each concern in exactly one place? | Same concern split across rules |

## Relationship to Benchmark

The benchmark test suite (T1-T9) is already measuring AGENTS.md
artifact operability. The scores belong in the artifact's
`scores.yaml`, not the skill's `scores.yaml`:

```
agentfs-setup/scores.yaml          → "did setup complete correctly?"
agentfs-setup/artifacts/agents-md/
  scores.yaml                      → "did 14B follow R1 correctly?"
```

This keeps the evolution feedback loop clean:
1. Benchmark measures AGENTS.md rule compliance
2. Scores stored in artifacts/agents-md/scores.yaml
3. MCACS attribution identifies which rule to improve
4. Edit seed-agents-md.sh (source template)
5. Regenerate AGENTS.md via sync
6. Re-benchmark → compare scores
