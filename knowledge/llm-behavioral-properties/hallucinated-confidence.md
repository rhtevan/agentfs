---
type: Behavioral Property
title: Hallucinated Confidence
description: Model states uncertain claims with unwarranted certainty, substituting training data for authoritative sources
tags: [llm, behavioral, hallucination, confidence, memory-substitution]
timestamp: 2026-09-10T18:03:00-04:00
---

# Hallucinated Confidence (Memory Substitution)

## Property

The model presents claims derived from training data with the
same confidence as claims derived from authoritative sources.
It substitutes pattern-matched knowledge for verified facts,
especially for tool-specific configurations, API details, and
version-specific behaviors.

## Observable Symptoms

- States tool syntax or configuration values from training data
  that are wrong for the current version
- Presents architectural claims about systems without citing
  documentation
- Describes API behavior based on similar-but-different APIs
- Provides file paths, port numbers, or URLs that are plausible
  but incorrect
- Answers questions about a project's internals based on
  similar projects in training data

## Variants

### Training Data Anchoring

The model anchors on training data patterns even when given
explicit contradictory evidence. Example: insisting that a
network architecture uses host networking because similar
systems in training data do, despite documentation clearly
stating bridge networking.

## AgentFS Mitigations

| Mitigation | Location | Mechanism |
|-----------|----------|-----------|
| Flag low confidence | SOUL.md | "At the top, not buried in a footnote" |
| No action on assumed inputs | AGENTS.md Rule 17 | State what's missing, ask before acting |
| goose-doc-guide skill | Skill signal | "MUST read relevant docs before answering; MUST NOT rely on training data" |
| web-search skill | Skill signal | Search for current information when training data is insufficient |

## Key Insight

The most dangerous form is when the model is confidently wrong
about something the user cannot easily verify — internal
architecture details, security properties, or subtle
configuration interactions. AgentFS mitigations work best when
the agent self-identifies uncertainty, which requires the identity
directives in SOUL.md to override the default confidence bias.

## Effectiveness

SOUL.md directives reduce but do not eliminate the behavior.
The model still occasionally presents uncertain claims without
flagging them, especially when the claim is tangential to the
main task (buried in a longer response). The goose-doc-guide
skill is effective for Goose-specific questions but cannot be
applied to all domains.
