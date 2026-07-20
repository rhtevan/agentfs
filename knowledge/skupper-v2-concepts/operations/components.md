---
type: Reference
title: Skupper V2 Software Components
description: The controller, kube-adaptor, router, and network observer components that make up a Skupper deployment
tags: [skupper, components, architecture, controller, router]
timestamp: 2026-07-20T17:19:00-04:00
---

# Skupper V2 Components

## On Kubernetes

| Component | Role |
|-----------|------|
| **Controller** | Watches CRDs (Site, Listener, Connector, etc.) and reconciles them. Interacts only with the Kube API. |
| **Kube-Adaptor** | Bridge between Controller output and the router. All direct router interaction goes through kube-adaptor. |
| **Router** (`skupper-router`) | Data plane — routes application traffic between sites. Stateless. |
| **Network Observer** | Optional. Collects flow data, provides web console + metrics. Deployed separately via Helm. |

```
Controller ──→ Kube API ──→ Kube-Adaptor
(reconciles     (CRDs)      (configures router)
 resources)          │
                skupper-router
                (data plane)
```

## On Linux/Docker/Podman (System Mode)

Simpler architecture — no Kubernetes API, no controller:

| Component | Role |
|-----------|------|
| **skupper-router** | Router process (systemd service or container) |
| **Skupper CLI** (`skupper system ...`) | Manages configuration files directly |

## Platform Feature Matrix

| Resource/Feature | Kubernetes | Docker | Podman | Linux (systemd) |
|-----------------|:----------:|:------:|:------:|:---------------:|
| Site | ✅ | ✅ | ✅ | ✅ |
| Link | ✅ | ✅ | ✅ | ✅ |
| AccessGrant / AccessToken | ✅ | ✅ | ✅ | ✅ |
| Listener | ✅ | ✅ | ✅ | ✅ |
| Connector | ✅ (selector) | ✅ (host) | ✅ (host) | ✅ (host) |
| MultiKeyListener | ✅ | ✅ | ✅ | ✅ |
| RouterAccess | ✅ | ✅ | ✅ | ✅ |
| AttachedConnector / Binding | ✅ | ❌ | ❌ | ❌ |
| HA (`ha: true`) | ✅ | ❌ | ❌ | ❌ |
| Network Console | ✅ | ❌ | ❌ | ❌ |
| `exposePodsByName` | ✅ | ❌ | ❌ | ❌ |

## Configuration Workflows

Skupper V2 has four parallel workflow paths:

| Workflow | Platform | Method |
|----------|----------|--------|
| Kubernetes CLI | Kubernetes | `skupper` commands |
| Kubernetes YAML | Kubernetes | `kubectl apply` CRDs |
| System CLI | Linux/Docker/Podman | `skupper system` commands |
| System YAML | Linux/Docker/Podman | File-based config |
