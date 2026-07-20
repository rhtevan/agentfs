---
type: Reference
title: Individual Pod Services (exposePodsByName)
description: Expose each Kubernetes pod as a separately addressable service across the Skupper network
tags: [skupper, expose-pods-by-name, stateful, kubernetes, individual-pods]
timestamp: 2026-07-20T17:19:00-04:00
---

# Individual Pod Services

The `exposePodsByName` field on Listener (and AttachedConnectorBinding) creates **individual services for each pod** rather than load-balancing across them.

## Platform Support

**Kubernetes only** — pods don't exist on other platforms.

## How It Works

```yaml
apiVersion: skupper.io/v2alpha1
kind: Listener
metadata:
  name: redis
spec:
  routingKey: redis
  host: redis
  port: 6379
  exposePodsByName: true    # The key field
```

### What Gets Created

```
Without exposePodsByName:
  redis:6379 → load-balanced across all redis pods

With exposePodsByName:
  redis:6379          → still load-balanced (aggregate)
  redis-0:6379        → specifically redis-0
  redis-1:6379        → specifically redis-1
  redis-2:6379        → specifically redis-2
```

Each pod gets a dedicated service endpoint named after the pod, in addition to the aggregate service.

## Use Cases

| Workload | Why Individual Pod Services |
|----------|-----------------------------|  
| Redis Cluster | Reach specific master/replica nodes |
| Kafka | Connect to specific brokers |
| PostgreSQL (streaming replication) | Target primary vs replicas |
| Elasticsearch | Reach specific nodes |
| Any StatefulSet | Stateful workloads needing addressable instances |

## Available On

| Resource | Field |
|----------|-------|
| Listener | `spec.exposePodsByName` |
| AttachedConnectorBinding | `spec.exposePodsByName` |
