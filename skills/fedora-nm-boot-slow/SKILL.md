---
name: fedora-nm-boot-slow
description: >
  slow boot network, nm-wait-online slow, network boot delay,
  diagnose boot network, fix nm-wait-online
argument-hint: "diagnose | fix-wifi | fix-nm-wait-online"
compatibility: "Fedora 40+ with NetworkManager and systemd"
metadata:
  author: agentfs
  version: "1.1.0"
  tags: [fedora, network, boot, networkmanager, performance]
user-invocable: true
disable-model-invocation: false
---

# Fedora NM Boot Slow

Diagnoses and guides remediation of slow boot caused by
`NetworkManager-wait-online.service` blocking the systemd boot sequence.
This service waits for ALL auto-connected network interfaces to finish
activating before releasing `network-online.target` — which delays
everything downstream (VPN clients, log forwarders, and desktop apps
that start after network is ready). The most common root cause on
laptops/workstations is having both wired and Wi-Fi auto-connecting
simultaneously, where the slower Wi-Fi path (scan → WPA handshake →
DHCP) holds up the entire boot.

## Prerequisites

- Fedora 40+ with NetworkManager as the network manager
- `systemd-analyze` available (standard on Fedora)
- `nmcli` available (standard with NetworkManager)
- `sudo` access for remediation steps (diagnosis is sudo-free)

## Steps

### 1. Diagnose Boot Time

First, check whether `NM-wait-online` is actually a significant
bottleneck in the current boot:

```bash
systemd-analyze blame | head -20
```

Look for `NetworkManager-wait-online.service` near the top of the list.
Also check the critical chain:

```bash
systemd-analyze critical-chain
```

If `NetworkManager-wait-online.service` appears in the chain with a
`+` time of 3 seconds or more, it is a meaningful bottleneck.

### 2. Identify Auto-Connected Interfaces

Find which network interfaces auto-connect at boot:

```bash
nmcli -f NAME,TYPE,DEVICE,CONNECTION-FLAGS con show
```

Look for connections with `autoconnect` in the flags or check
explicitly:

```bash
nmcli -f NAME,TYPE,connection.autoconnect con show | grep yes
```

Note the names of any Wi-Fi connections with `autoconnect: yes`.
These are candidates for the slowdown if wired is also auto-connecting.

### 3. Check What Depends on network-online.target

Understand the blast radius — what services are blocked at boot:

```bash
systemctl list-dependencies network-online.target --reverse
```

Only active (● green) services matter. Inactive (○ grey) services are
not running and have no impact.

### 4. Identify Root Cause

If both wired (`ethernet` type) and Wi-Fi (`wifi` type) connections
are set to `autoconnect: yes`, `NM-wait-online` blocks until **both**
finish. Wi-Fi is always slower because it requires:
- Scanning for the SSID
- WPA/WPA2 authentication handshake
- DHCP lease acquisition

This typically adds 4–7 seconds on top of the wired connection time.

### 5. Remediation — Choose One Option

Two options are available depending on your usage pattern.

#### Option A — Disable Wi-Fi Auto-Connect (Simple, Docked-Only)

**Use when:** You are primarily docked/wired and only need Wi-Fi
manually when away from your desk.

Find your Wi-Fi connection name:
```bash
nmcli -f NAME,TYPE con show | grep wifi
```

Then disable auto-connect (replace `<wifi-name>` with the name found
above, e.g. `starnet`):
```bash
nmcli con modify <wifi-name> connection.autoconnect no
```

> ⚠️ **Undocked caveat:** With this option, if you reboot without a
> wired connection, you will have **no network at boot** — not even
> Wi-Fi. You must manually connect Wi-Fi after login via the GNOME
> network menu or `nmcli con up <wifi-name>`.
> Additionally, `NM-wait-online` will hit its 30-second timeout
> waiting for wired, further slowing undocked boots. See Option B
> to address both issues together.

**Verify:**
```bash
nmcli -f connection.autoconnect con show <wifi-name>
```
Expected: `connection.autoconnect: no`

#### Option B — Disable NM-wait-online (Recommended for Most Users)

**Use when:** You want the fix to work whether docked or undocked,
and your services that depend on network connectivity handle
late/missing network gracefully (which most do — including Splunk).

