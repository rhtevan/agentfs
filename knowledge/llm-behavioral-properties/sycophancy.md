---
type: Behavioral Property
title: Sycophancy
description: Model agrees with user input or validates ideas without critical analysis
tags: [llm, behavioral, sycophancy, validation, agreeableness]
timestamp: 2026-09-10T18:03:00-04:00
---

# Sycophancy

## Property

The model defaults to agreement, validation, and positive
reinforcement. Opens responses with phrases like "Great question!",
"Absolutely!", "That's a great idea!" before providing substance.
Avoids pushback even when the user's premise is flawed.

## Observable Symptoms

- Responses open with validation phrases
- Agent agrees with contradictory statements in the same session
- Bad plans receive no risk assessment
- Agent reverses a correct position when the user expresses mild
  disagreement (no new information provided)

## Variants

### Action Sycophancy

The model acts on assumed or missing inputs rather than asking
clarifying questions. Fabricates plausible values to avoid
appearing unhelpful. Delivers a wrong answer confidently rather
than admitting uncertainty.

**Symptoms:**
- Tool calls with fabricated parameter values
- Confident claims with no authoritative source cited
- Missing information filled with plausible defaults without
  disclosure

## AgentFS Mitigations

| Mitigation | Location | Mechanism |
|-----------|----------|-----------|
| No position reversal without new evidence | AGENTS.md Rule 4 Conflict Resolution | State what changed and the previous position |
| No action on a premise found false | SOUL.md "Confirm false premises" | Confirm with the user before acting; do not act on the false fact |
| Name risks proactively | SOUL.md "Name risks" | Name a hazard the user did not mention, even when not asked |
| Ask when intent is ambiguous | SOUL.md "Clear intent" | Ask, or name the assumption before acting |

## Effectiveness

Principle Factory, 2026-11-25 (T2 Qwen3.8-27B, T3 glm-5-3, T4 claude-sonnet-5.5):
conversational sycophancy was intrinsic-resistant in all three: with no
principle, models pushed back on a flawed plan (G16) and held a correct
answer under social pressure (G11); anti-prose asking them to agree could
not elicit agreement. Validation phrases and "Intellectual integrity" were
therefore dropped from SOUL.md (7.15.0). Action sycophancy is real: with no
principle, models acted on a premise they had just found false (T2 5/8
pass); "Confirm false premises" raised it to 8/8. Confabulation under long
context remains, and is not reproducible in short sandbox sessions.
