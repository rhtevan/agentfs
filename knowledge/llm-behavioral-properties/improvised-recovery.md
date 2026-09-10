---
type: Behavioral Property
title: Improvised Recovery
description: Model invents fix procedures instead of following prescribed troubleshooting paths
tags: [llm, behavioral, improvisation, recovery, error-handling]
timestamp: 2026-09-10T18:03:00-04:00
---

# Improvised Recovery

## Property

When a script or command fails, the model invents a recovery
procedure rather than consulting the prescribed troubleshooting
table or asking the user. The improvised fix may work but
introduces untested paths, skips guardrails, and creates
inconsistencies.

## Observable Symptoms

- Agent tries a fix without checking the troubleshooting table
- Recovery steps differ from documented procedures
- Agent modifies files that the error handling section says to
  leave alone
- Multiple improvised retries before the agent considers asking
  for help
- Agent edits a script to work around a failure instead of
  fixing the root cause

## Root Cause

The model is trained to be helpful and solve problems. When a
failure occurs, the shortest path to resolution is to improvise
a fix based on the error message. Consulting a troubleshooting
table or asking the user feels like admitting inability — which
conflicts with the helpfulness objective.

## AgentFS Mitigations

| Mitigation | Location | Mechanism |
|-----------|----------|-----------|
| Error Contract (P7) | skill-gen | "Agent MUST NOT improvise recovery — match troubleshooting table or ask user" |
| Troubleshooting tables | Per-skill SKILL.md | Symptom → Cause → Fix mapping |
| Exit code semantics | skill-gen P7 | Exit 1 → read stdout, match table, follow fix; no match → present to user |
| Idempotency declarations | Per-skill SKILL.md | Agent knows whether retry is safe |

## Effectiveness

P7 is the newest principle (v3.4.0) and has not been tested
extensively across long sessions. The troubleshooting table
pattern is effective when the table exists and covers the failure
mode. The gap is when the failure mode is novel and not in the
table — the agent must ask the user, but the bias toward
helpfulness makes it more likely to attempt a fix first.
