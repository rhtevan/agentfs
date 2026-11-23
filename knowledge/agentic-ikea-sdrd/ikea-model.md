---
type: Model
title: Agentic I.K.E.A. Model
description: Information → Knowledge → Expertise → Action — the agentic AI value chain, with SKILL/OKF composing Knowledge and SESSION/LOG feeding it back via harvest
tags: [ikea, agentic-ai, memory-model, harvest, agentic-sre, methodology]
timestamp: 2026-11-23T09:55:00-05:00
---

# Agentic I.K.E.A. Model

The I.K.E.A. model describes how an agent turns external input into
action, and how it improves itself between tasks. It is slide 8
("Agentic AI - The IKEA Model") of the *Agentic SRE & AI Grid* deck
(Evan Zhang, Red Hat NA Telco SAA, September 2026).

## The acronym

| Letter | Stage | Stereotype | Meaning |
|---|---|---|---|
| **I** | Information | `<<context>>` | Raw input reaching the agent — prompt, files, tool output |
| **K** | Knowledge | `<<persistent memory>>` | What the agent retains across sessions |
| **E** | Expertise | `<<model>>` | The LLM's reasoning applied to information + knowledge |
| **A** | Action | `<<tools>>` | Effects on the world through tool calls |

Main flow (solid arrows): `Information → Knowledge → Expertise → Action`.

## Memory stores

Four stores, named after cognitive memory types:

| Store | Memory type | Relationship |
|---|---|---|
| **SKILL** | Procedure memory | Composes **Knowledge** |
| **OKF** | Semantic memory | Composes **Knowledge** |
| **SESSION** | Working memory | Produced by **Action** |
| **LOG** | Episodic memory | Written from SESSION via **remember** |

Knowledge is not a store of its own. It is the union of SKILL
(how to do things) and OKF (what is true).

## Flows

| Flow | From → To | Label |
|---|---|---|
| Execution | Action → SESSION | (dotted) |
| Retention | SESSION → LOG | **remember** |
| Graduation | SESSION → SKILL | **harvest** |
| Graduation | SESSION → OKF | **harvest** |
| Graduation | LOG → SKILL | **harvest** |
| Graduation | LOG → OKF | **harvest** |

Key property: **Knowledge grows only through harvest.** `remember`
writes episodic memory (LOG), not Knowledge. Episodic entries must be
distilled (harvested) into procedures (SKILL) or facts (OKF) before
they influence future Expertise.

## Two regions

| Region | Span | Meaning |
|---|---|---|
| **External Stimulates** | Information | The only input from outside the agent |
| **Internal Evolution Loop** | Knowledge → Action → SESSION/LOG → harvest → Knowledge | Self-improvement cycle |

## Relation to other deck concepts

The same deck lists three intrinsic GenAI properties that can only be
mitigated: hallucination (mitigated by knowledge base / OKF / RAG),
stochasticity (harness, guardrails, CNL, watchdog), and sycophancy
(self-challenge, verifier, multi-model). The OKF arm of Knowledge is
the hallucination mitigation.

See [I.K.E.A. → AgentFS Mapping](./ikea-agentfs-mapping.md) for how
each store and flow is implemented.

# Citations

[1] `~/Downloads/Agentic SRE & AI Grid.pdf`, slide 8 "Agentic I.K.E.A. Model"; slide 3 "The Intrinsic properties of Gen AI".
