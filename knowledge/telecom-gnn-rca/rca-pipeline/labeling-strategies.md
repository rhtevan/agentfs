---
type: Procedure
title: "Six Labeling Strategies for Telecom GNN RCA"
description: "Practical approaches to building labeled RCA datasets — trouble ticket mining, expert annotation, fault injection, semi-supervised learning, active learning, and causal discovery."
tags: [labeling, nlp, fault-injection, semi-supervised, active-learning, causal-discovery]
timestamp: 2026-06-25T19:33:12
---

# Labeling Strategies for Telecom GNN RCA

Six approaches, from most common to most advanced.

## Strategy 1: Trouble Ticket Mining (Most Common, Most Noisy)

Extract root cause labels from ServiceNow/Remedy tickets using NLP:
1. NLP entity extraction (equipment names, interfaces, fault types)
2. Cause-effect relation extraction
3. Structured RCA label output

**Yield**: ~5% clean labels from raw tickets. Challenges include vague descriptions (~40%), wrong categorization (~20%), copy-paste templates (~15%).

## Strategy 2: Expert Annotation (Highest Quality, Lowest Scale)

SMEs manually review historical incidents with full context (alarm timeline, KPI dashboards, topology view).

**Cost**: $50K–$200K for 1,000 labels. 30-90 minutes per incident. Inter-annotator agreement: 70-85%.

**Use for**: bootstrapping initial model, gold-standard test sets.

## Strategy 3: Fault Injection / Chaos Engineering

Deliberately inject known faults into lab/digital twin. Perfect ground truth, unlimited scale, but synthetic ≠ real.

**Tools**: Simu5G (OMNeT++), ns-3, Cisco CML/GNS3, LitmusChaos, Keysight/Spirent.

## Strategy 4: Semi-Supervised & Self-Supervised Learning

Leverage vast unlabeled data with few labels:
- **Masked node prediction** (GraphMAE) — predict masked KPIs
- **Link prediction** — predict removed edges
- **Graph contrastive learning** — learn robust representations
- **Label propagation** — GNNs naturally propagate sparse labels through graph topology

GNNs are uniquely label-efficient because message passing propagates labels through the network structure.

## Strategy 5: Active Learning

Let the GNN select the most uncertain predictions for human labeling. Reaches ~85% accuracy with only 15% of data labeled (vs. 40%+ for random sampling).

## Strategy 6: Causal Discovery

Learn causal relationships from observational data using Granger causality, PC algorithm, or DAG-GNN. No labels needed — discovers cause-effect structure directly.

## Combined Production Pipeline

1. **Bootstrap** (Month 1-3): Fault injection (2K labels) + expert annotation (500) + NLP mining (3K noisy)
2. **Train** (Month 3-4): Self-supervised pre-training + semi-supervised fine-tuning on ~5K labels
3. **Refine** (Month 4+): Active learning from NOC feedback (20 labels/week)
4. **Closed-loop** (Month 6+): Remediation outcomes as implicit labels

## Emerging: LLM-Assisted Labeling

LLMs (GPT-4/Claude/Llama) extract structured RCA labels from ticket text + alarm logs. Early results: 70-85% accuracy, reducing SME effort by 60-80%.

## Related Concepts

- [Labeled Data Challenge](./labeled-data-challenge.md) — why this is needed
- [GNN+DRL for RCA](./gnn-drl-for-rca.md) — bypassing labels entirely
- [RCA Dataset Design](../training-data/rca-dataset-design.md) — structure of a labeled dataset
