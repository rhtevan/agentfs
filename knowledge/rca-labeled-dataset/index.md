# Telecom GNN RCA Labeled Dataset

A realistic labeled dataset for training Graph Neural Networks to perform
Root Cause Analysis on telecom network faults. Based on a backhaul SFP
failure causing cascading degradation across RAN, transport, and core
domains.

## Quick Start

```bash
source .venv/bin/activate
python scripts/07_pyg_graph_construction.py
```

## Graph Structure

* [Network Topology](topology.md) - 12-node heterogeneous graph (gNBs, routers, core NFs) with 14 edges across 3 domains

## Node & Edge Features (Time Series)

* [Node Features](node-features.md) - 19 KPIs per node at 4 temporal snapshots (baseline → fault → recovery)
* [Edge Features](edge-features.md) - 9 KPIs per edge at 4 temporal snapshots, showing CRC error escalation on fault link

## Fault Data

* [Alarm Sequence](alarm-sequence.md) - 47-alarm storm across 10 network elements over ~47 minutes
* [Trouble Ticket](trouble-ticket.md) - Original ServiceNow ticket INC00847291 with work notes from 4 engineers

## Labels & Training

* [RCA Ground Truth Labels](rca-labels.md) - Per-node 5-class labels (root_cause, primary/secondary symptom, collateral, unaffected) with propagation graph
* [Training Batch](training-batch.md) - 8 diverse incident types for batch training with class balance guidance

## Code

* [Graph Construction Script](graph-construction.md) - Converts raw data to PyTorch Geometric Data object (node/edge feature matrices + labels)

## Data & Code Directories

* [samples/](samples/) - Raw data files (topology JSON, KPI CSVs, alarm sequence, labels, trouble ticket, training batch)
* [scripts/](scripts/) - Graph construction Python script
