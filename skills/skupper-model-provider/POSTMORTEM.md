# Skupper Model Provider — Postmortem

**Date:** 2026-08-11  
**Version:** v6.0.0  
**Scope:** Complete VAN rebuild across 3 hosts with infrastructure/runtime separation

## Executive Summary

Rebuilt the Skupper V2 Virtual Application Network from scratch across 3 hosts
(local-site, hub-rhel-ai, hub-rhtevan-work) to fix multiple operational issues.
The rebuild exposed 9 distinct issues, all resolved. The skill was refactored to
separate one-time infrastructure setup from daily start/stop operations.

## Timeline

| Time | Event |
|------|-------|
| ~15:00 | Teardown old VAN, plan rebuild with unique site names |
| ~15:15 | Phase 3: Build hub-rhel-ai — hit /tmp permission issue |
| ~15:30 | Investigated /tmp root cause (podman 4.x uid mapping) |
| ~15:40 | Fixed with --tmpfs + SSL_PROFILE_BASE_PATH + cert chmod |
| ~15:50 | Discovered system-controller doesn't auto-restart crashed router |
| ~15:55 | Developed start-watch.sh auto-restart patch, tested on rhel-ai |
| ~16:00 | Patched controller auto-restart on rhel-ai |
| ~16:17 | Phase 4: Built hub-rhtevan-work + applied auto-restart patches |
| ~16:21 | Phase 5: Built local-site + applied patches |
| ~16:22 | Phase 6: Links — hit port 55671 unreachable on rhel-ai |
| ~16:25 | Added hub-rhel-ai-public RouterAccess on port 8000 |
| ~16:26 | Hit SSL cert verify failed — no SANs on certs |
| ~16:28 | Added subjectAlternativeNames to all RouterAccess resources |
| ~16:29 | Hit `link generate` CLI bug — returns "no tokens found" |
| ~16:30 | Built link YAML manually from client certs |
| ~16:32 | Both links connected, VAN operational |
| ~16:46 | Refactored skill scripts (setup/teardown/up/down/status) |
| ~16:55 | Skill check passed, all guardrail compliance done |

## Root Cause Analysis

### Issue 1: /tmp Not Writable in Router Container (rhel-ai)

**Symptoms:** Router starts in Standalone mode instead of Interior. Logs show
`/tmp/skrouterd.json: Permission denied`.

**Root Cause:** On rhel-ai (podman 4.9.4 on RHEL 9 bootc), the rootless user
namespace mapping differs from podman 5.x. The container runs skrouterd as uid
10000 (user "runner"), but /tmp from the image layer inherits restrictive
permissions that uid 10000 cannot write to. The router's `launch.sh` entrypoint
copies the config to `/tmp/skrouterd.json` and runs `expandvars.py` to resolve
`${SSL_PROFILE_BASE_PATH}` variables — both fail silently, causing the router
to fall back to the embedded default standalone config.

**Fix:** `--tmpfs /tmp:rw,size=10M,mode=1777` on `podman run`. This overlays
a fresh writable tmpfs over /tmp inside the container.

**Why only rhel-ai?** podman 5.x (on local and rhtevan-work) handles rootless
namespace mapping differently and /tmp is writable by default.

**Why not fixed upstream?** rhel-ai runs bootc (immutable OS) — podman cannot
be upgraded. The image is baked in.

**Rejected alternatives:**
- Override entrypoint to skip launch.sh → loses `expandvars.py` variable
  expansion step that resolves `${SSL_PROFILE_BASE_PATH}`
- Upgrade podman → bootc is immutable, packages cannot be installed

### Issue 2: Cert File Permissions

**Symptoms:** Router fails to start with `Failed to configure TLS caCertFile`.

**Root Cause:** When `skupper system start` generates certs, files are created
with `640` permissions (owner: cloud-user, group: users). The container runs as
uid 10000 which is neither owner nor group member → permission denied.

**Fix:** `chmod -R o+r` on the certs directory after each `system start`.

**Why only rhel-ai?** On podman 5.x hosts, the container has different uid
mapping that allows reading the files.

### Issue 3: Missing SSL_PROFILE_BASE_PATH Environment Variable

**Symptoms:** After fixing /tmp, router still fails because cert paths contain
unresolved `${SSL_PROFILE_BASE_PATH}` in skrouterd.json.

**Root Cause:** The `expandvars.py` script in launch.sh resolves environment
variables in the config file. `SSL_PROFILE_BASE_PATH` tells skrouterd where
certs are mounted. When creating the container manually (to add --tmpfs), this
env var was not included.

