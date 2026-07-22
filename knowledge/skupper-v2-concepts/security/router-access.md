---
type: Reference
title: RouterAccess — Router Network Exposure
description: How RouterAccess controls the external accessibility of the Skupper router, including ports, mTLS enforcement, and access types
tags: [skupper, router-access, linking, ingress, tls, mtls, ports]
timestamp: 2026-07-22T15:39:00-04:00
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

## Inter-Site Link Ports

Two port roles define how sites connect:

| Role | Default Port | Purpose | Used By |
|------|:------------:|---------|--------|
| `inter-router` | **55671** | Links between interior routers | Interior ↔ Interior |
| `edge` | **45671** | Links from edge routers to interior routers | Edge → Interior |

### Which Port Gets Used

| Link Direction | Port | Possible? |
|---------------|:-----:|:---------:|
| Interior → Interior | 55671 | ✅ |
| Interior ← Interior | 55671 | ✅ |
| Edge → Interior | 45671 | ✅ |
| Edge → Edge | — | ❌ Edges can't accept links |
| Interior → Edge | — | ❌ Edges can't accept links |

Ports are **configurable** on the RouterAccess resource — they are not hardcoded. However, the linking site doesn't need to know the port in advance: the **AccessGrant/Token** flow carries the connection endpoint (host + port) automatically.

### Protocol

Both ports carry **AMQPS** (AMQP over TLS) — the Skupper router's inter-router protocol. These are not HTTP ports. All communication is always encrypted with mutual TLS.

## Inter-Router mTLS — Always On

Inter-router mTLS is **enabled by default and cannot be disabled**. This is a deliberate security design decision.

### Why It's Mandatory

- `tlsCredentials` is a **required** field on RouterAccess — there is no way to omit it
- The AccessGrant/Token workflow **structurally enforces** mTLS: the token receives a signed certificate, and the resulting link uses it for mutual authentication
- Skupper connects services across **untrusted network boundaries** (public internet, cloud interconnects) — plaintext would undermine the core security promise

### What You CAN Customize

While mTLS cannot be disabled, the **certificate infrastructure** is fully customizable:

```yaml
# Use your own CA
apiVersion: skupper.io/v2alpha1
kind: Site
metadata:
  name: my-site
spec:
  defaultIssuer: my-corporate-ca    # Your own CA secret

---
# Use your own certs for RouterAccess
apiVersion: skupper.io/v2alpha1
kind: RouterAccess
metadata:
  name: skupper-router
spec:
  roles:
    - name: inter-router
      port: 55671
  tlsCredentials: my-custom-certs           # Your own cert bundle
  generateTlsCredentials: false             # Don't auto-generate
  subjectAlternativeNames:
    - router.example.com                    # Custom SANs
```

### mTLS Summary

| Question | Answer |
|----------|--------|
| Enabled by default? | **Yes — always** |
| Can you disable it? | **No** |
| Can you use your own certificates? | **Yes** — via `tlsCredentials` and `defaultIssuer` |
| Can you use plaintext inter-router links? | **No** — `tlsCredentials` is required |
