---
type: Reference
title: Skupper Network Console (Network Observer)
description: Web-based observability UI for visualizing Skupper network topology, services, and traffic flow
tags: [skupper, console, observability, monitoring, prometheus, helm]
timestamp: 2026-07-20T17:19:00-04:00
---

# Network Console (Network Observer)

The Network Console is a web-based observability UI deployed separately via Helm. It collects flow data from the Skupper router and provides visualizations.

## Architecture

```
┌─────────────────────────────────────┐
│  Network Observer Pod               │
│                                      │
│  ┌──────────────┐  ┌─────────────┐  │
│  │ Observer      │  │ Prometheus   │  │
│  │ (flow data)   │  │ (metrics)    │  │
│  └──────┬───────┘  └─────────────┘  │
│         │                            │
│  ┌──────┴───────┐                   │
│  │ Web Console   │                   │
│  └──────────────┘                   │
└─────────────────────────────────────┘
         │
    AMQPS → skupper-router
```

## Installation

```bash
helm install skupper-network-observer \
  oci://quay.io/skupper/helm/network-observer \
  --version 2.2.1
```

## Access

```bash
# Port forward
kubectl port-forward svc/skupper-network-observer 8443:443

# Get password (default user: skupper)
kubectl get secret skupper-network-observer-users \
  -o jsonpath='{.data.password}' | base64 -d
```

## What It Shows

| View | Content |
|------|---------|
| Topology | Visual map of sites and links |
| Services | Services exposed on the network |
| Sites | Site status and health |
| Components | Application components |
| Processes | Running workloads |

## Site Selection for Deployment

Consider:
- **Firewall position** — deploy inside/outside based on access needs
- **Traffic proximity** — deploy near the site with most traffic
- **Resource cost** — deploy where resources are cheapest

## Authentication Options

| Strategy | Platform | Details |
|----------|----------|---------|
| `basic` | Any K8s | Auto-generated username/password |
| `openshift` | OpenShift | OAuth integration |
| `none` | Any | No auth (development only) |

## Key Helm Configuration

| Category | Options |
|----------|--------|
| External access | Ingress (nginx, generic), OpenShift Route |
| TLS | Skupper-issued, OpenShift Service CA, or external |
| Persistence | PVC for Prometheus time-series data |
| Metrics | Dedicated metrics endpoint on port 9000 |
| Resources | CPU/memory limits for observer, prometheus, proxy containers |

## OpenShift Route Example

```yaml
route:
  enabled: true
  subdomain: network-observer
auth:
  strategy: openshift
  openshift:
    createCookieSecret: true
    serviceAccount:
      create: true
tls:
  openshiftIssued: true
```

## Uninstall

```bash
helm uninstall skupper-network-observer
# PVCs not auto-deleted:
kubectl delete pvc skupper-network-observer-prometheus
```
