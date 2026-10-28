---
name: crc-status
description: >
  crc status, check crc, crc health
metadata:
  author: agentfs
  version: "2.0.0"
  tags: [openshift, crc, status, console]
user-invocable: true
disable-model-invocation: false
---

# OpenShift Local Status Check

Read-only health check for an OpenShift Local (CRC) cluster.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 2.0.0 |
| **Pattern** | A — single script |
| **Dependencies** | `scripts/check-status.sh` |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Gather CRC state deterministically | `check-status.sh` exits 0 with structured output |
| S2 | Report status facts to user | Response contains crc_vm_state and cluster_running |
| S3 | Stop when cluster is stopped | No steps attempted beyond status report |

## Rules

Do NOT run `crc status` directly. Do NOT run `crc console` directly.
Do NOT run any `oc` command directly. The script runs all commands.

Do NOT generate, fabricate, or invent CRC output. All facts come from
the script output. Report exactly what the script says.

This skill never starts, stops, or modifies the CRC cluster.

## Workflow

### Step 1 — Run the status script

Execute the check-status script. Read its output.

```bash
bash ~/.agents/skills/crc-status/scripts/check-status.sh
```

### Step 2 — Report the results

Read the script output. Present the facts to the user in a clear format.

If `cluster_running: false` appears in the output, report that the
cluster is stopped. Do NOT proceed to any further steps. Do NOT
suggest starting the cluster unless the user asks.

If `cluster_running: true` appears in the output, also report the
credentials and banner status from the script output.

If `banner_exists: yes` appears, ask the user whether to remove it.
Do NOT remove it without confirmation.

## Scope

| In scope | Out of scope |
|----------|-------------|
| Report CRC VM and OpenShift state | Starting or stopping CRC |
| Report disk and cache usage | Changing CRC configuration |
| Report banner status | Troubleshooting CRC failures |
| Report credentials (if running) | Installing or updating CRC |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
