# Context Engineering

> 5 concepts | Principles and patterns for engineering the instruction context
> that reaches LLMs in agent frameworks. Derived from empirical analysis
> of Goose + AgentFS across strong and weak models.

| Concept | Type | Description |
|---------|------|-------------|
| [LLM Context Layer Model](llm-context-layer-model.md) | Pattern | Layered model of how instructions reach a stateless LLM per turn |
| [Instruction Override Semantics](instruction-override-semantics.md) | Lesson | How LLMs resolve conflicting instructions — specialization wins, contradiction is nondeterministic |
| [MOIM / Persistent Instructions Reality](moim-persistent-instructions-reality.md) | Lesson | Goose MOIM claims attention advantage but injects at the same primacy zone as AGENTS.md |
| [JIT-Reminder via Hooks](jit-reminder-recency-pattern.md) | Pattern | Using hook-based tool blocking to inject targeted reminders at the recency zone |
| [Rule Ordering by Frequency](rule-ordering-by-frequency.md) | Lesson | Ordering rules by operational frequency improves adherence over lifecycle-based ordering |
