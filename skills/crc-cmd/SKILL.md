---
name: crc-cmd
description: Install the crcstart and crcstop wrapper commands for OpenShift Local (CRC) that replace 'crc start' and 'crc stop' with more reliable alternatives
---

# CRC Wrapper Commands

Install two wrapper commands (`crcstart` and `crcstop`) into `~/.local/bin/` for managing OpenShift Local (CRC). These replace the built-in `crc start` and `crc stop` commands with more reliable alternatives.

## Background

### Why `crcstop` exists

The built-in `crc stop` has a **hard-coded 120-second timeout** in the libvirt machine driver (`crc-org/machine-driver-libvirt`, `pkg/libvirt/libvirt.go`). It sends an ACPI shutdown signal via `libvirt.Shutdown()`, then polls the VM state in a loop of 120 iterations × 1-second sleep. If the VM hasn't stopped by then, CRC force-kills it with `virsh destroy`.

The problem is the CRC guest OS (RHCOS) routinely takes **2.5–6 minutes** to shut down because:
- **~160–186 libcrun containers** must stop individually (~2.5 min)
- **CRI-O** cleanup can take up to its `DefaultTimeoutStopSec` of 200 seconds
- The `qemu-guest-agent` in the VM has `ConditionVirtualization=apple`, so it's **disabled on KVM/libvirt** — no guest-agent shutdown path is available

This means `crc stop` **always force-kills the VM** on Linux with libvirt.

### Why `crcstart` exists

Created for consistency alongside `crcstop`. It wraps `crc start` with pre-flight checks (is the VM already running?) and post-start status display.

## Prerequisites

- `~/.local/bin` must be on `PATH` (Fedora default via `~/.bashrc`)
- CRC installed and configured with libvirt driver
- SSH key exists at `~/.crc/machines/crc/id_ed25519` (created by CRC automatically)
- `virsh` available (from `libvirt-client` package)
- `crc-daemon.service` running as a systemd user unit

## Steps

1. **Create `~/.local/bin` if it doesn't exist**
   ```bash
   mkdir -p ~/.local/bin
   ```

