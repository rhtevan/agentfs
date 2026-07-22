---
type: Reference
title: Linux/systemd Platform Architecture
description: How Skupper V2 runs on Linux using native skrouterd binary, systemd services, and bootstrap containers
tags: [skupper, linux, systemd, skrouterd, architecture, bootstrap]
timestamp: 2026-07-22T19:03:00-04:00
---

# Linux/systemd Platform Architecture

The Linux/systemd platform is architecturally unique among Skupper V2 platforms. The router runs as a **native process**, not a container.

## How Each Platform Runs the Router

| Platform | Router Runs As | Controller | Container Runtime Required |
|----------|---------------|------------|:--------------------------:|
| **Kubernetes** | Pod (container) | Controller Pod + Kube-Adaptor | Yes (K8s) |
| **Docker** | Docker container | Controller container | Yes |
| **Podman** | Podman container | Controller container | Yes |
| **Linux (systemd)** | **Native `skrouterd` binary** via systemd | **None** | Yes (bootstrap only) |

## The Two Systemd Service Templates

Skupper uses different templates based on platform:

### Linux template (`systemd_service.template`)

```ini
[Service]
ExecStart=skrouterd -c {{.SiteConfigPath}}/skrouterd.json
Environment="SKUPPER_SITE_ID={{.SiteId}}"
```

Runs the router binary **directly** — no container.

### Container template (`systemd_container_service.template`)

```ini
[Service]
ExecStart=/bin/bash {{.SiteScriptPath}}/start.sh
ExecStop=/bin/bash {{.SiteScriptPath}}/stop.sh
```

Runs scripts that manage a **container**.

Template selection (from `systemd.go`):

```go
if s.platform == string(types.PlatformLinux) {
    // Native binary template
} else {
    // Container template
}
```

## The Bootstrap Container

Despite running the router natively, the Linux platform **does** use a container during `skupper system start` — for config generation only.

### Two Container Images

| Image | Purpose | When Used |
|-------|---------|----------|
| `quay.io/skupper/cli` | Config generation (bootstrap) | One-time during `system start`, then exits |
| `quay.io/skupper/skupper-router` | Actual router data plane | **NOT used on Linux** — only Docker/Podman/K8s |

### Bootstrap Flow

```
Step 1: Bootstrap (ephemeral container)
  quay.io/skupper/cli container:
    - Reads YAML resources from /input
    - Generates skrouterd.json, TLS certs, systemd service files
    - Writes output to /output
    - Container exits (--rm)

Step 2: Install systemd service (on host)
  bootstrap.sh copies service file → ~/.config/systemd/user/
  systemctl --user enable --now skupper-<ns>.service

Step 3: Router runs (native, ongoing)
  skrouterd -c <path>/skrouterd.json
  No container. Runs indefinitely.
```

### Why Use a Container for Config Generation?

The bootstrap container enables **site bundles** — pre-packaged site configurations that can be deployed on remote hosts without the CLI installed. The same config generation logic works for both direct CLI usage and bundle deployment.

## No Controller on Linux

Unlike Docker/Podman (which have a long-running controller container that auto-reconciles), Linux has **no controller**:

| Platform | Config Change Handling |
|----------|----------------------|
| Kubernetes | Controller auto-reconciles via CRD watches |
| Docker/Podman (auto) | Controller container auto-reconciles |
| Docker/Podman (manual) | `skupper system reload` |
| **Linux** | `skupper system reload` → re-runs bootstrap → regenerates config → restarts service |

## User vs Root Service Installation

| Running As | Service Location | Control |
|-----------|-----------------|--------|
| Regular user | `~/.config/systemd/user/skupper-<ns>.service` | `systemctl --user` |
| Root | `/etc/systemd/system/skupper-<ns>.service` | `systemctl` |

## Prerequisites for Linux Platform

| Prerequisite | Direct CLI | Site Bundle |
|-------------|:----------:|:-----------:|
| `skrouterd` binary | ✅ Required | ✅ Required |
| Container engine (Podman/Docker) | ✅ Required (bootstrap) | ❌ Not required |
| Skupper CLI | ✅ Required | ❌ Not required |
| systemd | ✅ Required | ✅ Required |
| Python | ❌ | ✅ Required (port selection) |
