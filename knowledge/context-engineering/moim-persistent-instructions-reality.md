---
type: Lesson
title: MOIM / Persistent Instructions — Reality vs. Marketing
description: Goose MOIM claims attention advantage over system prompt but empirically injects at the same primacy zone
tags: [context-engineering, goose, moim, persistent-instructions, attention]
timestamp: 2026-09-29T18:06:00-04:00
---

# MOIM / Persistent Instructions — Reality vs. Marketing

Goose's MOIM (Model-Observed Internal Memory) provides persistent
instructions via `GOOSE_MOIM_MESSAGE_FILE`. The documentation claims
they are "more effective than system prompt instructions for critical
guardrails."

## The Claim

> "They can't be 'forgotten' as the conversation grows"
> "They're more effective than system prompt instructions"

## The Reality

Empirical observation in active sessions shows MOIM content injected
at the **same primacy zone** as AGENTS.md / .goosehints — not at the
recency zone (turn context).

| Property | MOIM (`instructions.md`) | AGENTS.md |
|----------|:-:|:-:|
| Position | Primacy zone (L1) | Primacy zone (L2) |
| Sent every turn | Yes | Yes |
| Survives compaction | Yes | Yes |
| Attention advantage | **None observed** | **None observed** |

The only real difference is **scope**: MOIM is global (all projects),
AGENTS.md is per-project. This is an organizational difference, not
an attention advantage.

## Consequence

Maintaining both MOIM `instructions.md` AND AGENTS.md as parallel
instruction channels creates redundancy with no attention benefit.
AgentFS v7 consolidated to AGENTS.md as sole authority and reduced
`instructions.md` to a one-line pointer.

## What Actually Achieves Recency

Hook-based JIT reminders — specifically the `signal-dispatch` plugin's
`enforce-hey.sh` — inject content as **tool call block reasons**. This
places the reminder at the very end of conversation history, right
before the model's next generation. This IS the recency zone.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: Context Landscape Analysis | Empirical observation of MOIM injection position, channel consolidation analysis |

## Implications

- Do not duplicate instructions across MOIM and AGENTS.md
- Use MOIM only for truly global instructions that apply to every project
- For recency-zone enforcement, use hooks (JIT reminders), not MOIM
- The "persistent" in persistent instructions means "re-injected every
  turn" — but AGENTS.md is also re-injected every turn
