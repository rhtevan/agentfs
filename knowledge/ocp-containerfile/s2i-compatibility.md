# S2I Compatibility

**Applies to:** Only when building Source-to-Image (S2I) builder images

## What Is S2I

Source-to-Image (S2I) is an OpenShift build strategy that produces
ready-to-run images by injecting application source code into a
builder image. The builder image provides the runtime environment
and scripts to compile/prepare the source.

S2I is an **optional** pattern. Most modern applications use
standard Containerfile builds or Tekton pipelines. S2I is relevant
when building platform-managed builder images that accept source
from developers.

## Required Labels

| Label | Purpose | Example |
|-------|---------|---------|
| `io.openshift.s2i.scripts-url` | Location of assemble/run/save-artifacts scripts | `image:///usr/libexec/s2i` |
| `io.openshift.s2i.destination` | Working directory for S2I operations | `/tmp` (default) |
| `io.openshift.s2i.assemble-user` | UID to run the assemble script as | `1001` |

## Required Scripts

| Script | Purpose | Required? |
|--------|---------|:---------:|
| `assemble` | Build the application from source | ✅ Yes |
| `run` | Start the application | ✅ Yes |
| `save-artifacts` | Save build artifacts for incremental builds | Optional |
| `usage` | Print usage instructions | Optional |

## S2I Builder Image Example

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

LABEL name="mycompany/nodejs-builder" \
      vendor="My Company" \
      version="1.0.0" \
      release="1" \
      summary="Node.js S2I Builder" \
      description="S2I builder for Node.js applications" \
      io.openshift.tags="builder,nodejs" \
      io.openshift.s2i.scripts-url="image:///usr/libexec/s2i" \
      io.k8s.display-name="Node.js Builder" \
      io.k8s.description="S2I builder for Node.js applications"

RUN microdnf install -y nodejs npm && \
    microdnf clean all

# S2I scripts
COPY s2i/bin/ /usr/libexec/s2i/

# Source destination
RUN mkdir -p /opt/app-root/src && \
    chgrp -R 0 /opt/app-root && \
    chmod -R g=u /opt/app-root

# License
COPY LICENSE /licenses/LICENSE

USER 1001
WORKDIR /opt/app-root/src
EXPOSE 8080

CMD ["/usr/libexec/s2i/usage"]
```

### assemble script

```bash
#!/bin/bash
# /usr/libexec/s2i/assemble
set -e

echo "---> Installing application source..."
cp -Rf /tmp/src/. ./

if [ -f package.json ]; then
    echo "---> Installing dependencies..."
    npm ci --production
fi
```

### run script

```bash
#!/bin/bash
# /usr/libexec/s2i/run
exec node ${APP_SCRIPT:-server.js}
```

## S2I Script Lookup Order

When building, S2I checks for scripts in this order:
1. Scripts specified in the `BuildConfig` `scripts` field
2. Scripts in the application source `.s2i/bin/` directory
3. Scripts at the URL specified by `io.openshift.s2i.scripts-url`
4. Scripts at the default `/usr/libexec/s2i/` path

## Gotchas

- **Script permissions**: S2I scripts must be executable
  (`chmod +x`). The `COPY` instruction preserves permissions from
  the source filesystem.
- **Assemble runs as the image USER**: The assemble script runs as
  the UID specified in the Containerfile `USER` directive (or
  `io.openshift.s2i.assemble-user`). All source directories must
  be writable by this user.
- **Incremental builds**: `save-artifacts` must write to stdout as
  a tar stream. The artifacts are injected into the next build at
  the destination path.

## Sources

- [OpenShift S2I: Builder Image Requirements](https://github.com/openshift/source-to-image/blob/master/docs/builder_image.md)
- [OCP 3.11: S2I Requirements](https://docs.redhat.com/en/documentation/openshift_container_platform/3.11/html/creating_images/creating-images-s2i)
