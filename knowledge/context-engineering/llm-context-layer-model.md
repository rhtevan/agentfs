---
type: Pattern
title: LLM Context Layer Model
description: Layered model of how instructions reach a stateless LLM per turn in agent frameworks
tags: [context-engineering, llm, attention, agent-framework, goose]
timestamp: 2026-09-29T18:06:00-04:00
---

# LLM Context Layer Model

LLMs are stateless. Every turn, the agent runtime assembles a complete
context payload and sends it as one request. The payload has a consistent
layered structure.

## Layer Stack

| Layer | Content | Position | Injection |
|-------|---------|----------|-----------|
| L0 | System prompt (identity, tool schemas, extension instructions, skills list) | Front | Every turn (runtime) |
| L1 | Global hints (global .goosehints, MOIM) | After L0 | Every turn (runtime) |
| L2 | Project hints (AGENTS.md, SOUL.md) | After L1 | Every turn (runtime) |
| L3 | Conversation history | Middle | Every turn (grows, compacts) |
| L4 | Turn context (timestamp, working directory) | Before user message | Every turn (runtime) |
| L5 | Current user message | Last | Every turn (user) |

All layers are sent every turn. The difference between layers is
**position**, not presence.

## Attention Zones

- **Primacy zone (L0–L2):** Front of payload. Benefits from primacy
  bias — models anchor on early content.
- **Decay zone (L3):** Middle. Conversation history grows and pushes
  L4–L5 further back. Most vulnerable to attention loss.
- **Recency zone (L4–L5):** End of payload. Benefits from recency
  bias — last content before generation gets high attention.

The primacy and recency effects are well-replicated across models.
The degree of middle decay is model-specific and has been reduced
in modern long-context models.

## Key Properties

- L0–L2 are at **fixed positions** — they don't drift as conversation grows
- L3 is the only layer that **grows** — it pushes L4–L5 further back
- **Compaction** only affects L3 — L0–L2 are always re-injected fresh
- Within a layer, **position still matters** — rules at the top of
  AGENTS.md get more attention than rules at the bottom

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: Context Landscape Analysis | Full analysis of Goose context assembly, empirical observation of layer positions |

## Implications

- Critical rules belong in L0–L2 (primacy zone) — not in conversation history
- Rule ordering within AGENTS.md matters — high-frequency rules go first
- MOIM/persistent instructions have no attention advantage over AGENTS.md
  when both inject at the same primacy zone
- JIT reminders via hooks achieve actual recency zone placement
