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
| No validation phrases | SOUL.md | Identity directive: "Never open with 'Great question', 'Absolutely'" |
| Lead with substance | AGENTS.md Rule 14 | Every response |
| No position reversal | AGENTS.md Rule 15 | Requires new information or logical argument; state what changed |
| Name risks proactively | AGENTS.md Rule 14 | "Name ≥1 risk when evaluating a plan or design" |
| No action on assumed inputs | AGENTS.md Rule 17 | State missing info → ask → do not execute |
| Flag low confidence | SOUL.md | "At the top, not buried in a footnote" |

## Effectiveness

Rules 14 and 15 are effective for conversational sycophancy — the
agent consistently avoids validation phrases and pushes back on
bad plans. Action sycophancy (Rule 17) requires ongoing vigilance
— the model still occasionally fabricates values under context
pressure (long sessions, complex multi-step tasks).
