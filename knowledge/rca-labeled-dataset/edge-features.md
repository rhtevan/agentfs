---
type: Dataset
title: "Edge Feature Time Series"
description: "Per-edge KPI measurements (utilization, latency, packet loss, CRC errors, link flaps, oper_status) at 4 timestamps matching the node feature snapshots."
tags: [kpi, telemetry, edge-features, link-state, time-series]
timestamp: 2026-06-25T16:35:47
---

# Edge Feature Time Series

Link-level KPI data that populates the GNN's edge attribute matrix **E**.

## Source File

- [03_edge_features_timeseries.csv](./samples/03_edge_features_timeseries.csv)

## Schema (9 features per edge)

| Feature | Unit | Source |
|---------|------|--------|
| utilization | 0–1 | SNMP interface counters |
| latency_ms | ms | TWAMP / active probes |
| packet_loss_rate | 0–1 | interface counters |
| bandwidth_gbps | Gbps | inventory / config |
| crc_errors | count/interval | SNMP |
| input_errors | count/interval | SNMP |
| output_drops | count/interval | SNMP |
| link_flaps | count/interval | syslog |
| oper_status | up=1, down=0 | SNMP |

## Key Observation

Edge **E005** (CSG-NYC-E-01 → AGG-NYC-E-01) is the **fault link** — its CRC errors escalate from 0 → 847 → 52,480 → 125,000 across the 4 snapshots, and `oper_status` transitions from `up` to `down`.
