---
name: crc-status
description: >
  crc status, check crc, crc health
metadata:
  author: agentfs
  version: "2.1.0"
  tags: [openshift, crc, status, console]
user-invocable: true
disable-model-invocation: false
---

# OpenShift Local Status Check

Read-only health check for an OpenShift Local (CRC) cluster.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 2.1.0 |
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

Read the script output. Present the facts to the user in a clear
summary. The script prints a structured status report — see the
[Output Contract](#output-contract) below for the full list of fields.

**When the cluster is stopped:** Tell the user the CRC VM is not
running and report the VM state, disk usage, and cache usage. Do NOT
proceed to any further steps. Do NOT suggest starting the cluster
unless the user asks.

**When the cluster is running:** Report the VM state, OpenShift state,
disk and cache usage, credentials, and whether a console notification
banner is present.

**When a console banner is present:** Ask the user whether to remove
it. Do NOT remove it without confirmation.

## Output Contract

The status script (`check-status.sh`) prints a structured report with
these fields. All fields are plain text, one per line, in `key: value`
format.

| Field | Always present | Description |
|-------|:-:|---|
| `crc_cli_found` | ✅ | Whether the `crc` CLI is installed |
| `crc_exit_code` | ✅ | Exit code from `crc status` |
| `crc_vm_state` | ✅ | VM state (Running, Stopped, etc.) |
| `openshift_state` | ✅ | OpenShift cluster state |
| `disk_usage` | ✅ | CRC disk usage |
| `cache_usage` | ✅ | CRC cache usage |
| `cache_directory` | ✅ | Path to cache directory |
| `cluster_running` | ✅ | `true` or `false` — derived from VM state |
| `oc_cli_found` | running only | Whether `oc` CLI is available |
| `credentials` | running only | Console credentials from `crc console --credentials` |
| `banner_exists` | running only | `yes`, `no`, or `unknown` |
| `banner_name` | running only | Console notification resource name (if banner exists) |

## Scope

| In scope | Out of scope |
|----------|-------------|
| Report CRC VM and OpenShift state | Starting or stopping CRC |
| Report disk and cache usage | Changing CRC configuration |
| Report banner status | Troubleshooting CRC failures |
| Report credentials (if running) | Installing or updating CRC |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
