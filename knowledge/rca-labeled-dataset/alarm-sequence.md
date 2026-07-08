---
type: Dataset
title: "Alarm Sequence — 47-Alarm Storm"
description: "Chronological sequence of 47 alarms generated during the SFP failure incident, spanning transport, RAN, and core domains over ~47 minutes."
tags: [alarms, fault-management, alarm-storm, correlation, chronological]
timestamp: 2026-06-25T16:35:47
---

# Alarm Sequence

The raw **alarm storm** that a GNN-based RCA system must process.

## Source File

- [04_alarm_sequence.csv](./samples/04_alarm_sequence.csv)

## Statistics

- **Total alarms**: 47
- **Duration**: 01:48:12 → 02:35:00 UTC (~47 minutes)
- **Affected nodes**: 10 of 12
- **Domains**: transport (12 alarms), RAN (28 alarms), core (7 alarms)
- **Root cause indicators**: 4 alarms (ALM-001 to ALM-004) on AGG-NYC-E-01

## Alarm Classification (from labels)

| Category | Count | Examples |
|----------|-------|---------|
| Root cause indicators | 4 | opticalRxPowerDegraded, CRC errors, linkFlapping |
| Direct symptoms | 6 | linkDown, ospfNeighborLoss, mplsLspDown |
| Cascading symptoms | 17 | cellUnavailable, sessionDrops, ngapConnectionLoss |
| Collateral noise | 20 | highUtilization, throughputDegraded, rsrpDegraded |

## Key Insight

The **first alarm** (ALM-001, opticalRxPowerDegraded at 01:48:12) is the earliest root cause signal — but it's a WARNING-severity alarm that is easily overlooked in the subsequent CRITICAL alarm storm.
