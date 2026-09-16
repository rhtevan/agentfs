# Image Metadata and Labels

**Applies to:** Both legacy and user namespace modes

## Required Labels (Certification)

Red Hat container certification tests for six mandatory labels via
the `HasRequiredLabel` check. All six must be present in the
Containerfile:

| Label | Purpose | Example |
|-------|---------|---------|
| `name` | Image name (human-readable) | `mycompany/myapp` |
| `vendor` | Company name | `My Company, Inc.` |
| `version` | Image version | `1.2.3` |
| `release` | Build release number | `1` |
| `summary` | Short description (≤80 chars) | `My Application Server` |
| `description` | Long description | `My Application Server provides...` |

### Example

```dockerfile
LABEL name="mycompany/myapp" \
      vendor="My Company, Inc." \
      version="1.2.3" \
      release="1" \
      summary="My Application Server" \
      description="My Application Server provides a REST API for..." \
      maintainer="team@mycompany.com"
```

Use a single `LABEL` instruction to avoid creating extra layers.

## OpenShift-Specific Labels

These labels enable integration with the OpenShift console, catalog,
and generation tools:

| Label | Type | Purpose | Example |
|-------|------|---------|---------|
| `io.openshift.tags` | comma-separated strings | Categories for catalog/discovery | `nodejs,web,api` |
| `io.openshift.wants` | comma-separated strings | Dependency hints — UI suggests adding these | `mongodb,redis` |
| `io.openshift.expose-services` | `PORT[/PROTO]:NAME` list | Describe what services the ports provide | `8080:http,8443:https` |
| `io.openshift.non-scalable` | boolean | Image doesn't support replicas > 1 | `true` |
| `io.openshift.min-memory` | K8s quantity | Minimum memory hint | `512Mi` |
| `io.openshift.min-cpu` | K8s quantity | Minimum CPU hint | `500m` |

## Kubernetes Labels

| Label | Purpose | Example |
|-------|---------|---------|
| `io.k8s.display-name` | Human-readable name for UI | `My App 1.2` |
| `io.k8s.description` | Description for K8s tools | `REST API server for...` |

## OCI Standard Labels

These follow the OCI image spec (`org.opencontainers.image.*`):

| Label | Purpose |
|-------|---------|
| `org.opencontainers.image.title` | Human-readable title |
| `org.opencontainers.image.description` | Description |
| `org.opencontainers.image.version` | Version |
| `org.opencontainers.image.vendor` | Vendor |
| `org.opencontainers.image.url` | Project URL |
| `org.opencontainers.image.source` | Source code URL |
| `org.opencontainers.image.licenses` | SPDX license expression |
| `org.opencontainers.image.created` | Build timestamp (RFC 3339) |

## Complete Label Block Example

```dockerfile
LABEL name="mycompany/myapp" \
      vendor="My Company, Inc." \
      version="1.2.3" \
      release="1" \
      summary="REST API server for widget management" \
      description="Provides CRUD operations for widget resources with PostgreSQL backend" \
      maintainer="platform-team@mycompany.com" \
      # OpenShift integration
      io.openshift.tags="api,rest,nodejs" \
      io.openshift.wants="postgresql" \
      io.openshift.expose-services="8080:http" \
      # Kubernetes
      io.k8s.display-name="Widget API Server" \
      io.k8s.description="REST API server for widget management" \
      # OCI
      org.opencontainers.image.title="Widget API Server" \
      org.opencontainers.image.version="1.2.3" \
      org.opencontainers.image.vendor="My Company, Inc." \
      org.opencontainers.image.source="https://github.com/mycompany/myapp" \
      org.opencontainers.image.licenses="Apache-2.0"
```

## S2I Labels

Only needed if the image is a Source-to-Image builder image.
See [S2I Compatibility](s2i-compatibility.md) for details.

| Label | Purpose |
|-------|---------|
| `io.openshift.s2i.scripts-url` | URL/path to assemble/run scripts |
| `io.openshift.s2i.destination` | Working directory for S2I (default `/tmp`) |

## Gotchas

- **Certification rejects missing labels** — the `HasRequiredLabel`
  test checks all six mandatory labels. Missing any one fails the
  entire test.
- **Use a single LABEL instruction** — each `LABEL` line creates a
  layer. Combine into one instruction with line continuations.
- **ARG for version** — use build args for dynamic values:
  ```dockerfile
  ARG VERSION=1.0.0
  LABEL version="${VERSION}" release="${RELEASE:-1}"
  ```
- **Don't duplicate in ENV** — labels are metadata, not runtime
  environment. Use `LABEL` not `ENV` for image metadata.

## Sources

- [OpenShift Origin: Image Metadata Proposal](https://github.com/openshift/origin/blob/main/docs/proposals/metadata.md)
- [Red Hat Certification Troubleshooting: HasRequiredLabel](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/containers/troubleshooting.md)
- [OCI Image Spec: Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
