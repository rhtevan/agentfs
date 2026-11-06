# Context Engineering

11 concepts covering principles and patterns for engineering the instruction context that reaches LLMs in agent frameworks. Derived from empirical analysis of Goose + AgentFS across strong and weak models.

| Concept | Type | Description |
|---------|------|-------------|
| [LLM Context Layer Model](llm-context-layer-model.md) | Pattern | Layered model of how instructions reach a stateless LLM per turn |
| [Instruction Override Semantics](instruction-override-semantics.md) | Lesson | How LLMs resolve conflicting instructions — specialization wins, contradiction is nondeterministic |
| [MOIM / Persistent Instructions Reality](moim-persistent-instructions-reality.md) | Lesson | Goose MOIM (tom extension) injects instructions.md into per-turn `<turn-context>` at recency peak. tom extension required for SOUL delivery. |
| [JIT-Reminder via Hooks](jit-reminder-recency-pattern.md) | Pattern | Using hook-based tool blocking to inject targeted reminders at the recency zone |
| [Rule Ordering by Frequency](rule-ordering-by-frequency.md) | Lesson | Ordering rules by operational frequency improves adherence over lifecycle-based ordering |
| [Goose Message Role Mapping](goose-message-role-mapping.md) | Reference | How Goose maps its internal concepts to OpenAI Chat Completions API message roles |
| [Generation Prior Conflict](generation-prior-conflict.md) | Pattern | How pretraining priors override system prompt rules at generation time |
| [CNL Authoring for Weak Models](cnl-authoring-for-weak-models.md) | Convention | Controlled Natural Language principles for agent instruction authoring. Includes State-Locking Keywords (LOCKED technique for persisting model-generated values across turns). |
| [Assistant Prefix as Continuation](assistant-prefix-continuation.md) | Lesson | Assistant-role prefix messages shift model from generation to continuation mode |
| [Rule Trigger Classification](rule-trigger-classification.md) | Pattern | Guard / inline constraint / effect taxonomy — effect rules are 0% enforceable, litmus test and conversion pattern |
| [Goose Turn-Message Attention Map](goose-attention-map.md) | Reference | U-shaped attention analysis of Goose's per-turn message structure with zone classifications and strategic placement guidance |
