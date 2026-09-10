# LLM Behavioral Properties

Observable behavioral properties of large language models that
degrade agent reliability, and the AgentFS mitigations built to
counter each one. Derived from empirical observations across
multi-session agent development.

## Concepts

* [Sycophancy](./sycophancy.md) - Model agrees without critical analysis; validates bad ideas; action sycophancy fabricates missing inputs
* [Multi-Turn Discipline Decay](./multi-turn-discipline-decay.md) - Procedural obligations dropped over long sessions; audit trail skipped during debugging iterations
* [Partial Completion](./partial-completion.md) - Model completes primary steps but skips documentation, verification, and cleanup; format drift; scope conflation
* [Improvised Recovery](./improvised-recovery.md) - Model invents fix procedures instead of following prescribed troubleshooting; bias toward helpfulness over correctness
* [Hallucinated Confidence](./hallucinated-confidence.md) - Training data substituted for authoritative sources; uncertain claims stated with unwarranted certainty

## Cross-Cutting Themes

Each property is countered by a combination of:

1. **Identity directives** (SOUL.md) — shape the model's default posture
2. **Structural rules** (AGENTS.md) — trigger/action pairs that fire per-message
3. **Mechanical scripts** (agentfs-setup) — deterministic verification that catches what discipline misses
4. **Process gates** (skill-gen principles) — checkpoints that block progression until obligations are met

No single layer is sufficient. The defense is layered: identity
sets the tone, rules prescribe behavior, scripts verify compliance,
and gates block completion until checks pass.
