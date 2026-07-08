---
type: Architecture
title: "GNN+DRL for Unified RCA and Remediation"
description: "Treating RCA and remediation as a single RL problem — the agent learns which actions restore the network, implicitly identifying root causes without labeled data."
tags: [gnn-drl, rca, remediation, reward-function, sim-to-real, autonomous-networks]
timestamp: 2026-06-25T19:33:12
---

# GNN+DRL for Unified RCA + Remediation

## The Key Insight

Instead of separating diagnosis (supervised, needs labels) from remediation (rule-based), treat them as **one unified decision process**:

- The agent doesn't need to explicitly "label" the root cause
- It learns which **actions** (applied **where** in the graph) **restore the network**
- The root cause is implicitly identified by where the successful remediation was applied

## Why Pure DRL Is Hard for RCA (vs. Optimization)

| Dimension | Optimization | RCA |
|---|---|---|
| Reward signal | Immediate, measurable | Delayed, ambiguous |
| Feedback loop | Milliseconds | Hours to days |
| Exploration risk | Low | High — wrong diagnosis worsens things |
| Episode structure | Repeatable | Rare, non-stationary events |

These are engineering challenges, not fundamental impossibilities.

## Architecture

```
Network graph + fault signals → GNN Encoder → Graph embedding
    → DRL Policy (Actor): WHERE to act + WHAT action + HOW (params)
    → Environment executes action → Observe new state → Reward
```

**Two-headed policy output**:
1. **WHERE** — node selection via attention over graph (implicitly ranks root cause candidates)
2. **WHAT** — action type (investigate, mitigate, remediate, escalate)
3. **HOW** — action-specific parameters

## Reward Function Design

```python
reward = 0.0
reward += (sla_violations_before - sla_violations_after) * 10.0  # SLA restoration
reward += (alarms_before - alarms_after) * 1.0                   # Alarm reduction
reward -= time_elapsed * 0.1                                      # Speed bonus
reward -= action_cost[action.type]                                # Prefer less disruptive
reward -= new_issues_caused * 20.0                                # Collateral penalty
```

No labeled root causes needed — the network's response IS the feedback.

## Training: Sim-to-Real Pipeline

1. **Simulator** (safe, unlimited episodes): Train on digital twin with fault injection catalog. 100K+ episodes, 1000+ scenarios.
2. **Shadow Mode** (observe only): Agent proposes actions on live faults without executing. Compare with NOC decisions.
3. **Graduated Autonomy**: Auto-execute low-risk → medium-risk → full autonomy with rollback safety net.

## Explainability Bridge

Even with implicit RCA, NOC engineers need explicit explanations:
- **GNN attention analysis** — which nodes the model attended to most
- **Counterfactual analysis** — "what if we'd acted on a different node?"
- **Action influence graph** — trace message-passing paths to the decision

## Current Industry Status

| Who | Approach | Status |
|---|---|---|
| TM Forum Catalyst C26.0.965 | GNN-Healing Networks, closed-loop | Active (2026) |
| Google Cloud + NetAI | GNN RCA + remediation orchestration | Production |
| Intel O-RAN xApp | GNN+DRL connection management | Research/PoC |
| Academic (JSAC 2023) | Digital Twin + GNN Self-Healing in 6G edge | Research |

## Evolution Path

- **Today** (2024-25): Supervised GNN (RCA) → rule-based remediation playbooks
- **Near-term** (2025-26): Supervised GNN (RCA) → GNN+DRL remediation agent
- **Future** (2027+): Unified GNN+DRL agent — no labels, learns from outcomes

Biggest blocker: **trust and organizational readiness**, not technology.

## Related Concepts

- [Deep RL Overview](../fundamentals/deep-rl-overview.md) — DRL fundamentals
- [Labeling Strategies](./labeling-strategies.md) — the supervised alternative
- [Labeled Data Challenge](./labeled-data-challenge.md) — why label-free matters
