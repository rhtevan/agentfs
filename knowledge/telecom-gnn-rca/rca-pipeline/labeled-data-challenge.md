---
type: Analysis
title: "The Labeled Data Challenge for Telecom GNN RCA"
description: "Why ground truth RCA labels are the single biggest barrier to deploying GNN-based RCA — root cause ≠ symptom, inconsistent ticketing, cross-domain blindness, and class imbalance."
tags: [labeled-data, ground-truth, trouble-tickets, class-imbalance, challenge]
timestamp: 2026-06-25T19:33:12
---

# The Labeled Data Challenge

The single biggest barrier to production GNN-based RCA in telecom.

## The Fundamental Problem

Network data is abundant — the problem is **ground truth labels**:

- ✅ Billions of PM counter samples, millions of alarms, complete topology
- ❌ "What was the ACTUAL root cause?" — this is what's missing

## Why Labels Are Hard

| Challenge | Impact |
|---|---|
| **Root cause ≠ symptom** | A fiber cut causes 500 RAN alarms, but the ticket says "RAN degradation" |
| **Inconsistent ticketing** | Different NOC engineers describe the same fault differently |
| **Incomplete resolution** | ~30% of tickets closed as "resolved" with no root cause explanation |
| **Multi-cause incidents** | Some outages have 2-3 contributing factors |
| **Silent faults** | Degradations that never trigger alarms or tickets |
| **Cross-domain blindness** | RAN/transport/core teams each see their piece — nobody labels end-to-end |
| **Tribal knowledge** | Senior engineers know patterns but never document them |

## Practical Yield from Trouble Tickets

From 100,000 trouble tickets (typical):
- ~30,000 have extractable root cause info (30%)
- ~10,000 can be mapped to specific NEs + alarms (10%)
- ~5,000 are high-confidence clean labels (5%)

## Class Imbalance

Telecom faults follow a heavy-tailed distribution. Root cause nodes are ~8% of affected nodes in any incident. The rarest faults (cascading failures, <1%) are often the most damaging.

**Mitigations**: Graph SMOTE, focal loss (γ=2), cost-sensitive weighting, over-sampling via simulation, hierarchical classification.

## Related Concepts

- [Labeling Strategies](./labeling-strategies.md) — 6 practical approaches
- [GNN+DRL for RCA](./gnn-drl-for-rca.md) — the label-free alternative
