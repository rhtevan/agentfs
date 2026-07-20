---
type: Reference
title: AttachedConnector and AttachedConnectorBinding
description: Cross-namespace service exposure on Kubernetes without deploying a router in the workload namespace
tags: [skupper, attached-connector, cross-namespace, kubernetes]
timestamp: 2026-07-20T17:19:00-04:00
---

# AttachedConnector and AttachedConnectorBinding

These resources enable a workload in a **peer Kubernetes namespace** to connect to a Skupper site in another namespace — without deploying a router in the workload namespace.

## Platform Support

**Kubernetes only.** These resources solve a Kubernetes-specific problem (namespace isolation). On Docker, Podman, or Linux, a regular Connector with `host` is sufficient.

## The Two-Sided Handshake

Both namespaces must explicitly agree to the attachment (security by design).

| Resource | Where It Lives | Who Controls It | What It Specifies |
|----------|---------------|-----------------|-------------------|
| **AttachedConnectorBinding** | Site namespace (router) | Network admin | `routingKey`, `connectorNamespace` |
| **AttachedConnector** | Workload namespace (app) | App team | `selector`, `port`, `siteNamespace` |

**Both must have the same `metadata.name`** — that's how they find each other.

## Separation of Concerns

| Concern | Who Decides | Resource |
|---------|------------|----------|
| Routing key (network identity) | Network admin | AttachedConnectorBinding |
| Which pods and port | App team | AttachedConnector |

Neither side can act alone:
- App team can't inject services into the network without a Binding
- Network admin can't reach into another namespace's pods without an AttachedConnector

## Example

**Workload namespace** (`databases`):

```yaml
apiVersion: skupper.io/v2alpha1
kind: AttachedConnector
metadata:
  name: database           # Must match Binding name
  namespace: databases
spec:
  siteNamespace: skupper   # Points to site namespace
  port: 5432
  selector: app=postgres
```

**Site namespace** (`skupper`):

```yaml
apiVersion: skupper.io/v2alpha1
kind: AttachedConnectorBinding
metadata:
  name: database           # Must match AttachedConnector name
  namespace: skupper
spec:
  connectorNamespace: databases
  routingKey: database
```

## Multiple Networks

To expose the same workload on multiple Skupper networks, create one AttachedConnector per network (each with a matching Binding in the respective site namespace).

## Comparison with Regular Connector

| Feature | Connector | AttachedConnector + Binding |
|---------|-----------|----------------------------|
| Namespaces | Same as Site | Different from Site |
| Resources needed | 1 | 2 (mutual opt-in) |
| CLI support | ✅ | ❌ YAML only |
| Router in workload namespace | N/A | **Not required** |
| Multi-network exposure | Multiple Connectors in multiple Sites | One AC per network |

## Key Constraints

- Names must match between AC and ACB
- Namespace cross-references must match (`siteNamespace` ↔ ACB namespace, `connectorNamespace` ↔ AC namespace)
- CLI not supported — YAML only
- `exposePodsByName` is available on AttachedConnectorBinding
