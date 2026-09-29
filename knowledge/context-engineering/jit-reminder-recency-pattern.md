---
type: Pattern
title: JIT-Reminder via Hooks as Recency Strategy
description: Using hook-based tool blocking to inject targeted reminders at the recency zone of the context
tags: [context-engineering, hooks, jit-reminder, recency, dispatch, goose]
timestamp: 2026-09-29T18:06:00-04:00
---

# JIT-Reminder via Hooks as Recency Strategy

Static instruction placement (system prompt, AGENTS.md) anchors
behavior via primacy. But high-frequency rules that are still
violated need **recency reinforcement** — content at the end of
the context, right before generation.

## The Pattern

Use agent runtime hooks to **block incorrect tool calls** and inject
a targeted reminder as the block reason. The block reason appears as
the last tool response in conversation history — the recency zone.

```
User: "hey setup crc monitoring"
  ↓
Hook: detect-hey.sh → flag SET (unmatched signal)
  ↓
Model tries: shell("crc setup...")
  ↓
Hook: enforce-hey.sh → BLOCK
  → Block reason: "Follow Signal Dispatch rule: first tool call
    MUST be search_nodes. You CAN and SHOULD call search_nodes now."
  ↓
Model reads block reason (recency zone) → calls search_nodes
```

## Properties

| Property | Value |
|----------|-------|
| Injection position | Recency zone (last content before generation) |
| Targeting | Contextual — only fires when the specific rule is violated |
| Token cost | 3–5 lines when active, 0 when not triggered |
| Enforcement level | Deterministic — hook blocks the tool call at runtime |
| Graceful degradation | One-shot — flag cleared after first block to prevent infinite loops |

## Comparison with Static Approaches

| Approach | Position | Always present? | Token cost | Enforcement |
|----------|----------|:-:|:-:|:-:|
| System prompt rule | Primacy | Yes | Every turn | Prose only |
| MOIM / persistent instruction | Primacy | Yes | Every turn | Prose only |
| AGENTS.md rule | Primacy | Yes | Every turn | Prose only |
| **JIT-Reminder (hook)** | **Recency** | **Only when violated** | **On violation only** | **Deterministic** |

## Implementation

AgentFS v7 implements this via the `signal-dispatch` plugin:

- `detect-hey.sh` (UserPromptSubmit hook): sets a flag file for
  unmatched `hey` signals
- `enforce-hey.sh` (PreToolUse hook): blocks non-`search_nodes`
  tools when flag is set, injects reminder as block reason
- `patterns.txt`: single source of truth for table-matched
  patterns (no flag set for these)

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: Context Landscape Analysis | Discovery that MOIM has no recency advantage; hook-based reminders achieve actual recency placement |
| agentfs-kgm-skill-dispatch | MEMORY.md | KGM dispatch enforcement architecture |

## Implications

- Static placement (primacy) anchors the full ruleset as baseline
- Dynamic placement (recency via hooks) reinforces what matters NOW
- Combine both: rules in AGENTS.md for anchoring, hooks for enforcement
- Hook-based enforcement is model-agnostic — works on weak models
  that ignore prose instructions
- The pattern generalizes beyond `hey` dispatch — any behavioral rule
  can be hook-enforced if the rule violation is detectable at tool-call time
