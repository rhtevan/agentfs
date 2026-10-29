# Rule Trigger Classification

A framework for classifying agent rules by when their trigger
condition is evaluable, determining whether an LLM can reliably
enforce them.

## The Three Rule Types

| Type | Trigger Source | When Evaluable | LLM-Enforceable |
|------|---------------|---------------|-----------------|
| **Guard** | User input, session state, task intent | Before execution | ✅ Yes |
| **Inline Constraint** | Specific agent action as it happens | During execution | ✅ Yes |
| **Effect** | Agent's own completed actions | After execution | ❌ No |

### Guard Rules

Triggered by conditions evaluable from the user's message and
current session state. The pre-execution scanner can match these.

Examples:
- "User message starts with `hey`" → Signal Dispatch
- "Task modifies ≥2 files" → Pre-Flight planning
- "Turn 1 of session" → Session Canary

**Pass rate:** 80-100% on frontier, 60-100% on 14B.

### Inline Constraints

Triggered by specific agent actions at the point they occur.
The constraint is part of the same Do block that produces the
action, so it executes as part of the matched instruction sequence.

Examples:
- "After EACH `.agents/` write, run post-write.sh" (in the same
  rule's Do block that governs `.agents/` writes)
- "IMMEDIATELY after edit, verify file is valid" (in the same
  skill step that performs the edit)

**Pass rate:** Same as the guard rule that contains them — the
inline constraint fires because it's part of a Do block that the
model is already executing.

### Effect Rules (Prohibited)

Triggered by conditions that only become true after the agent has
already acted. Require the scanner to re-evaluate — which LLMs
don't do (see: [No Forward Chaining](../llm-behavioral-properties/no-forward-chaining.md)).

Examples:
- "Before sending any response where writes touched `.agents/`"
- "After you have reversed a stated position"

**Pass rate:** 0% on all model sizes. Structurally unenforceable.

## The Litmus Test

For any proposed rule, ask:

> "Can I evaluate this When clause by reading ONLY the user's
> message and current session state, WITHOUT executing any
> action first?"

- **YES** → Guard rule ✅ (use as-is)
- **NO, but evaluable at point of action** → Rewrite as inline
  constraint in a guard rule's Do block ✅
- **NO, requires completed actions** → Effect rule ❌ (prohibited;
  merge into the guard rule that produces the triggering action)

## Conversion Pattern

When an effect rule is identified, convert it by asking:
"Which guard rule produces the side-effect that triggers this?"

Then merge the effect rule's Do block into that guard rule's Do
block as an inline constraint.

```
BEFORE (broken):
  Rule 7: When writing to memories/ → scope to PROJECT
  Rule 3: When writes touched .agents/ → run post-write.sh
  Result: Rule 3 never fires (0%)

AFTER (working):
  Rule 6: When writing to .agents/ →
    1. Scope to PROJECT
    2. Run post-write.sh after each write
  Result: post-write fires as part of Rule 6 (100%)
```

## Measured Results

| Metric | Effect-based (v7.5.1) | Guard+Inline (v7.6.0) |
|--------|----------------------|----------------------|
| Frontier post-write | 0% | 100% |
| 14B post-write | 0% | 100% |
| 14B overall benchmark | 66% | 93% |

## Enforcement

A10 assertion in `template-check.sh` lints all When clauses for
effect-based language patterns (`"where writes touched"`,
`"after you have"`, `"having done"`, `"where you wrote"`).

## Related

- [No Forward Chaining](../llm-behavioral-properties/no-forward-chaining.md) — why effect rules fail
- [CNL Authoring for Weak Models](./cnl-authoring-for-weak-models.md) — writing rules LLMs follow
- [Rule Ordering by Frequency](./rule-ordering-by-frequency.md) — optimizing guard rule scan order
- Design constraints C1/C2 in agentfs-setup design-spec.md
