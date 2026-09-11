---
type: Behavioral Property
title: Multi-Turn Discipline Decay
description: Model progressively drops procedural obligations over long iterative sessions
tags: [llm, behavioral, discipline, multi-turn, context-pressure, memory]
timestamp: 2026-09-10T18:03:00-04:00
---

# Multi-Turn Discipline Decay

## Property

Over long sessions with many turns, the model progressively
deprioritizes "overhead" tasks (logging, changelogs, verification
steps) in favor of the immediate functional goal. Procedural
obligations that were consistently followed in early turns are
skipped in later turns, especially during rapid fix-test-fix cycles.

## Observable Symptoms

- Rule 13 (post-write) obligations skipped after `.agents/` edits
  during debugging iterations
- Changelog entries missing for incremental fixes
- Log entries omitted when the agent is focused on "making it work"
- Post-creation checklist items skipped (version bump, index regen)
- Mixed formatting emerges (different changelog formats within
  same project)

## Root Cause

The model does not maintain persistent state across turns. Each
turn re-evaluates obligations from the rules, but under cognitive
load (complex debugging, multiple tool calls), lower-priority
obligations (audit trail) are dropped in favor of higher-priority
goals (fix the bug). This is analogous to human working memory
limits under cognitive load.

## AgentFS Mitigations

| Mitigation | Location | Mechanism | Type |
|-----------|----------|-----------|------|
| Pre-flight checklist | AGENTS.md Rule 18 | Write action plan before executing; include process obligations; review against rules | **Preventive** |
| `post-write.sh` chain | Rule 13 + agentfs-setup | Single entry point enforces log + changelog + post-edit in one call | Procedural |
| Log drift detection | `post-edit.sh` | Compares file mtimes against latest log entry; warns on unlogged modifications | **Detective** |
| Mandatory Skill Check | skill-gen Post-Creation Checklist | P1–P7 gate before changelog/index/log steps | Gate |
| `merge-changelog-entry.sh` | agentfs-setup | Enforces consistent table format mechanically | Mechanical |

### Pre-Flight Checklist (Primary Mitigation)

The most effective mitigation for discipline decay is making
obligations **visible before execution begins**. The pre-flight
checklist pattern (Rule 18) requires the agent to:

1. **Plan** — write out all steps including process obligations
   (post-write, changelog, version bump) before starting
2. **Review** — check the plan against Rules 13–17 and add any
   missing obligations
3. **Execute** — follow the plan in order, not skipping ahead
4. **Complete** — do not respond until all planned steps are done

This works because it converts a **memory problem** (remembering
to run post-write.sh during a debugging frenzy) into a **checklist
problem** (following a written plan). The same principle behind
aviation pre-flight checklists: pilots don't rely on memory because
knowing and consistently doing under cognitive load are different
things.

## Key Insight

**The agent's session log is not a ledger.** It records everything
that happened but is not structured for checking "what did I modify
but not log?" The defense is layered:

1. **Preventive** — Pre-flight checklist (Rule 18) makes obligations
   visible before execution
2. **Detective** — Drift detection (`post-edit.sh`) catches what
   prevention missed by comparing filesystem state against log state
3. **Corrective** — Agent fixes drift before responding when
   detection warns

No single layer is sufficient. Prevention reduces incidents,
detection catches escapes, correction fixes them.

## Effectiveness

- **Pre-flight checklist** — not yet tested at scale; addresses the
  root cause (obligations not in working memory during execution)
- **Drift detection** — catches 100% of unlogged `.agents/`
  modifications after the fact
- **Remaining gap** — files outside `.agents/` that skills depend on
  but Rule 13 doesn't govern require agent discipline only
