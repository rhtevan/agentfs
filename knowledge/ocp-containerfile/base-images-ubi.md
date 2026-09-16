# Base Images — UBI Selection

**Applies to:** Both legacy and user namespace modes

## What Is UBI

Red Hat Universal Base Images (UBI) are freely redistributable
container base images built from RHEL content. They are the
**required** base for Red Hat container certification — other
distros (Alpine, Debian, scratch) fail the `BasedOnUBI` test.

## UBI Variants

| Variant | Image | Size | Package Manager | Use Case |
|---------|-------|:----:|:---------------:|----------|
| **Standard** | `ubi9/ubi` | ~208 MB | `dnf` | General purpose, full tooling |
| **Minimal** | `ubi9/ubi-minimal` | ~102 MB | `microdnf` | Production apps, smaller footprint |
| **Micro** | `ubi9/ubi-micro` | ~23 MB | None | Statically linked binaries, distroless-like |
| **Init** | `ubi9/ubi-init` | ~228 MB | `dnf` + `systemd` | Multi-service containers, systemd workloads |

## Registries

| Registry | Auth Required | URL Pattern |
|----------|:------------:|-------------|
| **Red Hat Container Catalog** | Yes (RHSM) | `registry.redhat.io/ubi9/ubi-minimal:latest` |
| **Red Hat Public** | No | `registry.access.redhat.com/ubi9/ubi-minimal:latest` |

Use `registry.access.redhat.com` for builds that don't have RHSM
credentials (CI/CD pipelines, public builds). Use `registry.redhat.io`
when subscriptions are available (access to entitled RHEL repos).

## Selection Criteria

| If your app... | Use |
|----------------|-----|
| Is a statically compiled Go/Rust binary | `ubi9/ubi-micro` — smallest, no shell needed |
| Needs runtime packages (Python, Node, Java) | `ubi9/ubi-minimal` — `microdnf` for package installation |
| Needs many RHEL packages or build tools | `ubi9/ubi` — full `dnf` |
| Runs multiple processes via systemd | `ubi9/ubi-init` — systemd as PID 1 |

## Language-Specific Base Images

Red Hat provides pre-built language runtime images on UBI:

| Language | Image | Notes |
|----------|-------|-------|
| Python 3.12 | `ubi9/python-312` | Includes pip, virtualenv |
| Node.js 22 | `ubi9/nodejs-22` | Includes npm |
| Go 1.22 (builder) | `ubi9/go-toolset` | Build stage only |
| Java 21 (runtime) | `ubi9/openjdk-21-runtime` | JRE only |
| .NET 8 | `ubi9/dotnet-80-runtime` | Runtime only |

These are available from `registry.access.redhat.com` and
`registry.redhat.io`.

## Multi-Stage Build Pattern

Use a larger image for building, smaller for runtime:

```dockerfile
# Build stage — full tooling
FROM registry.access.redhat.com/ubi9/go-toolset:latest AS builder
COPY . /app
WORKDIR /app
RUN go build -o /app/server .

# Runtime stage — minimal
FROM registry.access.redhat.com/ubi9/ubi-micro:latest
COPY --from=builder --chown=1001:0 /app/server /server
COPY --chown=1001:0 LICENSE /licenses/LICENSE
USER 1001
EXPOSE 8080
ENTRYPOINT ["/server"]
```

## Package Installation Patterns

### ubi-minimal (microdnf)

```dockerfile
RUN microdnf install -y \
      nodejs npm \
      shadow-utils && \
    microdnf clean all && \
    rm -rf /var/cache/yum
```

### ubi (dnf)

```dockerfile
RUN dnf install -y \
      python3 python3-pip && \
    dnf clean all && \
    rm -rf /var/cache/dnf
```

### ubi-micro (no package manager)

Cannot install packages. Use multi-stage build to copy binaries in:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest AS deps
RUN microdnf install -y libpq && microdnf clean all

FROM registry.access.redhat.com/ubi9/ubi-micro:latest
COPY --from=deps /usr/lib64/libpq* /usr/lib64/
COPY --chown=1001:0 myapp /app/myapp
USER 1001
ENTRYPOINT ["/app/myapp"]
```

## Vulnerability Mitigation

Certification requires image grades A–C from the Clair scanner.
Add upgrade step after `FROM` to pick up latest security patches:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Pick up security patches between UBI releases
RUN microdnf upgrade -y && microdnf clean all
```

For `ubi-micro`, rebuilding from the latest base image is the
only mitigation path.

## Gotchas

- **Disconnected environments**: `microdnf`/`dnf` will fail without
  network access. Configure mirror/proxy repos or use multi-stage
  builds where the build stage has network access.
- **Entitled content**: Some RHEL packages require a subscription.
  On RHEL hosts with active subscriptions, the entitlement is
  passed to the build container automatically. On non-RHEL build
  hosts, only UBI-repo packages are available.
- **Image pinning**: Use digest-based pinning for reproducible
  builds: `FROM registry.access.redhat.com/ubi9/ubi-minimal@sha256:abc...`

## Sources

- [Red Hat Ecosystem Catalog: Base Images](https://catalog.redhat.com/en/software/base-images)
- [Red Hat Certification Troubleshooting: BasedOnUBI](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/containers/troubleshooting.md)
