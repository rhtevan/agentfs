---
type: Reference
title: RouterAccess — Router Network Exposure
description: How RouterAccess controls the external accessibility of the Skupper router for incoming links
tags: [skupper, router-access, linking, ingress, tls]
timestamp: 2026-07-20T17:19:00-04:00
---

# RouterAccess

RouterAccess is the lower-level resource that controls how the Skupper router is made accessible for incoming links. When you set `linkAccess` on a Site, it creates a RouterAccess under the hood.

## What It Controls

```
External Network
       │
       ▼
┌─────────────────────────────┐
│  RouterAccess                │
│  (LoadBalancer / Route /     │
│   Ingress / ClusterIP)       │
│                              │
│  Roles:                      │
│   - inter-router (port 55671)│
│   - edge (port 45671)        │
│                              │
│  TLS: mutual TLS certs       │
└──────────┬──────────────────┘
           ▼
    skupper-router
```

## Resource Example

```yaml
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: skupper-router
spec:
  roles:
    - name: inter-router     # For links from interior sites
      port: 55671
    - name: edge             # For links from edge sites
      port: 45671
  accessType: loadbalancer
  generateTlsCredentials: true
  tlsCredentials: skupper-site-server
```

## Key Fields

| Field | Description |
|-------|-------------|
| `roles` | Array of named interfaces: `inter-router` and `edge` |
| `accessType` | How to expose externally |
| `tlsCredentials` | TLS cert bundle for mTLS router-to-router communication |
| `generateTlsCredentials` | Let Skupper auto-generate certs |
| `bindHost` | Network interface to bind to (default `0.0.0.0`) |
| `subjectAlternativeNames` | Hostnames/IPs for the TLS certificate |

## accessType Options

| Value | What It Creates | Platform |
|-------|----------------|----------|
| `route` | OpenShift Route | OpenShift only |
| `loadbalancer` | K8s Service type LoadBalancer | Any K8s |
| `ingress` | K8s Ingress (generic) | Any K8s with Ingress controller |
| `ingress-nginx` | K8s Ingress with NGINX annotations | NGINX Ingress Controller |
| `local` | K8s Service type ClusterIP | Any K8s (no external access) |

## Relationship to Site linkAccess

| Site `linkAccess` | RouterAccess Created? | accessType |
|-------------------|:---------------------:|------------|
| `none` | ❌ No | — |
| `default` | ✅ Yes | Platform default |
| `route` | ✅ Yes | `route` |
| `loadbalancer` | ✅ Yes | `loadbalancer` |

You can also create RouterAccess resources **directly** for more fine-grained control than Site `linkAccess` provides — for example, to use `ingress-nginx` or `local` access types.
