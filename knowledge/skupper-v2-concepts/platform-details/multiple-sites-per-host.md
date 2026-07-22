---
type: Reference
title: Multiple Sites per Host — Namespace-Scoped Services
description: Running multiple independent Skupper sites on a single Linux host using filesystem namespaces
tags: [skupper, linux, namespaces, multi-site, systemd, ports]
timestamp: 2026-07-22T19:03:00-04:00
---

# Multiple Sites per Host

A single Linux host can run **multiple independent Skupper sites**, each in its own namespace. Each site gets its own `skrouterd` process, systemd service, and configuration.

## Creating Multiple Sites

```bash
skupper site create site-east -p linux -n east
skupper site create site-west -p linux -n west
skupper site create site-edge -p linux -n edge
```

## What Gets Created

Each namespace produces an independent systemd service:

```
skupper-east.service
  └── skrouterd -c ~/.local/share/skupper/namespaces/east/runtime/router/skrouterd.json

skupper-west.service
  └── skrouterd -c ~/.local/share/skupper/namespaces/west/runtime/router/skrouterd.json

skupper-edge.service
  └── skrouterd -c ~/.local/share/skupper/namespaces/edge/runtime/router/skrouterd.json
```

## Filesystem Namespace Structure

```
~/.local/share/skupper/namespaces/
├── east/
│   ├── input/resources/     ← Site, Connector, Listener YAMLs
│   ├── input/certs/         ← TLS certificates
│   ├── runtime/router/
│   │   └── skrouterd.json   ← Router config (unique)
│   └── internal/
│       └── platform.yaml
├── west/
│   └── ... (same structure)
└── edge/
    └── ... (same structure)
```

This is the non-K8s equivalent of Kubernetes namespaces:

| Kubernetes | Non-K8s Filesystem |
|------------|-------------------|
| Namespace | `~/.local/share/skupper/namespaces/<name>/` |
| CRD resources | YAML files in `input/resources/` |
| Secrets (TLS) | Directories in `input/certs/` |
| Multiple namespaces | Multiple directories; use `skupper -n <name>` |

## Each Site Is Fully Independent

| Resource | Per-Namespace? |
|----------|:-:|
| `skrouterd` process | ✅ |
| systemd service | ✅ `skupper-<ns>.service` |
| `skrouterd.json` config | ✅ |
| TLS certificates | ✅ |
| Site identity | ✅ |
| Listeners (ports) | ✅ — **must use different ports** |
| Links | ✅ |
| YAML resources | ✅ |

## Port Conflict Considerations

All `skrouterd` processes share the **same host network**. Ports must be unique across all sites:

- **Listener ports** — each site's Listeners must bind different ports
- **RouterAccess ports** (55671, 45671) — each site accepting links needs unique ports
- **Local management port** (5671) — auto-assigned per site

## Managing Multiple Sites

```bash
# CLI uses -n flag
skupper site status -n east
skupper connector status -n west
skupper system reload -n edge

# Systemctl
systemctl --user status skupper-east
systemctl --user status skupper-west
journalctl --user -u skupper-edge
```

## Use Cases

| Use Case | Example |
|----------|--------|
| Multiple networks | Same host in production and staging Skupper networks |
| Testing | Simulate multi-site topology on a single machine |
| Multi-tenant | Different applications with separate networks |
| Development | Replicate distributed setup locally |
