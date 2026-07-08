---
type: Ground Truth Labels
title: "RCA Ground Truth Labels"
description: "Per-node classification labels (root_cause, primary_symptom, secondary_symptom, collateral, unaffected) plus fault propagation graph and alarm classification."
tags: [labels, ground-truth, rca, node-classification, propagation-graph]
timestamp: 2026-06-25T16:35:47
---

# RCA Ground Truth Labels

The **supervision signal** for GNN training — what the model learns to predict.

## Source File

- [05_rca_labels.json](./samples/05_rca_labels.json)

## Label Schema (5 classes)

| Label ID | Name | Count | Nodes |
|----------|------|-------|-------|
| 0 | root_cause | 1 | AGG-NYC-E-01 |
| 1 | primary_symptom | 3 | CSG-NYC-E-01, gNB-NYC-E-047, eNB-NYC-E-047 |
| 2 | secondary_symptom | 3 | CORE-RTR-NYC-01, UPF-NYC-01, AMF-NYC-01 |
| 3 | collateral | 3 | gNB-NYC-E-048, CSG-NYC-E-02, AGG-NYC-E-02 |
| 4 | unaffected | 2 | gNB-NYC-E-049, CSG-NYC-E-03 |

## Training Target Formats

The labels are provided in three formats for different GNN tasks:

1. **Node classification** (5-class): `[1, 3, 4, 1, 1, 3, 4, 0, 3, 2, 2, 2]`
2. **Binary root cause detection** (2-class): `[0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0]`
3. **Root cause ranking** (regression): scores from 0.0 to 0.95

## Propagation Graph

A directed causal graph showing how the fault propagated from AGG-NYC-E-01 through 9 edges to 9 downstream elements. See [rca-labels.json](./samples/05_rca_labels.json) `propagation_graph` field.

## Label Source

Derived from [trouble ticket INC00847291](./trouble-ticket.md), validated by senior transport engineer.
