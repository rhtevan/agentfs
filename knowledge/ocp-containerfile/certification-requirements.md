# Red Hat Certification Requirements

**Applies to:** Both legacy and user namespace modes

## Overview

Red Hat container certification validates images against a set of
automated tests before publishing to the Red Hat Ecosystem Catalog.
Images must score grade A–C in vulnerability scanning.

## Certification Tests Checklist

| Test | What It Checks | How to Pass |
|------|---------------|-------------|
| **RunAsNonRoot** | `USER` is declared and is not `root`, `0`, or absent | Add `USER 1001` (numeric, non-zero) |
| **BasedOnUBI** | Base image is UBI or RHEL | `FROM registry.access.redhat.com/ubi9/ubi-minimal:latest` |
| **HasModifiedFiles** | No RPM-installed files in the base layer are modified | Don't overwrite files from the base image; copy to new paths instead |
| **HasLicense** | `/licenses/` directory exists at root with ≥1 license file | `COPY LICENSE /licenses/LICENSE` |
| **HasUniqueTag** | Registry has ≥1 tag other than `latest` | Tag with semver: `myapp:1.2.3` |
| **LayerCountAcceptable** | Image has <40 layers | Consolidate RUN instructions; use multi-stage builds |
| **HasNoProhibitedPackages** | No RHEL kernel packages or other prohibited packages | Don't install kernel, kernel-core, etc. |
| **HasRequiredLabel** | Six mandatory labels present | See [Image Metadata and Labels](image-metadata-labels.md) |
| **VulnerabilityScanner** | Clair scan grade A–C | `RUN microdnf upgrade -y && microdnf clean all` after FROM |

## Certification-Ready Containerfile Template

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Pick up security patches
RUN microdnf upgrade -y && microdnf clean all

# Required labels for certification
LABEL name="mycompany/myapp" \
      vendor="My Company, Inc." \
      version="1.0.0" \
      release="1" \
      summary="My Application" \
      description="My Application does X, Y, Z"

# Install application dependencies
RUN microdnf install -y nodejs npm && \
    microdnf clean all && \
    rm -rf /var/cache/yum

# License directory — required for certification
RUN mkdir -p /licenses
COPY LICENSE /licenses/LICENSE

# Application files
COPY --chown=1001:0 app /app
WORKDIR /app
RUN npm ci --production

# Writable directories (legacy GID 0 pattern)
RUN chgrp -R 0 /app/data && chmod -R g=u /app/data

# Non-root user — required
USER 1001

# Non-privileged port
EXPOSE 8080

ENTRYPOINT ["node", "server.js"]
```

## Infrastructure Partners (Privileged Images)

If the image genuinely requires root privileges (node agent, device
plugin, CNI), navigate to the certification project Settings tab
and select **Privileged** under Host level access. This omits the
`RunAsNonRoot` test but is subject to Red Hat review.

## Vulnerability Mitigation Between UBI Releases

There can be a lag between CVE disclosure and UBI rebuild. Mitigate
by upgrading packages in the Containerfile:

| Base Image | Command |
|-----------|---------|
| UBI standard | `RUN dnf upgrade -y && dnf clean all` |
| UBI minimal | `RUN microdnf upgrade -y && microdnf clean all` |
| UBI micro | Rebuild from latest base image (no package manager) |

## Preflight Tool

Run certification checks locally before submitting:

```bash
preflight check container \
  quay.io/redhat-isv-containers/<project-id>:<tag> \
  --docker-config=/path/to/dockerconfig.json
```

For submission:

```bash
preflight check container \
  quay.io/redhat-isv-containers/<project-id>:<tag> \
  --submit \
  --pyxis-api-token=<token> \
  --certification-component-id=<component-id> \
  --docker-config=/path/to/dockerconfig.json
```

## Gotchas

- **HasModifiedFiles** catches config file overwrites in the base
  layer. If you need to modify an RPM-owned config file, copy it
  to a new location and configure the app to read from there.
- **HasUniqueTag** fails if your registry doesn't expose the
  `/tags/list` endpoint.
- **VulnerabilityScanner** runs **after** submission, not during
  `preflight`. An image that passes preflight locally can still
  fail on grade.
- **Infrastructure partner** flag must be set **before** running
  preflight — it changes which tests are executed.

## Sources

- [Red Hat Certification Troubleshooting](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/containers/troubleshooting.md)
- [Red Hat Partner Connect: Container Certification Policy Guide](https://connect.redhat.com/en/partner-resources/container-certification-policy-guide)
