---
name: crc-ctl
description: >
  start crc, stop crc, crc start, crc stop,
  clean crc, crc cleanup, crc disk cleanup
argument-hint: "'start crc', 'stop crc', 'clean crc'"
compatibility: "Requires crcstart/crcstop wrappers installed via crc-cmd skill"
metadata:
  author: agentfs
  version: "2.0.0"
  tags: [crc, openshift, openshift-local, cluster, operations, cleanup]
user-invocable: true
disable-model-invocation: false
---

# CRC Cluster Control

Operational procedures for starting, stopping, and maintaining the
OpenShift Local (CRC) cluster. This skill defines the correct workflow
for using the custom `crcstart` and `crcstop` wrapper scripts, and
provides a disk cleanup procedure to reclaim space inside the CRC VM
when container image layers, journal logs, and completed pods
accumulate over time.

> **Important:** Never use the built-in `crc start` or `crc stop`
> commands directly. Always use the `crcstart` and `crcstop` wrapper
> scripts. See the `crc-cmd` skill for installation details.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| ~/app/playground/goofing-around | default-agent/MEMORY | "Do NOT use `crc start` or `crc stop` — use `crcstart` and `crcstop` instead" |
| ~/app/playground/goofing-around | default-agent/MEMORY | "Before running `crcstart`, first run `crc version` and show the result" |
| ~/app/playground/goofing-around | default-agent/MEMORY | "After running `crcstop`, wait for exit, check for lingering CRC processes, clean up" |
| ~/app/playground/rhsi | session 2026-08-27 | CRC disk cleanup: crictl prune, journal vacuum, API log cleanup, completed pod deletion |

## Prerequisites

- `crcstart` and `crcstop` wrapper scripts installed in `~/.local/bin/`
  (use the `crc-cmd` skill to install them)
- CRC installed and configured with libvirt driver
- `virsh` available (from `libvirt-client` package)
- SSH accessible into CRC VM on `127.0.0.1:2222` (for cleanup operations)

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

## Cleaning Up Disk Space

CRC VM disk usage grows over time from unused container image layers,
journal logs, old API server logs, and completed pods (especially
from `openshift-marketplace` catalog jobs). The cleanup script
reclaims this space without affecting running workloads.

### What gets cleaned

| Target | Location (inside VM) | Method |
|--------|---------------------|--------|
| Unused container images | `/var/lib/containers/storage/overlay/` | `crictl rmi --prune` |
| Journal logs | `/var/log/journal/` | `journalctl --vacuum-size=256M` |
| Old API server logs | `/var/log/kube-apiserver/`, `/var/log/openshift-apiserver/`, `/var/log/oauth-apiserver/` | Delete `.log` files older than 3 days |
| Completed pods | All namespaces | `oc delete pods --field-selector=status.phase=Succeeded` and `Failed` |

### Run cleanup

```bash
bash ~/.agents/skills/crc-ctl/scripts/crc-cleanup.sh
```

For a preview without making changes:

```bash
bash ~/.agents/skills/crc-ctl/scripts/crc-cleanup.sh --dry-run
```

The script:
1. Checks CRC VM is running and SSH is accessible
2. Reports disk usage before cleanup
3. Prunes unused container images (`crictl rmi --prune`)
4. Vacuums journal logs down to 256 MB
5. Deletes API server logs older than 3 days
6. Deletes completed and failed pods
7. Reports disk usage after cleanup with total reclaimed

### When to run cleanup

- When `crc status` shows disk usage above 50%
- Before deploying large workloads that need space
- Periodically (e.g., weekly) as maintenance

## Quick Reference

| Action | Command | Never Use |
|--------|---------|----------|
| Start cluster | `crcstart` | ~~`crc start`~~ |
| Stop cluster | `crcstop` | ~~`crc stop`~~ |
| Clean up disk | `bash ~/.agents/skills/crc-ctl/scripts/crc-cleanup.sh` | — |
| Clean up (preview) | `bash ~/.agents/skills/crc-ctl/scripts/crc-cleanup.sh --dry-run` | — |
| Check version | `crc version` | — |
| Check status | `crc status` | — |
| Start with debug | `crcstart -- --log-level debug` | — |
| Stop with timeout | `crcstop --timeout 600` | — |

## Gotchas

- **Unused image pruning can reclaim 50+ GB.** CRI-O does not
  aggressively garbage-collect pulled images. After operator updates
  or catalog refreshes, old image layers linger in
  `/var/lib/containers/storage/overlay/`. This is the single largest
  source of disk waste — the 2026-08-27 cleanup freed ~74 GB mostly
  from this.
- **`/var/home/ezhang/` inside the VM** is a passthrough mount of the
  host home directory. It shows as ~275 GB in `du` inside the VM but
  is NOT consuming VM disk — ignore it when diagnosing VM disk usage.
- **The CRC VM root filesystem uses composefs.** `df /` shows the
  composefs overlay at 100% — this is normal and not the filesystem
  you're monitoring. The relevant mount is the one reported by
  `crc status` (the `/sysroot` or backing disk).
- **`openshift-marketplace` pods accumulate fastest.** Catalog source
  pods complete and pile up (36+ in a typical week). These are safe
  to delete.
- **Journal vacuum frees archived journals only.** Active journal
  files are not vacuumed — the reclaim depends on how many archived
  segments exist. Typical savings: 0.5–1.5 GB.
- **SSH port 2222** is the CRC VM's SSH port forwarded to localhost.
  If it's not listening, the VM may not be fully booted or the port
  forward may have failed — check `ss -tlnp | grep 2222`.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Start CRC cluster using `crcstart` wrapper | `crc status` shows Running after `crcstart` |
| S2 | Stop CRC cluster using `crcstop` wrapper | `crc status` shows Stopped after `crcstop` |
| S3 | Clean up VM disk space (images, logs, pods) | `scripts/crc-cleanup.sh` runs, reports before/after |
| S4 | Dry-run cleanup without changes | `scripts/crc-cleanup.sh --dry-run` exits 0 with preview |
| S5 | Detect CRC VM not running before cleanup | `scripts/crc-cleanup.sh` exits 1 when VM stopped |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `crcstart && crc status` | CRC VM: Running |
| T2 | S2 | `crcstop && crc status` | CRC VM: Stopped |
| T3 | S3 | `bash scripts/crc-cleanup.sh` | Before/after disk usage printed, "Cleanup complete" |
| T4 | S4 | `bash scripts/crc-cleanup.sh --dry-run` | Exit 0, "DRY RUN" in output, no changes made |
| T5 | S5 | Stop CRC, then `bash scripts/crc-cleanup.sh` | Exit 1, "not running" error message |

## Verification

- [ ] `crc version` runs and shows output before starting
- [ ] `crcstart` is used instead of `crc start`
- [ ] `crcstop` is used instead of `crc stop`
- [ ] No lingering CRC processes after `crcstop` completes
- [ ] `crc status` reports correct state after start/stop
- [ ] `crc-cleanup.sh` runs and reports disk space reclaimed
- [ ] `crc-cleanup.sh --dry-run` previews without making changes

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