Check services that depend on `network-online.target` first (Step 3).
If none of the active services require network to be present at the
exact moment of boot (e.g., no NFS mounts, no iSCSI), this is safe.

Disable the service (**requires sudo**):
```bash
sudo systemctl disable NetworkManager-wait-online.service
```

Verify it is disabled:
```bash
systemctl is-enabled NetworkManager-wait-online.service
```
Expected: `disabled`

**Effect:** Boot proceeds immediately to `network-online.target`
without waiting. NM still connects in the background — services just
don't block on it at startup.

**To re-enable if needed:**
```bash
sudo systemctl enable NetworkManager-wait-online.service
```

## Gotchas

- **Wi-Fi auto-connect disabled + undocked reboot = no network at
  boot.** Option A trades boot speed when docked for a poor undocked
  experience. Option B avoids this tradeoff entirely.

- **`NM-wait-online` timeout is 30 seconds by default.** If a
  connection it expects never comes up (e.g., wired unplugged, Wi-Fi
  disabled), it blocks for the full 30 seconds before failing. This
  makes undocked reboots with Option A significantly worse than
  normal.

- **SplunkForwarder depends on `network-online.target`** on Fedora
  systems with Splunk installed, but handles late connectivity
  gracefully — it buffers log events and forwards once connected.
  Disabling `NM-wait-online` (Option B) does not cause log loss.

- **NetBird/WireGuard VPN devices** (`wt0` etc.) are registered by
  NM during startup and add a small amount of device enumeration
  overhead (~1–2s). This is normal and not a bottleneck worth
  addressing separately.

- **NM-wait-online waits for ALL auto-activating connections**, not
  just the first one to come up. Even if wired connects in 3s, it
  continues waiting if Wi-Fi is still authenticating.

- **`connection.autoconnect-priority`** does NOT prevent a connection
  from auto-connecting — it only controls which connection wins when
  two profiles match the same device. Setting priority to `-1` or `0`
  still auto-connects; only `autoconnect: no` prevents it.

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Identify whether `NM-wait-online` is a significant boot bottleneck | `systemd-analyze blame` output shows service with 3s+ delay |
| S2 | Discover which network connections have `autoconnect: yes` | `nmcli` output lists all auto-connecting connections by name and type |
| S3 | Identify what services depend on `network-online.target` | `systemctl list-dependencies` output, distinguishing active vs inactive |
| S4 | Present both remediation options with their tradeoffs | Agent explains Option A (Wi-Fi autoconnect off) and Option B (disable NM-wait-online) before acting |
| S5 | Agent does NOT execute `sudo` commands directly | Agent provides commands for user to run; never runs them itself |
| S6 | Verify fix was applied after user runs the command | Agent re-runs the appropriate check command and confirms expected output |

## Tests

| Test | Spec | How to Verify | Expected Result |
|:----:|:----:|--------------|----------------|
| T1 | S1 | Run `systemd-analyze blame \| head -20` and check output | `NM-wait-online` appears with `+Xs` time if it is a bottleneck |
| T2 | S2 | Run `nmcli -f NAME,TYPE,connection.autoconnect con show \| grep yes` | Lists all auto-connecting connections by name |
| T3 | S3 | Run `systemctl list-dependencies network-online.target --reverse` | Active services (●) are identified; inactive (○) noted as not impacted |
| T4 | S4 | Ask agent: *"my boot is slow due to network"* | Agent presents both options with tradeoffs before asking which to apply |
| T5 | S5 | Observe agent behavior during fix | Agent outputs the `sudo` command as a code block for the user to copy — does not call `shell` with `sudo` |
| T6 | S6 | After user runs fix, agent re-checks | For Option A: `nmcli` shows `autoconnect: no`; for Option B: `systemctl is-enabled` shows `disabled` |

## Verification


- [ ] `systemd-analyze blame | head -5` — `NM-wait-online` no longer
      appears near top, or shows significantly reduced time
- [ ] `systemctl is-enabled NetworkManager-wait-online.service` —
      returns `disabled` (Option B)
- [ ] `nmcli -f connection.autoconnect con show <wifi-name>` —
      returns `no` (Option A)
- [ ] Next reboot: `systemd-analyze` shows reduced total boot time

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
