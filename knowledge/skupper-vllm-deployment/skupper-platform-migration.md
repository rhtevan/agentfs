---
type: Postmortem
title: "Skupper Platform Migration: Linux/Systemd → Podman"
description: "Why custom-built skrouterd on linux platform failed and how the official container image on podman platform solved it"
tags: [skupper, podman, systemd, skrouterd, qpid-proton, deployment]
timestamp: 2026-08-08T12:09:00-04:00
---

# Skupper Platform Migration: Linux/Systemd → Podman

## Context

Skupper V2 supports two non-Kubernetes platforms: `linux` (systemd)
and `podman` (container). The linux platform runs `skrouterd` as a
native binary managed by systemd. The podman platform runs
`quay.io/skupper/skupper-router` as a container.

## The Custom Build Saga (Linux Platform)

The target host `rhel-ai` (RHEL 9, glibc 2.34) had no pre-built
skrouterd package. Building from source required:

### Dependency Chain

1. **qpid-proton** (AMQP library) — needed OpenSSL headers, which
   RHEL 9 container image didn't have. Required extracting headers
   from a separate tarball.
2. **libwebsockets** — not available in the container image. Built
   from source (v4.3.3).
3. **nghttp2** — headers missing, copied from Fedora host.
4. **OpenSSL symlinks** — container had `libssl.so.3` but no
   `libssl.so` symlink, causing CMake to fail.
5. **Python 3.11 stdlib** — skrouterd embeds Python; the container
   had Python 3.11 but the host had Python 3.9. Required extracting
   the stdlib from the container.
6. **config.h collision** — skupper-router has two `config.h.in`
   files (in `src/` and `router/src/`). The wrong one was found
   during compilation, causing undefined macro errors.

### Build Iterations

Over **13 build script versions** (v1 through final), each fixing
a new issue:
- v1-v4: Proton version mismatch (0.40 vs 0.41)
- v5-v8: OpenSSL headers and TLS component failures
- v9-v11: nghttp2, libwebsockets missing
- v12-v13: CMake policy version, pkg-config path issues
- Final: config.h rename patch to resolve collision

### The octets=0 Mystery

After successfully building skrouterd 3.4.2:
- TCP connection established ✅
- TLS handshake succeeded ✅
- AMQP connection opened (`operStatus=up`) ✅
- **Zero bytes of AMQP management data exchanged** ❌

The loopback test (edge→hub on same machine) showed `octets=37`,
proving the build worked locally. But remote connections always
showed `octets=0, octetsReverse=0`.

**Root cause:** The custom-built skrouterd had an incomplete Python
management agent setup. The management agent activates (log shows
`AGENT (info) Activating`) but doesn't properly handle incoming
management queries, so the hub never sends routing data back to
the edge.

## The Podman Solution

Switching to `quay.io/skupper/skupper-router:latest` (v3.5.2)
resolved everything immediately:

- ✅ All dependencies bundled correctly in the container
- ✅ Python management agent fully functional
- ✅ AMQP data exchange worked on first connection
- ✅ Port 9000 listener opened instantly (connector visible through mesh)

## Podman Platform Gotchas

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| `/tmp` not writable | Container runs as uid 10000, `/tmp` owned by root (755) | `--tmpfs /tmp:rw,size=10M,mode=1777` |
| TLS certs not readable | Certs generated as 640, container uid 10000 can't read | `chmod -R o+r` on certs directory |
| `skupper system stop` deletes everything | Podman platform removes namespace on stop | Use `podman stop` on container instead |
| Connector host for co-located services | Container needs to reach host network | Use `host.containers.internal` not `localhost` |
| Old linux-platform skrouterd respawns | systemd service restarts and steals port | `systemctl --user mask skupper-model-provider.service` |

## Key Lesson

**Don't build infrastructure from source when an official container
image exists.** The 13+ build iterations, library dependency hunting,
and mysterious `octets=0` bug consumed ~8 hours. The podman approach
took ~30 minutes.
