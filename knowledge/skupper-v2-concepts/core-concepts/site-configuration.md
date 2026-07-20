---
type: Reference
title: Site Configuration — Edge Mode, Link Access, and HA
description: How edge, linkAccess, and ha fields interact to define site topology and capabilities
tags: [skupper, site, edge, link-access, ha, topology]
timestamp: 2026-07-20T17:19:00-04:00
---

# Site Configuration

The Site resource is the parent of all Skupper resources in a namespace. Its key fields control topology, accessibility, and resilience.

## Core Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `linkAccess` | string | `none` | External access for incoming links |
| `edge` | boolean | `false` | Edge mode — lightweight router, no inbound links |
| `ha` | boolean | `false` | High availability — two active routers |
| `defaultIssuer` | string | `skupper-site-ca` | Signing CA for AccessGrant and RouterAccess |

## linkAccess Values

| Value | Behavior |
|-------|----------|
| `none` | No inbound linking permitted (default) |
| `default` | Platform default (OpenShift → route, other K8s → loadbalancer) |
| `route` | OpenShift Route (OpenShift only) |
| `loadbalancer` | K8s Service type LoadBalancer |

## Edge Mode

Edge sites run a simplified router with minimal routing state.

| Capability | Interior (`edge: false`) | Edge (`edge: true`) |
|------------|:------------------------:|:-------------------:|
| Create outbound links | ✅ | ✅ |
| Accept inbound links | ✅ (if linkAccess set) | ❌ Never |
| Host Listeners | ✅ | ✅ |
| Host Connectors | ✅ | ✅ |
| Transit traffic for other sites | ✅ | ❌ |
| Full network routing table | ✅ | ❌ (only knows its connected interior) |
| HA support | ✅ | ❌ |

**There is no "Listener-only" or "Connector-only" site.** Every site can host both regardless of mode.

## How edge and linkAccess Interact

| `edge` | `linkAccess` | Accept Inbound? | Behavior |
|:------:|:------------:|:---------------:|----------|
| `false` | `none` | ❌ | Interior router, must link out |
| `false` | `default`/`route`/`loadbalancer` | ✅ | **Hub site** — accepts links |
| `true` | `none` | ❌ | **Typical edge** — links out only |
| `true` | any value | ❌ | **`edge` overrides `linkAccess`** — setting is ignored |

## High Availability

`ha: true` runs **two active router pods** simultaneously (Kubernetes only).

| Aspect | Detail |
|--------|--------|
| What runs | Two router pods, both active |
| Controller | Single instance (not HA) |
| Edge sites | Cannot use HA |
| Platform | Kubernetes only |
| Without HA | Single stateless router restarts quickly |

## Topology Patterns

### Small (≤16 sites)
All interior routers, any topology.

### Medium (17-100 sites)
Interior backbone with edge sites as leaves.

### Large (100+ sites)
Multiple interior hubs with many edge sites per hub.

```
  Interior Hub A ←→ Interior Hub B ←→ Interior Hub C
    ↑  ↑  ↑  ↑        ↑  ↑  ↑  ↑       ↑  ↑  ↑  ↑
   E  E  E  E        E  E  E  E       E  E  E  E
```

## Minimal Examples

```yaml
# Hub site — accepts links
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: hub
spec:
  linkAccess: default
  ha: true
```

```yaml
# Edge site — links out only
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: edge-store-42
spec:
  edge: true
```
