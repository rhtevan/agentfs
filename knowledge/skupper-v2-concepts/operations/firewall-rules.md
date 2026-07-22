---
type: Reference
title: Firewall Rules for Inter-Site Connections
description: When and what firewall rules are needed for Skupper V2 sites, including HTTP proxy tunneling
tags: [skupper, firewall, ports, proxy, connectivity, networking]
timestamp: 2026-07-22T19:03:00-04:00
---

# Firewall Rules for Inter-Site Connections

Skupper's core design principle is **no VPNs, no special firewall rules**. Links are established as outbound connections, so in most deployments you don't need to open any inbound ports.

## The Golden Rule

> **The site that creates the link needs only outbound connectivity. The site that accepts the link needs its router ports (55671/45671) reachable.**

## Link Direction and Firewalls

```
Site A (behind firewall)          Site B (public cloud)
┌──────────────────┐             ┌──────────────────┐
│  skupper-router ──┼────────────→│  skupper-router   │
│  (outbound only)  │  TLS conn   │  linkAccess:      │
│                   │             │    default         │
└──────────────────┘             └──────────────────┘
     No inbound needed            Must be reachable
```

Choose link direction based on which site has easier inbound accessibility.

## Decision Matrix

| Scenario | Firewall Rules Needed? |
|----------|:----------------------:|
| Site A links **out** to Site B (public cloud K8s) | ❌ None |
| Site A links **out** through a corporate proxy | ❌ None on firewall — configure proxy on Link |
| Site A (bare Linux) **accepts** inbound links | ✅ Open 55671 and/or 45671 inbound |
| Site A (K8s with LoadBalancer) accepts links | ✅ Cloud security group must allow inbound to LB |
| Site A (OpenShift with Route) accepts links | Usually ❌ — router typically allows 443 |
| Both sites behind firewalls | ⚠️ Use a relay site in the cloud |

## Ports to Open (When Accepting Links)

| Port | Protocol | Purpose |
|:----:|----------|--------|
| **55671** | TCP (AMQPS) | Inter-router links (interior ↔ interior) |
| **45671** | TCP (AMQPS) | Edge links (edge → interior) |

```bash
# Example: firewalld on Linux
sudo firewall-cmd --permanent --add-port=55671/tcp
sudo firewall-cmd --permanent --add-port=45671/tcp
sudo firewall-cmd --reload
```

## Kubernetes AccessType and Firewall

| `accessType` | What to Ensure |
|--------------|---------------|
| `loadbalancer` | Cloud security group allows inbound to LB on 55671/45671 |
| `route` (OpenShift) | Usually port 443 (TLS passthrough) — typically already open |
| `ingress` | Ingress controller must be reachable — typically 443 |
| `local` | No external access (cluster-internal only) |

## HTTP Proxy Tunneling

When your network requires routing through a corporate proxy, Skupper supports **HTTP CONNECT** tunneling:

```yaml
# Proxy Secret
apiVersion: v1
kind: Secret
metadata:
  name: my-proxy-config
type: kubernetes.io/basic-auth
stringData:
  host: proxy.example.com
  port: "3128"
  username: myuser       # Remove if no auth needed
  password: mypassword
```

```yaml
# Link with proxy
apiVersion: skupper.io/v2alpha1
kind: Link
metadata:
  name: link-to-remote-site
spec:
  endpoints:
    - host: remote-site.example.com
      name: inter-router
      port: "55671"
    - host: remote-site.example.com
      name: edge
      port: "45671"
  tlsCredentials: link-to-remote-site
  settings:
    proxy-configuration: my-proxy-config
```

Proxy must allow HTTP CONNECT to Skupper ports. Example Squid config:

```
acl skupper_ports port 55671 45671
http_access allow CONNECT skupper_ports
```

## Both Sites Behind Firewalls

Deploy a **relay site** in the cloud:

```
Site A (firewall) ──outbound──→ Cloud Relay ←──outbound── Site B (firewall)
                                (linkAccess: default)
```

Both sites link outbound to the relay. Traffic flows: Site A → Relay → Site B.
