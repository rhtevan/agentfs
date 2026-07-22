---
type: Reference
title: Skupper V1 to V2 — Deprecated and Changed Concepts
description: Comprehensive list of V1 concepts removed, replaced, or significantly changed in V2
tags: [skupper, migration, v1, v2, deprecated, gateway, service-sync]
timestamp: 2026-07-22T19:03:00-04:00
---

# V1 to V2 — Deprecated and Changed Concepts

Skupper V1 sites are **not compatible** with V2 sites. There is no in-place migration — you must create a new network.

## Completely Removed

| V1 Concept | What It Was | V2 Replacement |
|------------|-------------|----------------|
| **Gateway** | Local gateway process for non-K8s workloads (`skupper gateway init/expose/bind`) | **System sites** — first-class Linux/Docker/Podman platform support via `skupper system` CLI |
| **Service Sync** | Services exposed on one site automatically propagated to all sites | **Explicit Listener + Connector** matched by routing key. No auto-sync. |
| **`skupper expose` / annotations** | Exposed services via CLI command or K8s annotations | **Connector resource** — explicit `skupper connector create` or Connector YAML |
| **Claim-based linking** | Alternative to token-based linking using a "claim" URL | **AccessGrant / AccessToken** — unified token-based approach with expiration and redemption limits |
| **Built-in Console** | Web console deployed as part of the Skupper controller (`skupper init --enable-console`) | **Network Observer** — separate Helm-deployed component |
| **Console auth flags** (`--console-auth`) | Auth modes: `internal`, `openshift`, `unsecured` at init time | Network Observer Helm values (`auth.strategy: basic/openshift/none`) |
| **Proxy/bridge services** | Skupper-managed proxy deployments in each namespace for traffic forwarding | V2 router handles forwarding directly — no separate proxy deployments |
| **`skupper service create/bind`** | Two-step: create virtual service, then bind to workload | Single **Connector** resource |

## Significantly Changed

| V1 | V2 | Change |
|----|----|---------|
| `skupper init` | `skupper site create` | Simpler. Console, service-sync config removed. |
| `skupper token create` | `skupper token issue` | Uses formal AccessGrant/AccessToken model |
| `skupper link create` | `skupper token redeem` | Redeems token, creates Link resource |
| `skupper status` | `skupper site/connector/listener/link status` | Granular per-resource status |
| CLI-only config | CRD-based YAML + CLI + System YAML | GitOps-friendly |
| Podman support (experimental) | First-class `skupper system` CLI | Same commands across Linux, Docker, Podman |
| Service name = routing identity | Routing Key decoupled from name | More flexible service naming |

## New in V2 (No V1 Equivalent)

| V2 Concept | Purpose |
|------------|--------|
| **Routing Key** | Decouples service identity from service name |
| **MultiKeyListener** | Weighted/priority distribution across multiple routing keys |
| **AttachedConnector/Binding** | Cross-namespace service exposure without deploying a router |
| **RouterAccess** | Dedicated resource for router network exposure (replaces `--ingress` flag) |
| **System YAML** | File-based config for non-K8s platforms |
| **Site Bundles** | Pre-packaged site configs deployable without CLI on target host |

## Gateway → System Site Migration Example

**V1:**
```bash
skupper gateway init
skupper gateway expose backend localhost 8080
```

**V2:**
```bash
export SKUPPER_PLATFORM=linux
skupper site create my-site
skupper connector create backend 8080 --host localhost
skupper token redeem ~/token.yaml
skupper system start
```

The key difference: V2 treats non-K8s environments as **full sites** with the same resource model as Kubernetes, not as second-class "gateways."
