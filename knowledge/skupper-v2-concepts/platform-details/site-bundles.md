---
type: Reference
title: Site Bundles — Remote Deployment Without CLI
description: How to generate and deploy self-contained site bundles for remote hosts, including Linux/systemd support
tags: [skupper, site-bundle, deployment, linux, remote, install]
timestamp: 2026-07-22T19:03:00-04:00
---

# Site Bundles

Site bundles are **self-contained deployment packages** that allow installing a Skupper site on a remote host without requiring the Skupper CLI on that host.

## Generating a Bundle

```bash
# On your workstation (has CLI + container engine)
export SKUPPER_PLATFORM=linux   # or podman, docker
skupper site create my-remote-site
skupper system generate-bundle my-remote-site
# Output: ~/.local/share/skupper/bundles/my-remote-site.tar.gz
```

### Bundle Types

| `--type` | Output |
|----------|--------|
| `tarball` (default) | `.tar.gz` archive with `install.sh` |
| `shell-script` | Single self-extracting shell script |

## Deploying a Bundle

```bash
# Transfer to remote host, then:
tar -xzf my-remote-site.tar.gz
./install.sh -p linux    # or -p podman, -p docker
```

### Supported Platforms

```
Usage: install.sh [-p <podman|docker|linux>]
```

The bundle can target **any** of the three non-K8s platforms, regardless of which platform was used when generating it.

## What's Included vs What's Not

| Included in Bundle | NOT Included |
|:--:|:--:|
| ✅ Site YAML resources | ❌ `skrouterd` binary |
| ✅ Router config (`skrouterd.json`) | ❌ Container engine |
| ✅ TLS certificates | ❌ Skupper CLI |
| ✅ Systemd service files (both templates) | |
| ✅ Start/stop scripts (container platforms) | |
| ✅ `install.sh` script | |
| ✅ Static link tokens | |

## Key Difference: No Bootstrap Container

| Method | Bootstrap Container? | Config Generation |
|--------|:--------------------:|------------------|
| `skupper system start` (direct CLI) | ✅ Yes | Container generates config |
| Site bundle `install.sh` | ❌ **No** | Config is **pre-generated** in the bundle |

This means a Linux/systemd target using a bundle needs **only**:
- `skrouterd` binary
- systemd
- Python (for port selection)
- Standard shell utilities

**No container engine and no Skupper CLI required on the target.**

## How install.sh Works

1. Copies pre-rendered config files to `~/.local/share/skupper/namespaces/<ns>/`
2. Runs `sed` to fill in host-specific values (site ID, paths, namespace)
3. Selects the correct systemd service template (native for Linux, container for Docker/Podman)
4. Creates containers (Docker/Podman only) or skips (Linux)
5. Installs and enables the systemd service
6. Site is running

## Bundle Management

```bash
# Install
./install.sh -p linux -n my-namespace

# Remove
./install.sh -x

# Dump static link tokens
./install.sh -d /path/to/output/
```

## Use Case: Edge Deployment at Scale

```
Workstation                    Remote Edge Hosts (×100)
┌──────────────┐              ┌──────────────────────┐
│ skupper CLI   │   transfer   │ Only needs:           │
│ generate-     │──────────→  │  - skrouterd          │
│ bundle        │  .tar.gz    │  - systemd            │
│               │              │  - python, sed, etc.  │
│               │              │                       │
│               │              │ ./install.sh -p linux │
│               │              │ → site running        │
└──────────────┘              └──────────────────────┘
```
