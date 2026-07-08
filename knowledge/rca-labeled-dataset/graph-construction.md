---
type: Script
title: "PyTorch Geometric Graph Construction"
description: "Python script that converts the raw telecom dataset (topology + features + labels) into a PyG Data object ready for GNN training."
tags: [pyg, pytorch-geometric, graph-construction, data-pipeline, gnn-training]
timestamp: 2026-06-25T16:35:47
---

# Graph Construction Script

Bridges raw telecom data → GNN-ready graph tensors.

## Source File

- [07_pyg_graph_construction.py](./scripts/07_pyg_graph_construction.py)

## What It Produces

| Tensor | Shape | Description |
|--------|-------|-------------|
| `x` | [12, 29] | Node features: 19 KPIs + 7 type one-hot + 3 domain one-hot |
| `edge_index` | [2, 28] | 14 undirected edges → 28 directed edges |
| `edge_attr` | [28, 10] | Edge features: 9 KPIs + 1 edge type |
| `y` | [12] | Multi-class labels (5 classes) |
| `y_binary` | [12] | Binary root cause labels |
| `y_ranking` | [12] | Root cause ranking scores |

## Dependencies

- `pandas`, `numpy` (required)
- `torch`, `torch-geometric` (optional — runs in demo mode without)

## Usage

```bash
source .venv/bin/activate
python scripts/07_pyg_graph_construction.py
```

## Also Includes

A minimal `SimpleRCAGNN` model (GCN, 2 layers, 5-class output) for demonstrating a forward pass. Not trained — requires 500+ labeled incidents for meaningful training.
