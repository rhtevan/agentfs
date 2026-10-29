# No Forward Chaining

LLMs cannot perform forward chaining — the automatic re-evaluation
of rule conditions after state changes during execution.

## The Gap

Rule engines (Drools with Rete, Phreak) maintain persistent
**working memory**. When an action asserts a new fact, the engine
propagates it through all rule conditions, activating any rule
whose left-hand side now matches. This match-fire-assert cycle
repeats until no rules remain on the agenda (quiescence).

LLMs have none of this infrastructure:

| Capability | Rule Engine (Rete/Phreak) | LLM |
|-----------|--------------------------|-----|
| Persistent working memory | ✅ Fact store | ❌ Context window only |
| Re-evaluation after state change | ✅ Automatic propagation | ❌ Single scan |
| Conflict resolution (agenda) | ✅ Salience, recency | ❌ First match, stop |
| Truth maintenance | ✅ Dependency tracking | ❌ None |
| Cycle termination | ✅ Agenda-empty halt | ❌ No agenda concept |

## Why Model Scale Doesn't Fix This

This is not an intelligence or capability limitation. Frontier
models (Claude Sonnet/Opus) fail identically to 14B models on
effect-based rules — both at 0%. The model can explain what
forward chaining is, describe the Rete algorithm, and articulate
why a dependent rule should fire. It just doesn't execute the
re-evaluation cycle during token generation.

The failure is architectural: LLMs generate tokens left-to-right
in a single pass. There is no mechanism to interrupt generation,
assert facts into a structured store, propagate through other
rules, and resume generation with newly activated rules.

## Observed Failure Pattern

```
Rule 1: "hey remember" → write MEMORY.md       (fires ✅)
Rule 3: "writes touched .agents/" → post-write  (never fires ❌)
```

Rule 1 fires because its When clause matches user input (guard).
Rule 3 never fires because its When clause requires Rule 1 to
have already produced a side-effect. The LLM does one scan at
turn start, executes the matched rule, and responds — without
re-scanning.

## Measured Impact

| Template Version | t_r3 Pass Rate (Frontier) | t_r3 Pass Rate (14B) |
|-----------------|---------------------------|----------------------|
| v7.5.1 (effect-based Rule 3) | 0% | 0% |
| v7.6.0 (merged into guard rule) | 100% | 100% |

## Mitigation

The Self-Contained Actions principle (design-spec.md C1):
every rule's Do block must include ALL consequences of its
actions. No rule may depend on a different rule firing after it.

Effect-based rules are eliminated by merging their actions into
the Do blocks of guard rules that produce the triggering
side-effects.

## Future Direction

Platform-level rule engine integration (file-watch triggers,
post-action hooks) would restore forward-chaining capability
by moving rule re-evaluation out of the LLM and into
deterministic infrastructure — the same architectural pattern
as SDM integration for semantic evaluation.

## Related

- [Over-Tooling](./over-tooling.md) — model-level tool selection failures
- [Improvised Recovery](./improvised-recovery.md) — model invents alternatives instead of following rules
- Design constraint C1/C2 in agentfs-setup design-spec.md
- A10 assertion in agentfs-eval template-check.sh
