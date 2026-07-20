---
type: Reference
title: Listener, Connector, and Routing Key Model
description: How Skupper V2 exposes services using the Listener + Connector + Routing Key pattern
tags: [skupper, listener, connector, routing-key, service-exposure]
timestamp: 2026-07-20T17:19:00-04:00
---

# Listener, Connector, and Routing Key Model

Skupper V2 uses an explicit three-part model for service exposure.

## How It Works

1. **Listener** (consumer site): Creates a local service endpoint (host:port) that client workloads connect to
2. **Connector** (provider site): Binds to local server workloads (via pod selector or host)
3. **Routing Key**: A string that matches listeners to connectors. Traffic flows from listener → router → connector when keys match.

## Listener Resource

```yaml
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: backend
spec:
  routingKey: backend      # Must match connector's routing key
  host: backend             # Local service hostname
  port: 8080                # Local service port
```

Key fields:

| Field | Required | Description |
|-------|----------|-------------|
| `routingKey` | Yes | Matches to connectors |
| `host` | Yes | Local hostname for the service |
| `port` | Yes | Local port |
| `exposePodsByName` | No | Expose individual pods as separate services |
| `tlsCredentials` | No | TLS for client-to-router communication |
| `settings.observer` | No | Protocol inspection: `auto`, `none`, `http1`, `http2` |

**No explicit routing algorithm field.** The Listener does not have a `strategy` or `algorithm` field — routing is implicit via link cost.

## Connector Resource

On Kubernetes (uses `selector`):

```yaml
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: backend
spec:
  routingKey: backend
  port: 8080
  selector: app=backend    # K8s label selector
```

On Linux/Docker/Podman (uses `host`):

```yaml
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: backend
spec:
  routingKey: backend
  port: 8080
  host: localhost          # Or IP address
```

## Single Routing Key with Multiple Connectors

A single routing key can be shared by **multiple connectors** across different sites. This provides automatic load balancing and failover without needing a MultiKeyListener:

- Router distributes connections across all connectors sharing the key
- Link cost influences which connector is preferred
- If a connector becomes unreachable, traffic automatically reroutes

## Multi-Port Services

To expose a multi-port service, create multiple listeners with the same `host` but different ports.