**Fix:** Add `-e SSL_PROFILE_BASE_PATH=/etc/skupper-router` to `podman run`.

### Issue 4: No Auto-Restart on Router/Controller Crash

**Symptoms:** After `podman kill` of the router, it stays dead. systemd still
shows `active (exited)`. No recovery.

**Root Cause:** Skupper's generated systemd units use:
```ini
RemainAfterExit=yes
Type=simple
```
The `start.sh` script runs `podman start`, exits immediately (code 0), and
systemd considers the service "active" forever — it never monitors the actual
container process. There is no `Restart=` directive.

The system-controller container does NOT monitor router health or restart
crashed containers on the podman platform (unlike Kubernetes where pod
controllers handle this).

**Fix:** Created `start-watch.sh` that:
1. Runs `podman start` to start the container
2. Blocks on `podman wait --condition=stopped` (keeps systemd's main PID alive)
3. Traps SIGTERM (from `systemctl stop`) → touches stop marker → exits 0
4. On container exit without stop marker, checks exit code:
   - Exit 0 → exits 0 (no restart)
   - Non-zero → exits 1 (triggers `Restart=on-failure`)

Patched systemd unit:
```diff
- RemainAfterExit=yes
- ExecStart=.../start.sh
+ ExecStart=.../start-watch.sh
+ Restart=on-failure
+ RestartSec=5
```

**Applied to:** All 3 hosts, both router and controller services.

**Test results:**
| Test | Result |
|------|--------|
| `podman kill` router → auto-restart in ~6s | ✅ |
| `systemctl stop` → clean stop, no restart | ✅ |
| `systemctl start` after stop → works | ✅ |
| `podman kill` controller → auto-restart | ✅ |

### Issue 5: Stale CLI Status After Crash

**Symptoms:** After killing the router, `skupper site status` still shows
`Ready OK`.

**Root Cause:** The system-controller on the podman platform does NOT monitor
container health. It watches filesystem events (input/resources/ YAML changes)
and manages config reconciliation + cert rotation, but never checks if the
router container is actually running. The runtime YAML status files are written
once during bootstrap and never updated to reflect container state.

**Mitigation:** Auto-restart patch (Issue 4) ensures the router comes back
quickly, minimizing the window of stale status. The status is accurate most
of the time because the router is either running or about to restart.

**What system-controller actually does:**
1. Watches `input/resources/` → reconciles into `runtime/router/skrouterd.json`
2. Issues and rotates TLS certificates
3. Manages cert lifecycle (site-ca, service-ca, local-ca)

**What it does NOT do:**
- ❌ Monitor router container health
- ❌ Restart crashed containers
- ❌ Update runtime YAML status on container death

### Issue 6: Port 55671 Not Publicly Accessible on rhel-ai

**Symptoms:** Link from local to rhel-ai:55671 times out.

**Root Cause:** rhel-ai is hosted on AWS. Port 55671 is not in the security
group. Port 8000 IS publicly accessible (was used by the old VAN).

**Fix:** Added a second RouterAccess (`hub-rhel-ai-public`) on port 8000 with
its own TLS credentials and SANs including the public hostname.

### Issue 7: SSL Certificate Verify Failed on Links

**Symptoms:** Links fail with `SSL Failure: error:0A000086:SSL routines::
certificate verify failed`.

**Root Cause:** The RouterAccess resources were created without
`subjectAlternativeNames`. The server cert CN was `hub-rhel-ai` or
`hub-rhtevan-work`, but the client connects using IP addresses
(`RHTEVAN_WORK_IP`, `rhel-ai-host.example.com`). TLS verification
requires either a CN match or a SAN match — neither matched.

**Fix:** Added `subjectAlternativeNames` to all RouterAccess resources:
```yaml
subjectAlternativeNames:
  - "0.0.0.0"
  - "::"
  - RHTEVAN_WORK_IP        # or rhel-ai-host.example.com
  - work                 # or rhel-ai-internal.example.com
```

After adding SANs, the controller regenerated certs with the new SANs
automatically. Client link certs also needed to be re-fetched and re-applied.

### Issue 8: `skupper link generate` Returns "no tokens found"

**Symptoms:** `skupper --platform podman link generate -n model-provider-podman
--name hub-rhel-ai-public --host <PUBLIC_HOST>...` returns `no tokens found`.

**Root Cause:** CLI bug on the podman platform. The `link generate` command
only works with the default RouterAccess, not with named RouterAccess resources.
Even with `--name` flag, it cannot find the token.

**Fix:** Build link YAML manually:
1. Fetch client certs from remote host: `base64 -w0 .../client-<name>/ca.crt`
2. Construct Secret YAML with base64-encoded cert data
3. Construct Link YAML with correct host and port
4. Apply with `skupper system apply -f`

### Issue 9: No CLI Command to Stop Controller

**Symptoms:** No `skupper system stop-controller` or equivalent exists.

**Root Cause:** By design. The controller lifecycle is tied to
`skupper system install` / `skupper system uninstall`. There is no
granular stop/start.

**Fix:** Use `systemctl --user stop/start skupper-controller.service`.
Documented in skill's down.sh and status.sh.

## Duplicate Site Names

**Previous state:** Both rhel-ai and rhtevan-work were named "hub",
causing operational confusion when reading status output.

**Fix:** Unique site names suffixed with hostname:
- `hub-rhel-ai`
- `hub-rhtevan-work`  
- `local-site`

## Architecture Decisions

### 1. setup.sh / teardown.sh vs up.sh / down.sh

**Decision:** Separate one-time infrastructure operations from daily runtime.

**Rationale:** The old `up.sh` conflated site creation, resource application,
cert generation, linking, and container starting into a single 321-line script.
This made it fragile, hard to debug, and impossible to "just restart" without
risking re-creation of infrastructure.

| Script | Purpose | Runs |
|--------|---------|------|
| setup.sh | Create sites, apply resources, generate links, patch systemd | Once |
| teardown.sh | Remove sites, stop services | Decommission |
| up.sh | Start controllers, routers, model containers | Daily |
| down.sh | Stop model containers (optionally routers) | Daily |

### 2. Keep /tmp Workaround on rhel-ai Only

**Decision:** Only rhel-ai needs `--tmpfs` and manual `podman run`. Other
hosts use `skupper system start` / `systemctl` as-is.

**Rationale:** The /tmp issue is specific to podman 4.9.4 on bootc. Applying
the workaround universally would add unnecessary complexity and prevent using
skupper's native container management.

### 3. Manual Link Building Instead of `link generate`

**Decision:** Build link YAML manually from client certs on all links.

**Rationale:** `skupper link generate` is broken on podman platform for
non-default RouterAccess resources. Even for the default RouterAccess, the
generated link uses `host: 127.0.0.1` which must be manually fixed. Building
manually is more reliable and scriptable.

### 4. Controllers ~~Left Running~~ Now Stopped on `down.sh all`

**Decision (v6.0.0):** `down.sh all` stops routers but NOT controllers.

**Rationale:** Controllers manage cert rotation and config reconciliation.
Stopping them risks cert expiry. They are lightweight (~25MB memory) and
should run continuously.

> **Superseded in v6.1.1:** `down.sh all` now stops controllers on all
> 3 hosts. No reason to keep controllers alive when all routers are down.
> Controllers restart cleanly via `up.sh`.

## Metrics

| Metric | Value |
|--------|-------|
| Total issues found | 9 |
| Issues resolved | 9 |
| Time to rebuild | ~2 hours |
| Hosts affected | 3 |
| Scripts refactored | 6 (common, up, down, status + 2 new) |
| Total script lines | 1,337 (was 771) |
| Skill version | v5.1 → v6.0.0 |

## Lessons Learned

1. **Always add SANs to RouterAccess.** Without them, any link using IP
   addresses or hostnames that don't match the cert CN will fail TLS
   verification.

2. **`link generate` is unreliable on podman.** Always build link YAML
   manually from client certs.

3. **Skupper's systemd units are fire-and-forget.** The `RemainAfterExit=yes`
   pattern means systemd never monitors the actual container. Always patch
   with `start-watch.sh` + `Restart=on-failure`.

4. **System-controller ≠ container health monitor.** It only does config
   reconciliation and cert rotation. Don't rely on it for crash recovery.

5. **Separate infrastructure from runtime.** One-time setup (sites, links,
   certs) should be a different operation from daily start/stop. Mixing them
   creates fragile, hard-to-debug scripts.

6. **Unique site names are mandatory.** Duplicate names cause operational
   confusion and make status output ambiguous.

7. **podman 4.x vs 5.x rootless differences are real.** Always test on the
   actual target platform. What works on podman 5 may not work on podman 4.
