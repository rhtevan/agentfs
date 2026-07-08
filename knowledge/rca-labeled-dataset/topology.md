---
type: Network Topology Graph
title: "Telecom Network Topology — NYC East Cluster"
description: "Heterogeneous graph of 12 network elements (gNBs, eNBs, CSGs, aggregation routers, core router, UPF, AMF) with 14 edges across RAN, transport, and core domains."
tags: [gnn, topology, graph-structure, 5g, adjacency-matrix]
timestamp: 2026-06-25T16:35:47
---

# Network Topology — NYC East Cluster

Defines the **graph structure** that becomes the GNN's adjacency matrix.

## Source File

- [01_topology.json](./samples/01_topology.json)

## Structure

- **12 nodes** across 7 types: gnodeb, enodeb, cell_site_gateway, aggregation_router, core_router, upf, amf
- **14 edges** across 7 types: fronthaul, backhaul, inter_agg, transport_core, n3_interface, n2_interface, xn_interface
- **3 domains**: RAN, transport, core
- Graph type: heterogeneous undirected

## Node Summary

| Node ID | Type | Vendor | Domain |
|---------|------|--------|--------|
| gNB-NYC-E-047 | gnodeb | Ericsson | RAN |
| gNB-NYC-E-048 | gnodeb | Ericsson | RAN |
| gNB-NYC-E-049 | gnodeb | Ericsson | RAN |
| eNB-NYC-E-047 | enodeb | Ericsson | RAN |
| CSG-NYC-E-01 | cell_site_gateway | Cisco | Transport |
| CSG-NYC-E-02 | cell_site_gateway | Cisco | Transport |
| CSG-NYC-E-03 | cell_site_gateway | Cisco | Transport |
| AGG-NYC-E-01 | aggregation_router | Cisco | Transport |
| AGG-NYC-E-02 | aggregation_router | Cisco | Transport |
| CORE-RTR-NYC-01 | core_router | Juniper | Transport |
| UPF-NYC-01 | upf | Nokia | Core |
| AMF-NYC-01 | amf | Nokia | Core |

## Usage

Used by [graph construction script](./graph-construction.md) to build the PyG `edge_index` tensor.
