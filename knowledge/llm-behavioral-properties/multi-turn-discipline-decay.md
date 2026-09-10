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

| Mitigation | Location | Mechanism |
|-----------|----------|-----------|
| `post-write.sh` chain | Rule 13 + agentfs-setup | Single entry point enforces log + changelog + post-edit in one call |
| Log drift detection | `post-edit.sh` | Compares file mtimes against latest log entry; warns on unlogged modifications |
| Mandatory Skill Check | skill-gen Post-Creation Checklist | P1–P7 gate before changelog/index/log steps |
| `merge-changelog-entry.sh` | agentfs-setup | Enforces consistent table format mechanically |

## Key Insight

**The agent's session log is not a ledger.** It records everything
that happened but is not structured for checking "what did I modify
but not log?" The solution is mechanical detection (`post-edit.sh`
drift check) that compares filesystem state against log state —
catching what discipline missed.

## Effectiveness

Drift detection catches 100% of unlogged `.agents/` modifications
after the fact. The remaining gap is for files outside `.agents/`
that skills depend on but Rule 13 doesn't govern. Those require
agent discipline, which remains unreliable over long sessions.
