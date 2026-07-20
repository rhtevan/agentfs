---
type: Reference
title: Skupper V2 Overview and Concept Model
description: Core concepts and architecture of Skupper V2 — sites, networks, services, and applications
tags: [skupper, v2, architecture, overview, concepts]
timestamp: 2026-07-20T17:19:00-04:00
---

# Skupper V2 Overview and Concept Model

Skupper is an open-source project that creates **Virtual Application Networks** (VANs) connecting services across Kubernetes clusters, Linux hosts, Docker, and Podman — without VPNs or firewall rules.

## Concept Groups

Skupper V2 organizes its model into four groups:

| Group | Concepts |
|-------|----------|
| **Sites** | Site, Workload, Platform |
| **Networks** | Network, Link, Access Token |
| **Services** | Listener, Connector, MultiKeyListener, Routing Key |
| **Applications** | Application, Component |

## Sites

| Concept | Description |
|---------|-------------|
| **Site** | A place where workloads run. Each site = one platform namespace. Multiple sites per platform possible. |
| **Workload** | A set of processes running on a platform (e.g., K8s Deployment, systemd service). |
| **Platform** | A system for running workloads: Kubernetes, Docker, Podman, or Linux (systemd). |

## Networks

| Concept | Description |
|---------|-------------|
| **Network** | A set of sites joined by links — the application network. |
| **Link** | A secure (mTLS) channel for communication between sites. Links are transport; app connections ride on top. |
| **Access Token** | A short-lived credential for securely creating links between sites. |

## Services

| Concept | Description |
|---------|-------------|
| **Listener** | Binds a local host:port to connectors in remote sites. Consumer-side proxy. |
| **Connector** | Binds a local workload to listeners in remote sites. Provider-side proxy. |
| **Routing Key** | String identifier matching listeners to connectors across the network. |
| **MultiKeyListener** | Single endpoint mapping to multiple routing keys with weighted or priority strategies. |

## Applications

| Concept | Description |
|---------|-------------|
| **Application** | A set of components working together — a distributed app. |
| **Component** | A logical part of an application, implemented by workloads in different locations. |

## Key V2 Changes from V1

| Aspect | V1 | V2 |
|--------|----|----|  
| Transport | Apache Qpid Dispatch Router (AMQP) | Custom routing fabric |
| Configuration | CLI-driven, annotations | CRD-based (YAML) + CLI + System YAML |
| Non-K8s support | Limited | First-class System CLI for Linux/Podman/Docker |
| Service model | `skupper expose` | Explicit Listener + Connector + Routing Key |
| Security | Token-based linking | Formalized AccessGrant/AccessToken resources |
