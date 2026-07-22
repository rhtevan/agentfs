---
type: Reference
title: Application TLS — Hop-by-Hop and Passthrough
description: How to configure TLS for client-to-router and router-to-server segments, plus end-to-end TLS passthrough in Skupper V2
tags: [skupper, tls, security, encryption, hop-by-hop, passthrough, end-to-end]
timestamp: 2026-07-22T15:39:00-04:00
---

# Application TLS

Application TLS secures the traffic between client applications and server workloads as it traverses the Skupper network. This is **distinct** from the automatic router-to-router mTLS.

## Three TLS Segments

```
Client App → [Listener] → router ←→ router → [Connector] → Server App
   │              │                               │              │
   └── Segment 1 ─┘     Segment 2 (auto)          └── Segment 3 ─┘
  Client-to-Router      Router-to-Router          Router-to-Server
```

| Segment | What | How Configured | Automatic? |
|---------|------|----------------|:----------:|
| 1. Client-to-Router | Client connects to Listener | `tlsCredentials` on **Listener** | No |
| 2. Router-to-Router | Inter-router transport | Always mTLS | **Yes** |
| 3. Router-to-Server | Router connects to workload | `tlsCredentials` on **Connector** | No |

## Important: Hop-by-Hop, Not End-to-End

Skupper Application TLS provides **hop-by-hop** encryption:

- ✅ All traffic encrypted in transit
- ✅ Simplified certificate management (Skupper can issue certs)
- ❌ Router can see plaintext (decrypts and re-encrypts at each hop)

For true **end-to-end TLS**, the application must handle TLS itself — Skupper passes encrypted bytes through transparently.

## TLS on a Listener

```yaml
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: backend
spec:
  routingKey: backend
  host: backend
  port: 8443
  tlsCredentials: backend-server-cert    # K8s Secret: tls.crt + tls.key
```

## Mutual TLS on a Listener

```yaml
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: backend
spec:
  routingKey: backend
  host: backend
  port: 8443
  tlsCredentials: backend-server-cert
  requireClientCert: true                # Clients must present valid cert
```

Note: `requireClientCert` is available on both Listener and MultiKeyListener.

## TLS on a Connector

```yaml
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: backend
spec:
  routingKey: backend
  port: 8443
  selector: app=backend
  tlsCredentials: backend-client-cert    # Secret with CA cert (+ optional client cert)
```

## TLS Passthrough (End-to-End Encryption)

Skupper also supports **true end-to-end TLS** by simply **not configuring** `tlsCredentials` on either the Listener or Connector. In this mode, the router treats traffic as **opaque TCP bytes** and never terminates or inspects the TLS.

```
Client App (TLS) → [Listener] → router ←→ router → [Connector] → Server App (TLS)
     │                                                                    │
     └────────────── End-to-end TLS (app-managed) ───────────────────────┘
                     Router sees encrypted bytes only
```

### Passthrough Configuration

```yaml
# Listener — NO tlsCredentials
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: backend
spec:
  routingKey: backend
  host: backend
  port: 8443
  # No tlsCredentials → router doesn't terminate TLS
  settings:
    observer: "none"    # Recommended: skip protocol inspection
```

```yaml
# Connector — NO tlsCredentials
apiVersion: skupper.io/v2alpha1
kind: Connector
metadata:
  name: backend
spec:
  routingKey: backend
  port: 8443
  selector: app=backend
  # No tlsCredentials → router passes bytes through
```

### Observer Setting for Passthrough

| `observer` Value | Behavior with TLS Passthrough |
|-----------------|-------------------------------|
| `auto` (default) | Tries to inspect traffic, fails on encrypted payload — wastes CPU, no useful telemetry |
| `none` | **Recommended** — disables inspection, reduces overhead |
| `http1` / `http2` | Useless — can't parse encrypted HTTP |

### Double Encryption Benefit

In passthrough mode, the inter-router transport still uses its own mTLS (Segment 2). Traffic gets **double encryption** in transit:

```
Application TLS payload (end-to-end)
  └── wrapped inside router mTLS (inter-router transport)
```

### Two TLS Models Compared

| Model | How | Router Sees Plaintext? | Cert Management |
|-------|-----|:----------------------:|----------------|
| **Hop-by-hop** (Skupper-managed) | Set `tlsCredentials` on Listener/Connector | ✅ Yes — decrypts/re-encrypts | Skupper/admin manages certs |
| **Passthrough** (app-managed) | Don't set `tlsCredentials` | ❌ No — opaque TCP | Application manages its own certs |

There is no explicit "passthrough mode" flag — it's simply the **absence** of Skupper-managed TLS configuration.

## TLS Credential Format

| Platform | Value is |
|----------|----------|
| Kubernetes | Name of a Secret in the current namespace |
| Docker/Podman/Linux | Name of a directory under `input/certs/` in the current namespace |
