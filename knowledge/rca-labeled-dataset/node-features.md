---
type: Dataset
title: "Node Feature Time Series"
description: "Per-node KPI measurements (CPU, memory, throughput, alarm count, etc.) at 4 timestamps: baseline, early degradation, fault onset, and post-remediation."
tags: [kpi, telemetry, pm-counters, time-series, node-features]
timestamp: 2026-06-25T16:35:47
---

# Node Feature Time Series

Real-time KPI data that populates the GNN's node feature matrix **X**.

## Source File

- [02_node_features_timeseries.csv](./samples/02_node_features_timeseries.csv)

## Schema (19 features per node)

| Feature | Unit | Source |
|---------|------|--------|
| cpu_util | 0–1 | SNMP / gNMI |
| memory_util | 0–1 | SNMP / gNMI |
| connected_ues | count | 3GPP PM |
| dl_throughput_mbps | Mbps | 3GPP PM |
| ul_throughput_mbps | Mbps | 3GPP PM |
| prb_util_dl / prb_util_ul | 0–1 | 3GPP PM |
| rrc_conn_success_rate | 0–1 | 3GPP PM |
| erab_setup_success_rate | 0–1 | 3GPP PM |
| handover_success_rate | 0–1 | 3GPP PM |
| cqi_avg | 0–15 | 3GPP PM |
| rsrp_avg_dbm | dBm | 3GPP PM |
| packet_loss_rate | 0–1 | telemetry |
| latency_ms | ms | active probes |
| active_alarms | count | FM |
| interface_errors / interface_discards | count | SNMP |
| temperature_c | °C | SNMP |
| power_draw_w | watts | SNMP |

## Temporal Snapshots

| Timestamp | Phase | Key Signal |
|-----------|-------|------------|
| 01:15 UTC | Normal baseline | All KPIs nominal |
| 01:45 UTC | Early degradation | CRC errors visible on AGG-NYC-E-01 |
| 02:17 UTC | Fault onset | Cascading failures across domains |
| 04:55 UTC | Post-remediation | KPIs recovering to baseline |
