---
type: Reference
title: Large Network Scaling Guidelines
description: Best practices for scaling Skupper V2 beyond 16 sites using edge mode and hub-spoke topologies
tags: [skupper, scaling, large-networks, edge, topology]
timestamp: 2026-07-20T17:19:00-04:00
---

# Large Network Scaling

Skupper can scale to networks with many sites, but architecture choices matter significantly at scale.

## Scaling Guidelines

| Network Size | Recommendation |
|-------------|----------------|
| ≤ 16 sites | All interior routers, any topology works |
| 17–100 sites | Use edge sites for leaf nodes, interior sites as backbone |
| 100+ sites | Hub-and-spoke with multiple interior hubs, edges at leaves |

## Key Principles

### Use Edge Sites Beyond 16 Sites

Edge routers maintain minimal routing state, reducing memory and CPU:

| Aspect | Interior Router | Edge Router |
|--------|:--------------:|:-----------:|
| Routing table | Full network view | Only knows connected interior |
| Transit traffic | ✅ Routes for others | ❌ Own traffic only |
| Memory at scale | High | Low |
| CPU at scale | Higher | Lower |
| HA support | ✅ | ❌ |

### Don't Build One Big Network

From the official docs:
> "You should not try to put a bunch of applications on one big network. It's less secure and less performant."

Separate applications should have **separate Skupper networks**.

### Multiple Smaller Networks Are Better

Each application or bounded context should get its own network for:
- Better security isolation
- Better performance (smaller routing tables)
- Simpler troubleshooting

## Topology Patterns

### Small (≤16 sites) — All Interior

```
     Interior (linkAccess: default)  ← Hub
        ↑           ↑          ↑
     Interior    Interior    Interior
```

### Medium (17-100) — Hub + Edges

```
     Interior Hub (linkAccess: default)
        ↑           ↑          ↑
      Edge         Edge        Edge
      Edge         Edge        Edge
```

### Large (100+) — Multi-Hub Backbone

```
  Interior A ←→ Interior B ←→ Interior C
    ↑  ↑  ↑       ↑  ↑  ↑       ↑  ↑  ↑
   E  E  E       E  E  E       E  E  E
   E  E  E       E  E  E       E  E  E
   ...            ...            ...
```

Interior hubs maintain full routing tables and can transit traffic between edges. Edges are lightweight — they only maintain a connection to their hub.
