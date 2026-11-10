---
name: fedora-dns-cache
description: >
  configure dns cache, fedora dns cache, dns timeout, terminal hangs offline
argument-hint: "No arguments required"
compatibility: "Fedora 40+ with systemd-resolved"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T2
  tags: [fedora, dns, network, systemd, terminal, offline]
user-invocable: true
disable-model-invocation: false
---

# Fedora DNS Cache for Offline Resilience

Configure `systemd-resolved` to serve stale (expired) DNS cache entries
when upstream DNS servers are unreachable, preventing 30+ second hangs
in terminals and shells caused by DNS resolution timeouts.

## Problem

When an ISP connection drops or DNS servers become unreachable, every
DNS lookup (hostname resolution, SSSD/IPA checks, etc.) blocks for
30+ seconds waiting for a timeout. This makes GNOME Terminal appear
stuck — the window opens but no prompt appears until all pending DNS
queries time out.

## Solution

Enable `StaleRetentionSec` in `systemd-resolved`. When upstream DNS
is unreachable, previously cached answers are served immediately
(for up to 1 hour after expiry) instead of waiting for a timeout.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Prerequisites

- Fedora 40+ (or any systemd 250+ distro with `systemd-resolved`)
- `systemd-resolved` active as the system DNS resolver
- `sudo` access to write to `/etc/systemd/resolved.conf.d/`

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Workflow

### Step 1 — Run the setup script

The agent MUST run the setup script:

```bash
bash ~/.agents/skills/fedora-dns-cache/scripts/setup.sh
```

The script handles diagnosis, configuration, and service restart
automatically. It requires `sudo` for systemd config changes.
The agent MUST report the script output verbatim.

### Step 2 — Verify

The agent MUST confirm the configuration is active:

```bash
systemd-analyze cat-config systemd/resolved.conf | grep -i stale
```

Expected: `StaleRetentionSec=3600` (uncommented).

## Output Contract

- Exit 0 from the setup script → configuration applied successfully
- Exit 1 → error (script output explains the cause)

## How It Works

- `systemd-resolved` maintains an in-memory DNS cache of recent lookups.
- Normally, when a cached entry expires (TTL), resolved discards it and
  queries upstream — which hangs if upstream is unreachable.
- With `StaleRetentionSec=3600`, expired entries are kept for up to
  1 hour and served immediately when upstream is unreachable.
- When connectivity returns, fresh lookups resume automatically.
- No downside for workstations/laptops — stale entries are only served
  when upstream is genuinely unreachable.

## Verification

- [ ] `/etc/systemd/resolved.conf.d/fast-timeout.conf` exists
- [ ] `systemd-analyze cat-config systemd/resolved.conf` shows `StaleRetentionSec=3600`
- [ ] `systemctl is-active systemd-resolved` returns `active`
- [ ] `resolvectl statistics` shows "Total Timeouts (Stale Data Served)" counter


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
