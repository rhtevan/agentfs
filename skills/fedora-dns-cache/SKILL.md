---
name: fedora-dns-cache
description: >
  Configure systemd-resolved stale DNS caching on Fedora to prevent terminal
  and shell hangs when internet connectivity drops. Diagnoses DNS timeout
  issues and applies a resolved.conf.d drop-in for instant cached responses.
argument-hint: "No arguments required"
compatibility: "Fedora 40+ with systemd-resolved"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [fedora, dns, network, systemd, terminal, offline]
  signals: ["dns cache", "terminal stuck offline", "terminal hangs no internet", "dns timeout", "fedora dns cache", "shell hangs network drop"]
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

## Prerequisites

- Fedora 40+ (or any systemd 250+ distro with `systemd-resolved`)
- `systemd-resolved` active as the system DNS resolver
- `sudo` access to write to `/etc/systemd/resolved.conf.d/`

## Steps

1. **Diagnose DNS timeout history**

   Check if DNS timeouts have been occurring:

   ```bash
   resolvectl statistics | grep -A1 Timeout
   ```

   Any non-zero "Total Timeouts" confirms the problem.

2. **Check current configuration**

   Verify no existing stale cache config:

   ```bash
   systemd-analyze cat-config systemd/resolved.conf | grep -i stale
   ```

   Default is `#StaleRetentionSec=0` (disabled).

3. **Apply the drop-in configuration**

   Run the setup script (requires `sudo`):

   ```bash
   bash ~/.agents/skills/fedora-dns-cache/scripts/setup.sh
   ```

   Or apply manually:

   ```bash
   sudo mkdir -p /etc/systemd/resolved.conf.d

   sudo tee /etc/systemd/resolved.conf.d/fast-timeout.conf <<'EOF'
   # Reduce DNS pain when ISP connection drops
   [Resolve]
   # Serve stale (expired) cached records when upstream DNS is unreachable
   # rather than waiting for a timeout. Stale records served for up to 1 hour.
   StaleRetentionSec=3600
   EOF
   ```

4. **Restart systemd-resolved**

   ```bash
   sudo systemctl restart systemd-resolved
   ```

5. **Verify**

   Confirm the setting is active:

   ```bash
   systemd-analyze cat-config systemd/resolved.conf | grep -i stale
   ```

   Expected output should show `StaleRetentionSec=3600` (uncommented).

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

| Updated | Change |
|---------|--------|
| 2026-07-29 10:27 | v1.0 — Initial skill based on real DNS timeout diagnosis |