2. **Create `~/.local/bin/crcstop`** with the script content from the [`crcstop` script](#crcstop-script) section below.

3. **Create `~/.local/bin/crcstart`** with the script content from the [`crcstart` script](#crcstart-script) section below.

4. **Make both executable**
   ```bash
   chmod +x ~/.local/bin/crcstop ~/.local/bin/crcstart
   ```

## Usage

### crcstop
```bash
crcstop                  # Graceful shutdown with 420s (7 min) default timeout
crcstop --timeout 600    # Custom timeout in seconds
```

How it works:
1. Checks if the CRC VM is running via `virsh domstate`
2. SSHs into the VM and runs `sudo systemctl poweroff` (faster than ACPI)
3. Falls back to ACPI shutdown (`virsh shutdown`) if SSH is unavailable
4. Polls VM state every 5 seconds with a spinner, up to the timeout
5. After shutdown completes, restarts `crc-daemon.service` so `crc status` reports correctly
6. Only force-kills (`virsh destroy`) as a last resort after timeout expires

### crcstart
```bash
crcstart                        # Normal start
crcstart -- --log-level debug   # Pass extra args to 'crc start'
crcstart --help                 # Show help
```

How it works:
1. Checks if the VM is already running — if so, shows status and exits
2. Runs `crc start` with any extra arguments passed through
3. Shows `crc status` after successful start

## Verification

- [ ] `which crcstop` returns `~/.local/bin/crcstop`
- [ ] `which crcstart` returns `~/.local/bin/crcstart`
- [ ] `crcstop` shuts down the VM gracefully (typically ~2.5 minutes) without force-killing
- [ ] `crc status` works correctly after `crcstop` completes
- [ ] `crcstart` starts CRC and shows status afterward

---

## crcstop script

```bash
#!/bin/bash
#
# crcstop: Gracefully stop CRC (OpenShift Local) without force-killing the VM.
#
# Problem: 'crc stop' has a hard-coded 120-second timeout, but the guest OS
# takes ~6 minutes to shut down (160+ containers + CRI-O cleanup). This causes
# 'crc stop' to always force-kill the VM via 'virsh destroy'.
#
# Solution: Issue 'poweroff' inside the VM via SSH, then wait with a generous
# timeout for the VM to reach 'shut off' state. Finally, restart the CRC daemon
# so 'crc status' reports the correct state.
#
# Usage: crcstop [--timeout SECONDS]
#

set -euo pipefail

TIMEOUT=420  # Default 7 minutes
if [[ "${1:-}" == "--timeout" ]]; then
    TIMEOUT="${2:-420}"
fi

SSH_KEY="$HOME/.crc/machines/crc/id_ed25519"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o LogLevel=ERROR"
LIBVIRT_URI="qemu:///system"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}●${NC} $*"; }
warn() { echo -e "${YELLOW}●${NC} $*"; }
err()  { echo -e "${RED}●${NC} $*"; }

# Check if CRC VM is running
vm_state=$(virsh --connect "$LIBVIRT_URI" domstate crc 2>/dev/null || echo "not found")
if [[ "$vm_state" != "running" ]]; then
    if [[ "$vm_state" == "shut off" ]]; then
        log "CRC VM is already stopped."
        exit 0
    else
        err "CRC VM is in unexpected state: $vm_state"
        exit 1
    fi
fi

log "CRC VM is running. Initiating graceful shutdown..."

# Try to SSH in and trigger poweroff from inside the guest
if ssh $SSH_OPTS -i "$SSH_KEY" -p 2222 core@127.0.0.1 "sudo systemctl poweroff" 2>/dev/null; then
    log "Shutdown command sent via SSH."
else
    warn "SSH failed (VM may not be fully booted). Falling back to ACPI power button..."
    virsh --connect "$LIBVIRT_URI" shutdown crc >/dev/null 2>&1
    log "ACPI shutdown signal sent."
fi

# Wait for VM to reach 'shut off' state
log "Waiting for VM to shut down (timeout: ${TIMEOUT}s)..."
elapsed=0
interval=5
spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spin_idx=0

while [[ $elapsed -lt $TIMEOUT ]]; do
    state=$(virsh --connect "$LIBVIRT_URI" domstate crc 2>/dev/null || echo "error")
    if [[ "$state" == "shut off" ]]; then
        echo ""
        log "CRC VM shut down gracefully in ${elapsed} seconds."

        # Restart the CRC daemon so 'crc status' picks up the new state
        if systemctl --user restart crc-daemon.service 2>/dev/null; then
            log "CRC daemon restarted. 'crc status' is ready."
        fi
        exit 0
    fi
    printf "\r  ${spinner[$spin_idx]} Shutting down... [%3ds / %ds]  " "$elapsed" "$TIMEOUT"
    spin_idx=$(( (spin_idx + 1) % ${#spinner[@]} ))
    sleep "$interval"
    elapsed=$((elapsed + interval))
done

echo ""
err "VM did not shut down within ${TIMEOUT} seconds."
err "Force-stopping with 'virsh destroy'..."
virsh --connect "$LIBVIRT_URI" destroy crc >/dev/null 2>&1

# Restart daemon even after force-stop
systemctl --user restart crc-daemon.service 2>/dev/null

err "VM was force-stopped. Data may not have been flushed cleanly."
exit 1
```

## crcstart script

```bash
#!/bin/bash
#
# crcstart: Start CRC (OpenShift Local) and wait for the cluster to be ready.
#
# Wrapper around 'crc start' that provides a cleaner experience:
# - Checks if the VM is already running (and cluster already ready)
# - Runs 'crc start' with output streaming
# - Verifies cluster is accessible afterward
#
# Usage: crcstart [-- <extra crc start args>...]
#

set -euo pipefail

LIBVIRT_URI="qemu:///system"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}●${NC} $*"; }
warn() { echo -e "${YELLOW}●${NC} $*"; }
err()  { echo -e "${RED}●${NC} $*"; }
info() { echo -e "${CYAN}●${NC} $*"; }

# Parse arguments: anything after '--' is passed to 'crc start'
CRC_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --)
            shift
            CRC_ARGS=("$@")
            break
            ;;
        -h|--help)
            echo "Usage: crcstart [-- <extra crc start args>...]"
            echo ""
            echo "Start CRC and wait for the cluster to be ready."
            echo "Any arguments after '--' are passed directly to 'crc start'."
            echo ""
            echo "Examples:"
            echo "  crcstart"
            echo "  crcstart -- --log-level debug"
            exit 0
            ;;
        *)
            CRC_ARGS+=("$1")
            shift
            ;;
    esac
done

# Check current VM state
vm_state=$(virsh --connect "$LIBVIRT_URI" domstate crc 2>/dev/null || echo "not found")

if [[ "$vm_state" == "running" ]]; then
    warn "CRC VM is already running."
    info "Checking cluster status..."
    crc status 2>/dev/null && exit 0
    warn "VM is running but cluster may not be ready. Running 'crc start' to reconcile..."
fi

log "Starting CRC..."
echo ""

# Run crc start, passing through any extra args
if crc start "${CRC_ARGS[@]+"${CRC_ARGS[@]}"}"; then
    echo ""
    log "CRC started successfully!"
    echo ""
    crc status 2>/dev/null || true
else
    exit_code=$?
    echo ""
    err "crc start failed (exit code: $exit_code)."
    err "Check 'crc status' or logs at ~/.crc/crc.log for details."
    exit $exit_code
fi
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-19 22:04 | v1.0 — Initial skill |
