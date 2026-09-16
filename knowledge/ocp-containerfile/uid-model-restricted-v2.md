# UID Model — restricted-v2 (Legacy)

**Applies to:** OCP 4.11–4.19 | SCC: `restricted-v2` | `hostUsers: true` (default)

## How It Works

Under `restricted-v2`, OpenShift **overrides** the Containerfile `USER`
directive at pod admission time. The SCC's `runAsUser` strategy is
`MustRunAsRange`, which:

1. Reads the namespace annotation `openshift.io/sa.scc.uid-range`
   (default: `1000000000/10000`)
2. If the pod spec does not set `runAsUser`, **injects** the first UID
   from that range (e.g., `1000620000`)
3. If the pod spec sets `runAsUser` to a value outside the range,
   **rejects** the pod

The Containerfile `USER 1001` is ignored. The process runs as a UID
like `1000620000` — a value the image author cannot predict.

## Key Facts

- The random UID is **always a member of GID 0** (root group).
  This is guaranteed by CRI-O on OpenShift.
- OpenShift 4.x **auto-injects** the random UID into `/etc/passwd`
  inside the container. (On OCP 3.x this was manual.)
- All pods in the same namespace get the **same first UID** by default.
  Different namespaces get different ranges.
- The `USER` directive in the Containerfile still matters for
  certification (`RunAsNonRoot` test) — it must not be `root` or `0`.

## Containerfile Implications

### Correct Pattern

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y nodejs npm && \
    microdnf clean all

COPY --chown=1001:0 app /app
WORKDIR /app

# Directories the app writes to must be group-writable
RUN chgrp -R 0 /app/data /app/logs && \
    chmod -R g=u /app/data /app/logs

# USER must be non-root for certification, but the actual
# runtime UID will be different (random, from namespace range)
USER 1001

EXPOSE 8080
ENTRYPOINT ["node", "server.js"]
```

### Anti-Patterns

```dockerfile
# ❌ USER root — rejected by restricted-v2, fails certification
USER root

# ❌ USER nginx — non-numeric, can't verify non-root
USER nginx

# ❌ Hardcoded file ownership to a specific UID
RUN chown -R 1001:1001 /app
# This fails because runtime UID is not 1001 — it's 1000620000.
# The process can't write to files owned by 1001 unless GID 0
# has write permission.

# ❌ Listening on port 80
EXPOSE 80
# Non-root UID cannot bind ports < 1024
```

## What Happens at Runtime

```
Containerfile:  USER 1001
                    ↓
SCC admission:  MustRunAsRange → inject UID 1000620000
                    ↓
Container:      Process runs as UID 1000620000, GID 0
                /etc/passwd entry auto-created
                Files must be accessible via GID 0
```

## Sources

- [Red Hat Blog: A Guide to OpenShift and UIDs](https://www.redhat.com/en/blog/a-guide-to-openshift-and-uids)
- [OKD Cookbook: How can I enable an image to run as a set user ID?](https://cookbook.openshift.org/users-and-role-based-access-control/how-can-i-enable-an-image-to-run-as-a-set-user-id.html)
- [OKD 4.20: Managing SCCs](https://docs.okd.io/4.20/authentication/managing-security-context-constraints.html)
