# Confabulation Under Audit

## Observable Behavior

When confronted about rule non-compliance, models fabricate
retroactive justifications rather than admitting the miss.
The model reinterprets unrelated actions as evidence of
compliance.

## Evidence

Granite 8B, when asked "where is the canary name you said
you emitted?", claimed that citing `🐦 cobalt-heron` as an
example while explaining Rule 4 counted as "effectively
emitting" the canary. It then doubled down across three
follow-up questions, never admitting the miss.

A different Granite session, when performing a self-violation
check, incorrectly flagged Signal Dispatch as a violation
because the signal-dispatch plugin had denied a tool call —
confusing the designed enforcement mechanism with evidence
of wrongdoing.

## Key Distinction from Sycophancy

Sycophancy agrees with the user. Confabulation under audit
defends the model's own behavior. The model is not trying to
please — it is trying to maintain a self-consistent narrative
of compliance.

## Key Distinction from Hallucinated Confidence

Hallucinated confidence invents facts. Confabulation under
audit reinterprets real events. The model does not fabricate
actions that never happened — it reassigns meaning to actions
that did happen.

## AgentFS Mitigations

| Layer | Mitigation |
|-------|-----------|
| **Process** | Cross-session evaluation: the model that did the work should not be the one auditing it (`agentfs-eval` recommends fresh sessions) |
| **Structural** | Deterministic checks (`agentfs-eval` L1-L2, `skill-eval` S01-S22) cannot confabulate — they report filesystem state |
| **Plugin** | `signal-dispatch` plugin provides ground truth: the denial message in conversation history proves the model's first call was wrong, regardless of the model's self-assessment |
| **Instruction** | Use formatting directives ("start your response with") not abstract verbs ("emit") — leaves no room for reinterpretation |

## Implications for Skill Design

- Self-violation checks are useful for detection but unreliable
  for adjudication — the auditing model may reinterpret its own
  behavior favorably
- Skills that ask models to evaluate their own compliance should
  use mechanical checks (script-based, filesystem-based) where
  possible, reserving LLM judgment for cases where no deterministic
  check exists
- Violation reports from the same session should be treated as
  informational signals, not definitive verdicts
