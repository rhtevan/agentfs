---
type: Reference
title: Load Balancing and Failover Mechanisms
description: Two approaches to traffic distribution in Skupper V2 — link cost (implicit) vs MultiKeyListener (explicit)
tags: [skupper, load-balancing, failover, link-cost, routing]
timestamp: 2026-07-20T17:19:00-04:00
---

# Load Balancing and Failover

Skupper V2 provides two mechanisms for controlling traffic distribution. The official docs recommend MultiKeyListener as the preferred approach.

## Approach 1: MultiKeyListener (Preferred)

Per-service, explicit control. See [MultiKeyListener](./multi-key-listener.md).

- **Weighted**: Proportional distribution across routing keys
- **Priority**: Failover with preference order
- **Per-service**: Each service gets its own strategy
- **Predictable**: Not influenced by connection timing or link metrics

## Approach 2: Link Cost (Alternative)

Global, implicit control via the `cost` field on Link resources.

```yaml
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: link-to-backup
spec:
  cost: 99999    # Very high = failover only
```

### Link Cost Behavior

| Rule | Detail |
|------|--------|
| Default cost | `1`. Local workloads have implicit cost `0`. |
| Multi-hop | Path cost = sum of all link costs along the path |
| Threshold behavior | Traffic flows on lowest-cost path until open connections exceed the cost of an alternative path, then spills over |
| Distribution | Statistical, **not** round robin |
| Scope | Applies to **ALL services** on a link — cannot be set per-service |
| Single path | When only one path exists, traffic flows regardless of cost |
| Failover | If a target becomes unavailable, traffic moves to remaining path regardless of cost |

### Failover via Link Cost

Set backup link cost very high:

- Local server: effective cost `0`
- Remote backup: link cost `99999`
- Result: All traffic goes local; failover to remote only when local is down

### Limitations

- Cannot set different costs for different services on the same link
- No orchestrated failover for stateful applications
- Behavior depends on connection count thresholds

## Comparison

| Aspect | Link Cost | MultiKeyListener |
|--------|-----------|------------------|
| Granularity | Per-link (global) | Per-service |
| Control | Implicit (threshold-based) | Explicit (weights/priority) |
| Predictability | Depends on connection count | Deterministic ratios |
| Configuration | On Link resource | On MultiKeyListener resource |
| Docs recommendation | "Alternative" | **"Preferred"** |
