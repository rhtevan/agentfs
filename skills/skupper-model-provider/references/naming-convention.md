# Skupper VAN Naming Convention

Consistent naming rules for all Skupper resources across the VAN.

## Foundation

Site names are the base identity. All other resource names derive from
site names and/or routing keys.

## Convention Table

| Component | Convention | Scope | Examples |
|-----------|-----------|-------|---------|
| **Site** | `{identity}` | Unique per VAN | `local-ezhang`, `rhel-ai`, `rhtevan-work`, `crc-ezhang` |
| **Routing Key** | `{service-type}-{provider-site}` | Unique per VAN | `model-api-rhel-ai`, `decision-api-rhel-ai` |
| **Link** | `link-{source-site}-{dest-site}` | Unique per VAN | `link-local-ezhang-rhel-ai`, `link-crc-ezhang-rhel-ai` |
| **Connector** | `connector-{routing-key}` | Unique per site | `connector-model-api-rhel-ai`, `connector-decision-api-rhel-ai` |
| **Listener** | `listener-{routing-key}` | Unique per site | `listener-model-api-rhel-ai`, `listener-model-api-rhtevan-work` |
| **RouterAccess** | `ra-{site-name}` | Unique per site | `ra-rhel-ai`, `ra-rhtevan-work`, `ra-local-ezhang` |
| **Secret** (auto) | Follows parent resource name | Unique per site | `link-local-ezhang-rhel-ai`, `ra-rhel-ai` |

## Naming Rules

1. **Site names are the atomic identity** — all other names compose
   from them.

2. **Routing keys are the service identity** — format
   `{service-type}-{provider-site}` ensures VAN-wide uniqueness.
   Current service types: `model-api`, `decision-api`.

3. **Connectors and Listeners share the routing key as their suffix**
   — prefixed with `connector-` or `listener-` for resource type
   clarity. A connector and its matching listeners across sites share
   the same routing key suffix.

4. **Links encode directionality** — `link-{source}-{dest}` where
   source initiates the connection.

5. **RouterAccess is one per site** — name `ra-{site-name}`. Multiple
   only when different TLS credentials are needed per port; in that
   case use `ra-{site-name}-{qualifier}`.

6. **Secrets inherit parent names** — `tlsCredentials` on Link and
   RouterAccess references the secret name, which matches the parent
   resource name.

## K8s Listener `spec.host` Rule

On Kubernetes (CRC), the Listener `spec.host` field becomes the
**Service name and DNS hostname**. Set `spec.host` equal to
`metadata.name` to keep them aligned:

```yaml
metadata:
  name: listener-model-api-rhel-ai        # resource name
spec:
  host: listener-model-api-rhel-ai        # becomes K8s Service DNS
  routingKey: model-api-rhel-ai
  port: 9000
```

Resulting DNS: `listener-model-api-rhel-ai.{namespace}.svc`

On Podman, `spec.host` is the bind address (`0.0.0.0`) — independent
of the listener name.

## Component Placement

| Component | Where it lives | Which sites |
|-----------|---------------|-------------|
| Site | Every site | All 4 |
| Routing Key | Implicit — defined in Connector and Listener specs | — |
| Link | Consumer/relay sites (outbound) | `local-ezhang`, `crc-ezhang` |
| Connector | Provider sites (where workloads run) | `rhel-ai`, `rhtevan-work` |
| Listener | Consumer sites (where clients connect) | `local-ezhang`, `crc-ezhang` |
| RouterAccess | Sites accepting inbound links (interior only) | `rhel-ai`, `rhtevan-work`, `local-ezhang` |

## RouterAccess Guidelines

- RouterAccess applies to **interior routers that accept inbound
  links** only. Edge routers cannot accept inbound links.
- One RouterAccess per site is the norm. A single RouterAccess can
  expose multiple roles/ports (e.g. `inter-router` + `edge`).
- Multiple RouterAccess resources per site are valid **only** when
  different TLS credentials are needed per port (e.g. internal CA
  for LAN, public CA for WAN). Each must use a **different port**.
- Two RouterAccess resources on the same port is redundant — the
  router creates duplicate listeners with different sslProfiles.
- Consumer-only sites (e.g. CRC with `linkAccess: none`) do not
  need RouterAccess — they only create outbound links.

## Current → Proposed Rename Map

### Connectors (provider sites)

| Site | Current | Proposed |
|------|---------|----------|
| rhel-ai | `model-connector` | `connector-model-api-rhel-ai` |
| rhel-ai | `decision-connector` | `connector-decision-api-rhel-ai` |
| rhtevan-work | `model-connector` | `connector-model-api-rhtevan-work` |

### Listeners (localhost — podman)

| Current | Proposed |
|---------|----------|
| `model-rhel-ai` | `listener-model-api-rhel-ai` |
| `model-rhtevan-work` | `listener-model-api-rhtevan-work` |
| `decision-rhel-ai` | `listener-decision-api-rhel-ai` |

### Listeners (CRC — K8s)

| Current | Proposed | K8s Service DNS change |
|---------|----------|----------------------|
| `model-listener-rhel-ai` | `listener-model-api-rhel-ai` | `model-listener-rhel-ai.model-provider-crc` → `listener-model-api-rhel-ai.model-provider-crc` |
| `model-listener-rhtevan-work` | `listener-model-api-rhtevan-work` | `model-listener-rhtevan-work.model-provider-crc` → `listener-model-api-rhtevan-work.model-provider-crc` |
| *(missing)* | `listener-decision-api-rhel-ai` | New |

### RouterAccess

| Site | Current | Proposed | Notes |
|------|---------|----------|-------|
| localhost | `local-ezhang-ra` | `ra-local-ezhang` | Prefix flip |
| rhel-ai | `rhel-ai` + `rhel-ai-public` | `ra-rhel-ai` | Consolidate two → one |
| rhtevan-work | `rhtevan-work` | `ra-rhtevan-work` | Add prefix |

### Links — no changes

Already follow `link-{source-site}-{dest-site}`.

### Sites — no changes

Already the base identity.

## Downstream Impact

| Rename | Downstream updates required |
|--------|---------------------------|
| CRC Listeners | OLS provider URLs: update `url` field in OLSConfig CR |
| RouterAccess | Link `tlsCredentials` references; cert directory/Secret names |
| Connectors | None — name is cosmetic on podman |
| Localhost Listeners | None — bind address is `0.0.0.0`, name is cosmetic |

## Execution Recommendation

- **Connectors + Localhost Listeners**: Low risk — delete + recreate
- **CRC Listeners**: Coordinate with OLS URL update (use `crc-ols` skill)
- **RouterAccess**: Most disruptive — requires cert regeneration and
  link rebuild; best done during a full `setup.sh` rebuild
