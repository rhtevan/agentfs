---
type: Lesson
title: Rule Ordering by Frequency, Not Lifecycle
description: Ordering agent rules by operational frequency and criticality improves adherence over lifecycle-based ordering
tags: [context-engineering, agentfs, rules, attention, ordering]
timestamp: 2026-09-29T18:06:00-04:00
---

# Rule Ordering by Frequency, Not Lifecycle

## The Problem

AgentFS v6 ordered rules by lifecycle phase:
1. Session start
2. Per-message dispatch
3. Before reading
4. Before writing
5. Before responding
6. Always

This is human-readable but works against attention dynamics. Within
the AGENTS.md block (Layer 2), earlier rules get more attention than
later rules. Lifecycle ordering placed infrequent rules (session start)
before high-frequency rules (post-write, pre-flight).

## The Evidence

During the v7 implementation session itself, the Post-Write and
Pre-Flight rules (at positions 5–6 with NORMAL priority) were
skipped. The model prioritized task execution over procedural
guardrails that were buried behind higher-priority rules it
encountered less frequently.

## The Fix (v7.1.0 → v7.2.0)

Reordered by operational frequency. Severity tags removed in v7.2.0
after empirical evidence showed no measurable effect on model
adherence — ordering alone is the mechanism.

| Position | Rule | Frequency |
|:--------:|------|-----------|
| 1 | Signal Dispatch | Every `hey` message |
| 2 | Pre-Flight | Every multi-step task |
| 3 | Post-Write | Every `.agents/` write |
| 4 | Session Canary | Session start + periodic |
| 5 | Conflict Resolution | Occasional |
| 6 | Checkpoint | Infrequent |
| 7 | Scope Rules | Infrequent |
| 8 | Path Hygiene | Infrequent |

## The Principle

**Order rules so that the most frequently triggered rules are
encountered first during the model's initial scan of the instruction
block.** Position in token stream is the primary attention mechanism.
Severity annotations were removed in v7.2.0 — no controlled evidence
they influence model behavior beyond what ordering already provides.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: Context Landscape Analysis | Post-Write/Pre-Flight skipped at NORMAL priority; promoted to HIGH in v7.1.0 |

## Implications

- Rules the model encounters first get better adherence
- Ordering IS priority — no separate severity annotations needed
- Use named rule references, not numbered — names are stable when
  order changes
- Lifecycle grouping is useful for human documentation, not for
  model consumption
