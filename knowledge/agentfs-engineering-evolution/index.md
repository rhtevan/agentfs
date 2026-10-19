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

3. **Skill Evolution.** Realize the concept of a feedback loop where
   an adjuster model or human observes execution of Operable Skills,
   analyzes the gap using CECX scores, suggests an improvement plan,
   and upgrades the skill — all with the help of the runtime harness.

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

## Source

Grounded in David Farley's *Modern Software Engineering* (2021), Part III:
Chapters 9–13. Empirical evidence from Qwen3-14B-FP8 test sessions
(Test qw14b-40k, Test2 qw14b-40k).
