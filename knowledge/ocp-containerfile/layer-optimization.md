# Layer Optimization

**Applies to:** Both legacy and user namespace modes

## Layer Count Limit

Red Hat container certification enforces `LayerCountAcceptable`:
images must have **fewer than 40 layers**. Each `FROM`, `RUN`,
`COPY`, and `ADD` instruction creates a layer.

## Multi-Stage Builds

Separate build-time dependencies from runtime to minimize image
size and attack surface.

```dockerfile
# Build stage — large, has compilers
FROM registry.access.redhat.com/ubi9/go-toolset:latest AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o server .

# Runtime stage — minimal
FROM registry.access.redhat.com/ubi9/ubi-micro:latest
COPY --from=builder --chown=1001:0 /app/server /server
COPY --chown=1001:0 LICENSE /licenses/LICENSE
USER 1001
EXPOSE 8080
ENTRYPOINT ["/server"]
```

Benefits:
- Build tools (compilers, headers, test frameworks) stay out of the
  final image
- Smaller image = faster pulls, smaller attack surface
- Separate cache invalidation — source code changes don't rebuild
  dependency layer

## Cache-Friendly Ordering

Place instructions that change **infrequently** early and
instructions that change **frequently** late:

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# 1. System packages — rarely change
RUN microdnf install -y nodejs npm && microdnf clean all

# 2. Dependencies — change when package.json changes
COPY package.json package-lock.json ./
RUN npm ci --production

# 3. Application code — changes every commit
COPY --chown=1001:0 src/ ./src/

USER 1001
EXPOSE 8080
CMD ["node", "src/index.js"]
```

If `src/` changes but `package.json` doesn't, layers 1–2 are cached.

## Package Cache Cleanup

Package manager caches persist in the layer where they were created.
**Clean in the same `RUN` instruction** as the install:

### Correct

```dockerfile
# ✅ Install and clean in the same layer
RUN microdnf install -y \
      python3 python3-pip \
      shadow-utils && \
    microdnf clean all && \
    rm -rf /var/cache/yum /var/cache/dnf
```

### Incorrect

```dockerfile
# ❌ Cache persists in the first layer — second RUN doesn't help
RUN microdnf install -y python3 python3-pip
RUN microdnf clean all
```

## Consolidate RUN Instructions

Chain related operations to reduce layer count:

```dockerfile
# ✅ Single layer for all setup
RUN microdnf install -y nodejs npm && \
    microdnf clean all && \
    mkdir -p /app/data /app/logs && \
    chgrp -R 0 /app/data /app/logs && \
    chmod -R g=u /app/data /app/logs

# ❌ Four layers for the same operations
RUN microdnf install -y nodejs npm
RUN microdnf clean all
RUN mkdir -p /app/data /app/logs
RUN chgrp -R 0 /app/data /app/logs && chmod -R g=u /app/data /app/logs
```

## Don't Install Unnecessary Packages

```dockerfile
# ✅ --nodocs skips man pages and documentation
RUN dnf install --nodocs -y httpd && dnf clean all

# ✅ --no-install-recommends equivalent for microdnf
RUN microdnf install -y --nodocs python3 && microdnf clean all
```

## .containerignore / .dockerignore

Prevent build context bloat by excluding unnecessary files:

```
# .containerignore
.git
node_modules
*.md
tests/
docs/
.env
```

## COPY vs ADD

- Use `COPY` for local files — it's explicit and predictable.
- Use `ADD` only for auto-extracting tarballs or fetching URLs
  (though `curl` in a `RUN` is preferred for URLs).

## Gotchas

- **Layer count includes base image layers** — if the base image has
  30 layers, you only have ~9 left before hitting the 40 limit.
  Check with `podman inspect <image> | jq '.[0].RootFS.Layers | length'`.
- **Squashing** — `podman build --squash` merges all layers into one
  but destroys cache. Use only for final production builds.
- **Multi-stage COPY creates a layer** — each `COPY --from=builder`
  is a layer in the final image. Minimize by combining files into
  a single directory in the build stage.

## Sources

- [Red Hat Certification Troubleshooting: LayerCountAcceptable](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/containers/troubleshooting.md)
- [Docker Docs: Building best practices](https://docs.docker.com/build/building/best-practices/)
