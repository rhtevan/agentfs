---
type: Lesson
title: Instruction Override Semantics in LLMs
description: How LLMs resolve conflicting instructions across context layers — specialization wins, contradiction is nondeterministic
tags: [context-engineering, llm, instruction-following, identity, override]
timestamp: 2026-09-29T18:06:00-04:00
---

# Instruction Override Semantics in LLMs

LLMs have no formal instruction override mechanism. When instructions
conflict across layers, resolution is attention-weighted heuristics.

## Resolution Patterns

| Scenario | Typical Outcome |
|----------|----------------|
| L0 says X, L2 says Y (direct contradiction) | **Nondeterministic** — primacy gives L0 an edge but not a guarantee |
| L0 is silent, L2 specifies | **L2 wins** — extension, not override |
| L0 is generic, L2 is specific | **L2 usually wins** — model interprets specificity as refinement |

## The Safe Pattern

**Specialization, not contradiction.**

- L0: "You are an AI agent" (generic container)
- L2: "You are an Agentic SRE" (specific role)
- Result: model reads L2 as refining L0 — clean specialization

The anti-pattern is direct contradiction:

- L0: "You are a general-purpose assistant"
- L2: "You are a security auditor"
- Result: model blends unpredictably across turns

## Empirical Finding

Tested with Goose + Granite 8B (weak model): SOUL.md identity
("Agentic SRE") at Layer 2 successfully specialized the Layer 0
identity ("general-purpose AI agent") without conflict. The model
adopted the SOUL.md identity fully and recited all 8 principles.

This held even without customizing the system.md to remove
"general-purpose." Specificity wins over generality even on
weak models.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: Context Landscape Analysis | Identity conflict analysis, empirical testing with Granite 8B |
| goofing-around | Session: AgentFS v7 weaker model test | Confirmed SOUL.md override on weak model |

## Implications

- Design L0 as a neutral container that any L2 identity can specialize
- Never put role-specific instructions in L0 if L2 will define roles
- Multi-identity via profiles works because each SOUL.md specializes
  the same neutral L0
- Nondeterministic conflict resolution is the worst outcome — avoid
  by eliminating contradictions rather than hoping the right one wins
