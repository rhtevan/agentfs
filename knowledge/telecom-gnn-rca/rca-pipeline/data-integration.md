---
type: Architecture
title: "CSP Network Data Integration for GNN"
description: "How a GNN model ingests a CSP's actual network — topology discovery, KPI feature extraction, graph construction engine, and integration patterns."
tags: [data-pipeline, topology, kpi, graph-construction, snmp, gnmi, netconf]
timestamp: 2026-06-25T19:33:12
---

# CSP Network Data Integration for GNN

A GNN model does not magically "know" a CSP's network. It is fed a **continuously updated graph representation** built from existing management systems.

## What a GNN Needs

1. **Graph Structure (Topology)** — what nodes exist, how they connect, node/edge types
2. **Feature Vectors (State)** — per-node KPIs (CPU, throughput, alarms) and per-edge KPIs (utilization, latency, errors)

Both must be continuously updated as the network changes.

## Topology Sources

| Source | Protocol | What It Provides | Update Frequency |
|---|---|---|---|
| Network Inventory / CMDB | REST, TMF639 | All managed elements, types, relationships | Near real-time |
| IGP/Routing (OSPF-TE, IS-IS) | BGP-LS or controller | L3 topology, link metrics | Seconds |
| SDN Controller | RESTCONF, OpenFlow | Centralized topology view | Real-time |
| NETCONF/YANG | RFC 6241 | Device config, interface relationships | On-demand |
| 3GPP NBI | TS 28.532 | RAN topology (gNBs, cells, neighbor relations) | Real-time |
| O-RAN E2/O1 | E2AP, NETCONF/VES | Near-RT RAN topology | Real-time |
| LLDP/CDP | L2 discovery | Physical adjacency | 30-60s |

## Feature Sources

| Source | Protocol | Features | Granularity |
|---|---|---|---|
| PM Counters (3GPP) | FTP/Kafka/VES | RAN KPIs: RSRP, throughput, PRB utilization | 15-min (configurable) |
| Streaming Telemetry | gNMI, gRPC | Interface stats, errors, latency | Seconds |
| SNMP | SNMPv2c/v3 | CPU, memory, temperature | 5-min polling |
| FM Alarms | VES, SNMP traps | Alarm type, severity, timestamp | Immediate |
| NWDAF (5G) | Nnwdaf APIs | Network analytics: load, QoS, mobility | Real-time |

## Graph Construction Engine

The critical middle layer that translates raw CSP data into GNN-consumable tensors:

1. **Topology Reconciler** — merges sources, resolves conflicts, detects changes
2. **Feature Normalizer** — z-score/min-max normalization, handles missing values, encodes categoricals
3. **Graph Builder** — creates adjacency matrix A, node feature matrix X, edge feature matrix E

**Multi-vendor normalization**: Ericsson `pmRrcConnEstabSucc` and Nokia `VS.RRC.ConnEstab.Succ` both map to the same `rrc_connection_success_rate` (float 0-1). Standard models: TMF SID, 3GPP NRM, OpenConfig YANG.

## Integration Patterns

| Pattern | How It Works |
|---|---|
| **Graph Database Hub** | Neo4j / TigerGraph / Google Spanner Graph stores topology; GNN reads subgraphs. Used by Google Cloud + NetAI. |
| **Streaming Pipeline** | Kafka → Flink → Feature Store (Redis/Feast) → GNN inference (TorchServe/Triton). |
| **Digital Twin** | Mirror of production network; GNN trains/infers on twin data; safe for what-if simulation. |

## Related Concepts

- [Labeled Data Challenge](./labeled-data-challenge.md) — getting ground truth for training
- [RCA Dataset Design](../training-data/rca-dataset-design.md) — practical dataset structure
