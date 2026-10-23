# AgentFS Engineering Evolution

**Applying systems engineering principles (MCACS) to evolve AgentFS from a
frontier-model-dependent system to one operable by mid-range (14B-class)
models at ≥90% success rate.**

## Goals

Three ultimate goals for this Context/AgentFS Evolution:

1. **MCACS-Informed Skill Generation.** Incorporate MCACS systems
   engineering principles into the `skill-gen` skill so that a
   frontier/engineering model produces quality skills operable by
   mid-range (14B-class) operating models combined with SDM.

2. **Operable Skill.** Realize the concept of a skill that combines
   deterministic scripts (bones) with CNL prose instructions (muscle).
   A controller (LLM + SDM) executes the Operable Skill and observes
   results with the help of a runtime harness.

3. **Observable Skill & Skill Evolution.** Realize the concept of
   an Observable Skill that carries its own evaluation criteria
   (observation schema) scored by SDM post-execution. An adjuster
   model or human reads CECX observation scores, analyzes the gap,
   suggests an improvement plan, and upgrades the skill — all with
   the help of the runtime harness.

## Concepts

| Concept | Type | Summary |
|---------|------|---------|
| [MCACS Principles for AgentFS](./mcacs-principles-for-agentfs.md) | Framework | Five interdependent engineering principles mapped to AgentFS gaps and fix directions |
| [MCACS Measurement Framework](./mcacs-measurement-framework.md) | Convention | Per-principle quantitative metrics at 3 levels (component, integration, system) |
| [Operational Pattern Classification](./operational-pattern-classification.md) | Reference | Five skill patterns (A–E), 61 skills classified, cognitive demand and failure mode analysis |
| [Benchmark Test Suite](./benchmark-test-suite.md) | Convention | 8 test cases (T1–T8), 3 model tiers, safety levels, SDM-automated scoring |
| [SDM Integration for AgentFS](./sdm-integration-for-agentfs.md) | Pattern | Semantic Decision Model as skill runtime (Pattern 1) and evaluation engine (Pattern 2) |
| [Observation Schema — CECX](./observation-schema-cecx.md) | Convention | Four measurable traits (Correctness, Efficiency, Comprehension, Complexity) for scoring skill executions, modeled after QSCZ deployment fitting |
| [Operable Skill Architecture](./operable-skill-architecture.md) | Pattern | Four-layer skill anatomy (bones/muscle/controller/harness) and Author→Operate→Evolve lifecycle |
| [Observable Skill Design](./observable-skill-design.md) | Pattern | Agent-agnostic audit trail, two-phase observation, three schema types, score persistence, SDM integration |
| [Implementation Plan](./implementation-plan.md) | Convention | Phased plan: Phase 0 (SDM foundation), Phase 1 (skill-gen), Phase 2 (first conversion), Phase 3 (benchmarking), Phase 4 (maturity) |

## Source

Grounded in David Farley's *Modern Software Engineering* (2021), Part III:
Chapters 9–13. Empirical evidence from Qwen3-14B-FP8 test sessions
(Test qw14b-40k, Test2 qw14b-40k).
