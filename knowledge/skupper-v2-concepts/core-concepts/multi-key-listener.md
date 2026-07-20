---
type: Reference
title: MultiKeyListener — Explicit Traffic Distribution
description: How MultiKeyListener provides per-service weighted load balancing and priority failover across routing keys
tags: [skupper, multi-key-listener, load-balancing, failover, weighted, priority]
timestamp: 2026-07-20T17:19:00-04:00
---

# MultiKeyListener

A MultiKeyListener binds a **single local host:port** to **multiple routing keys** with an explicit strategy for traffic distribution. This is the **recommended** approach for per-service load balancing and failover control.

## When to Use

| Scenario | Use |
|----------|-----|
| Same service in multiple sites, same config | Standard Listener (single routing key, multiple connectors) |
| Explicit weight control between groups | **MultiKeyListener with `weighted`** |
| Active/passive failover between different services | **MultiKeyListener with `priority`** |
| Canary/blue-green deployments | **MultiKeyListener with `weighted`** |

## Weighted Strategy

Distributes traffic proportionally across routing keys:

```yaml
apiVersion: skupper.io/v2alpha1
kind: MultiKeyListener
metadata:
  name: backend
spec:
  host: backend
  port: 8080
  strategy:
    weighted:
      routingKeys:
        east-backend: 75    # 75% of connections
        west-backend: 25    # 25% of connections
```

## Priority Strategy

Routes all traffic to the first available routing key; fails over to the next:

```yaml
apiVersion: skupper.io/v2alpha1
kind: MultiKeyListener
metadata:
  name: backend
spec:
  host: backend
  port: 9095
  strategy:
    priority:
      routingKeys:
        - primary-backend    # All traffic here when available
        - backup-backend     # Failover only
```

## Key Properties

| Property | Detail |
|----------|--------|
| `strategy` | Required. Must be exactly one of `priority` or `weighted`. **Immutable after creation.** |
| `host` / `port` | Updatable |
| `observer` | Protocol inspection: `auto`, `none`, `http1`, `http2` |
| `status.hasDestination` | `true` if at least one connector exists for any matched routing key |

## Strategy vs Link Cost

- Strategy selects **between routing keys** independently of link cost
- Link cost determines which **connector within a routing key** handles traffic
- Multiple MultiKeyListeners referencing the same routing keys make independent decisions

## MultiKeyListener vs Single Routing Key

| Feature | Single Routing Key | MultiKeyListener |
|---------|-------------------|------------------|
| Connectors share | Same routing key | Different routing keys |
| Load balancing | Automatic (link-cost based) | Explicit weights |
| Failover | Automatic (router detects) | Explicit priority ordering |
| Granularity | Router decides | You decide |
| Docs recommendation for per-service control | "Alternative" | **"Preferred approach"** |
