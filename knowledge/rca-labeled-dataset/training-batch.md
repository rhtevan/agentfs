---
type: Training Dataset
title: "Multi-Incident Training Batch"
description: "8 diverse labeled incidents (SFP failure, config error, PSU failure, VNF memory leak, congestion, neighbor list error, power outage, line card failure) for GNN batch training."
tags: [training-batch, fault-diversity, class-balance, incident-catalog, multi-incident]
timestamp: 2026-06-25T16:35:47
---

# Training Batch — 8 Labeled Incidents

Shows the **diversity** needed in a real GNN-RCA training set.

## Source File

- [08_training_batch_example.json](./samples/08_training_batch_example.json)

## Incident Summary

| # | ID | Fault Type | Root Cause | Alarms | UEs | Domain |
|---|------|------------|------------|--------|-----|--------|
| 1 | INC00847291 | HW: SFP degradation | AGG router | 47 | 5,210 | Transport→RAN→Core |
| 2 | INC00852104 | Config: OSPF cost error | AGG router | 23 | 3,400 | Transport→RAN |
| 3 | INC00855678 | HW: Power supply | gNodeB | 12 | 2,800 | RAN |
| 4 | INC00861234 | SW: VNF memory leak | UPF | 35 | 15,000 | Core→RAN |
| 5 | INC00867890 | Congestion: Capacity | gNodeB | 18 | 45,000 | RAN→Core |
| 6 | INC00873456 | Config: Neighbor list | gNodeB | 8 | 800 | RAN |
| 7 | INC00879012 | Power: Commercial outage | CSG | 52 | 8,500 | Transport→RAN |
| 8 | INC00885678 | HW: Line card failure | Core router | 68 | 25,000 | Transport→RAN→Core |

## Class Balance

- **root_cause**: 8 nodes (1 per incident) — ~8% of affected nodes
- Recommended handling: focal loss (γ=2), cost-sensitive weighting, oversampling via simulation

## Training Split

Split by **incident** (not by node): 70% train / 15% validation / 15% test.
