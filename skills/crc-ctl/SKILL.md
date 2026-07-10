---
name: crc-ctl
description: >
  Operational skill for starting and stopping the OpenShift Local (CRC)
  cluster using the custom crcstart/crcstop wrapper scripts. Includes
  pre-start version check, post-stop process cleanup, and correct
  command usage. Complements crc-cmd which installs the wrappers.
argument-hint: "'start crc', 'stop crc', 'crc start', 'crc stop'"
compatibility: "Requires crcstart/crcstop wrappers installed via crc-cmd skill"
metadata:
  author: agentfs
  version: "1.0"
  tags: [crc, openshift, openshift-local, cluster, operations]
user-invocable: true
disable-model-invocation: false
---

# CRC Cluster Control

Operational procedures for starting and stopping the OpenShift Local
(CRC) cluster. This skill defines the correct workflow for using the
custom `crcstart` and `crcstop` wrapper scripts, including pre-flight
checks and post-operation verification.

> **Important:** Never use the built-in `crc start` or `crc stop`
> commands directly. Always use the `crcstart` and `crcstop` wrapper
> scripts. See the `crc-cmd` skill for installation details.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| ~/app/playground/goofing-around | default-agent/MEMORY | "Do NOT use `crc start` or `crc stop` — use `crcstart` and `crcstop` instead" |
| ~/app/playground/goofing-around | default-agent/MEMORY | "Before running `crcstart`, first run `crc version` and show the result" |
| ~/app/playground/goofing-around | default-agent/MEMORY | "After running `crcstop`, wait for exit, check for lingering CRC processes, clean up" |

## Prerequisites

- `crcstart` and `crcstop` wrapper scripts installed in `~/.local/bin/`
  (use the `crc-cmd` skill to install them)
- CRC installed and configured with libvirt driver
- `virsh` available (from `libvirt-client` package)

## Starting the Cluster

Follow these steps **in order** when starting CRC:

### 1. Show CRC version

Always run `crc version` first and show the output to the user:

```bash
crc version
```

This confirms which CRC and OpenShift versions are installed before
attempting to start the cluster.

### 2. Start with `crcstart`

Use the wrapper script, **never** `crc start`:

```bash
crcstart
```

To pass additional arguments to the underlying `crc start`:

```bash
crcstart -- --log-level debug
```

The wrapper will:
- Check if the VM is already running (skip if so)
- Run `crc start` with any extra arguments
- Show `crc status` after successful start

### 3. Verify cluster is ready

After `crcstart` completes, verify:

```bash
crc status
oc whoami 2>/dev/null && echo "Cluster accessible" || echo "Not logged in"
```

## Stopping the Cluster

Follow these steps **in order** when stopping CRC:

### 1. Stop with `crcstop`

Use the wrapper script, **never** `crc stop`:

```bash
crcstop
```

For a custom timeout (default is 420s / 7 minutes):

```bash
crcstop --timeout 600
```

The wrapper will:
- SSH into the VM and issue `systemctl poweroff`
- Poll VM state with a spinner until shutdown completes
- Restart `crc-daemon.service` so `crc status` reports correctly
- Only force-kill as a last resort after timeout

### 2. Wait for script to exit

Do NOT interrupt `crcstop`. Wait for the script to exit completely.
A graceful shutdown typically takes **2.5–6 minutes** due to 160+
containers and CRI-O cleanup.

### 3. Check for lingering processes

After `crcstop` exits, check for any remaining CRC-related processes:

```bash
# Check for lingering CRC processes
ps aux | grep -E '[c]rc|[q]emu.*crc' | grep -v grep
```

If any processes remain:

```bash
# Check VM state
virsh --connect qemu:///system domstate crc 2>/dev/null

# If VM is still running or in a stuck state, force destroy
virsh --connect qemu:///system destroy crc 2>/dev/null

# Kill any orphaned CRC daemon processes
pkill -f 'crc daemon' 2>/dev/null || true

# Restart the daemon cleanly
systemctl --user restart crc-daemon.service 2>/dev/null || true
```

### 4. Verify clean shutdown

```bash
crc status
```

Expected output should show the CRC VM as `Stopped`.

## Quick Reference

| Action | Command | Never Use |
|--------|---------|----------|
| Start cluster | `crcstart` | ~~`crc start`~~ |
| Stop cluster | `crcstop` | ~~`crc stop`~~ |
| Check version | `crc version` | — |
| Check status | `crc status` | — |
| Start with debug | `crcstart -- --log-level debug` | — |
| Stop with timeout | `crcstop --timeout 600` | — |

## Verification

- [ ] `crc version` runs and shows output before starting
- [ ] `crcstart` is used instead of `crc start`
- [ ] `crcstop` is used instead of `crc stop`
- [ ] No lingering CRC processes after `crcstop` completes
- [ ] `crc status` reports correct state after start/stop

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 20:06 | v1.0 — Initial skill harvested from project memories (3 entries from goofing-around) |
