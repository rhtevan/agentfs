---
type: Specification
title: "RCA Labeled Dataset Design"
description: "Structure and design of a realistic labeled RCA dataset for GNN training — topology graph, node/edge KPI time series, alarm sequences, ground truth labels, and PyG construction."
tags: [dataset, labeled-data, pyg, pytorch-geometric, training, graph-construction]
timestamp: 2026-06-25T19:33:48
---

# RCA Labeled Dataset Design

Specification for a realistic labeled dataset suitable for training GNN-based RCA models on telecom networks.

## Dataset Components

A complete labeled incident requires **6 data artifacts**:

| Component | Format | GNN Tensor | Purpose |
|---|---|---|---|
| Network topology | JSON (nodes + edges) | Adjacency matrix `edge_index` [2×E] | Graph structure |
| Node KPI time series | CSV (N nodes × F features × T timestamps) | Node feature matrix `X` [N×F] | Per-node state |
| Edge KPI time series | CSV (E edges × D features × T timestamps) | Edge attribute matrix `edge_attr` [E×D] | Per-link state |
| Alarm sequence | CSV (chronological) | Additional node features or separate graph | Fault signals |
| RCA ground truth | JSON (per-node labels) | Label vector `y` [N] | Supervision signal |
| Source ticket | JSON (trouble ticket) | — | Label provenance |

## Label Schema (5-Class Node Classification)

| Label ID | Name | Definition |
|---|---|---|
| 0 | `root_cause` | The originating faulty element — where the fix should be applied |
| 1 | `primary_symptom` | Directly connected to root cause, first-order effect |
| 2 | `secondary_symptom` | Affected by cascading propagation, 2+ hops |
| 3 | `collateral` | Not in fault path but impacted by traffic rerouting or overload |
| 4 | `unaffected` | Normal operation throughout |

Alternative target formats:
- **Binary**: root_cause (1) vs. everything else (0)
- **Ranking**: continuous score 0.0–1.0 for root cause probability

## Temporal Snapshots

Each incident should include multiple timestamps:

| Phase | What To Capture |
|---|---|
| Normal baseline | All KPIs nominal (reference state) |
| Early degradation | Subtle signals (e.g., rising CRC errors) visible only on root cause element |
| Fault onset | Cascading failures across domains |
| Peak impact | Maximum alarm count, worst KPIs |
| Post-remediation | KPIs recovering to baseline |

## Node Features (19 dimensions typical)

CPU utilization, memory utilization, connected UEs, DL/UL throughput, PRB utilization (DL/UL), RRC connection success rate, E-RAB setup success rate, handover success rate, CQI average, RSRP average, packet loss rate, latency, active alarm count, interface errors/discards, temperature, power draw.

Plus structural features: node type one-hot (7 types), domain one-hot (3 domains) = **29 total features**.

## Edge Features (10 dimensions typical)

Utilization, latency, packet loss, bandwidth, CRC errors, input errors, output drops, link flaps, operational status, edge type.

## Training Set Diversity

A production training set needs **500–5,000 labeled incidents** across fault types:

- Hardware failures (SFP, PSU, line card)
- Configuration errors (OSPF cost, neighbor list)
- Software bugs (VNF memory leak)
- Congestion/capacity events
- Power failures (commercial outage + battery depletion)

**Class balance**: Root cause is ~8% of affected nodes — use focal loss, cost-sensitive weighting, or Graph SMOTE.

**Split strategy**: By **incident** (not by node) — 70% train / 15% val / 15% test.

## Reference Implementation

A working example dataset with all components is available at `knowledge/rca-labeled-dataset/` in this repository. It includes:
- 12-node heterogeneous graph (RAN + transport + core)
- 47-alarm incident with 4 temporal snapshots
- PyTorch Geometric graph construction script
- 8 diverse incident templates for batch training

## Related Concepts

- [Labeled Data Challenge](../rca-pipeline/labeled-data-challenge.md) — why getting labels is hard
- [Labeling Strategies](../rca-pipeline/labeling-strategies.md) — how to build the dataset
- [Data Integration](../rca-pipeline/data-integration.md) — where the raw data comes from
