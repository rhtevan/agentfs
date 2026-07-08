---
type: Concept
title: "Graph Neural Networks (GNNs) — Overview"
description: "Core concepts, architectures, and applications of Graph Neural Networks for processing graph-structured data."
tags: [gnn, deep-learning, message-passing, graph-convolution]
timestamp: 2026-06-25T19:30:30
---

# Graph Neural Networks (GNNs)

Graph Neural Networks are a class of deep learning models designed to operate on **graph-structured data** — nodes (vertices) connected by edges (relationships).

## Core Mechanism: Message Passing

GNNs follow a message passing (neighborhood aggregation) paradigm:

1. Each node starts with a feature vector
2. **Aggregate**: collect features from neighbors
3. **Update**: combine current features with aggregated neighbor information
4. **Repeat** for K layers — each node incorporates information from K-hop neighbors

```
h_v^(k) = UPDATE( h_v^(k-1), AGGREGATE({ h_u^(k-1) : u ∈ N(v) }) )
```

## Key Architectures

| Architecture | Key Idea | Strengths |
|---|---|---|
| **GCN** | Spectral convolution with mean aggregation | Simple, effective baseline |
| **GAT** | Attention-weighted neighbor aggregation | Differentiates neighbor importance |
| **GraphSAGE** | Sampling + inductive aggregation | Scales to large/dynamic graphs |
| **GIN** | Sum aggregation, maximally expressive under WL test | Strongest theoretical guarantees |
| **MPNN** | General message passing framework | Unifying abstraction |

## Common Tasks

- **Node classification** — label prediction per node
- **Link prediction** — predict missing edges
- **Graph classification** — label entire graphs
- **Graph generation** — produce new graph structures

## Strengths and Limitations

**Strengths:** handles relational data naturally, permutation invariant, captures local and global structure.

**Limitations:** over-smoothing with many layers, scalability challenges on billion-node graphs, expressiveness bounded by the Weisfeiler-Leman test.

## Related Concepts

- [Deep Reinforcement Learning](./deep-rl-overview.md) — often combined with GNNs for decision-making on graphs
- [GNN Architectures for Telecom](../telecom-models/gnn-architectures.md) — telco-specific GNN model adoption
