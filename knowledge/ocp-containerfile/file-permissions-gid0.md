# File Permissions — GID 0 Pattern

**Applies to:** Legacy (`restricted-v2`) — mandatory. User namespaces (`restricted-v3`) — not required but harmless for backward compat.

## The Problem

Under `restricted-v2`, the container runs as a random UID (e.g.,
`1000620000`) that the image author cannot predict. Standard Unix
file permissions require either owner or group match to write. Since
the UID is unpredictable, **owner match is impossible**. The only
stable identity is **GID 0** (root group) — CRI-O always assigns
the container process to this group.

## The Pattern

```dockerfile
# Make directories writable by any user in group 0
RUN chgrp -R 0 /app/data /app/logs /app/tmp && \
    chmod -R g=u /app/data /app/logs /app/tmp
```

`g=u` copies the user permission bits to the group permission bits.
If user has `rwx`, group gets `rwx`. This ensures any UID in GID 0
has the same access as the owner.

## Where to Apply

Apply GID 0 permissions to every directory the application writes to
at runtime:

| Path Type | Examples |
|-----------|---------|
| Application data | `/app/data`, `/var/lib/myapp` |
| Logs | `/app/logs`, `/var/log/myapp` |
| Temporary files | `/tmp`, `/app/tmp` |
| Config written at startup | `/app/config`, `/etc/myapp` |
| PID files | `/var/run/myapp` |
| Cache | `/var/cache/myapp`, `/app/.cache` |
| Volume mount points | Any path where a PVC is mounted |

## Complete Example

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y nginx && microdnf clean all

# Copy config and static files
COPY nginx.conf /etc/nginx/nginx.conf
COPY html /usr/share/nginx/html

# nginx needs to write to these directories
RUN mkdir -p /var/cache/nginx /var/run/nginx /var/log/nginx && \
    chgrp -R 0 /var/cache/nginx /var/run/nginx /var/log/nginx \
               /etc/nginx && \
    chmod -R g=u /var/cache/nginx /var/run/nginx /var/log/nginx \
                 /etc/nginx

USER 1001
EXPOSE 8080
CMD ["nginx", "-g", "daemon off;"]
```

## COPY --chown Interaction

`COPY --chown=1001:0` sets ownership at **build time**. This is
correct for files copied into the image. But it does not help files
created at **runtime** — those are owned by the random UID.

```dockerfile
# ✅ Correct: sets GID 0 at build time
COPY --chown=1001:0 app /app

# ❌ Incomplete: runtime-created files in /app/uploads will be
#    owned by the random UID with no group write
# Fix: also chmod g=u on directories where runtime writes occur
RUN chmod -R g=u /app/uploads
```

## Volume Mount Permissions

Files on PVCs follow the same rules. The `fsGroup` field in the
pod spec helps:

```yaml
spec:
  securityContext:
    fsGroup: 0    # or omit — SCC MustRunAs injects from range
```

When `fsGroup` is set, the kubelet recursively chowns the volume
to the specified GID. Combined with the image's `chmod g=u`, this
ensures the random UID can write via group membership.

For files **created** on the PVC at runtime, the `setgid` bit
(set by `fsGroup`) ensures new files inherit the group.

## Under User Namespaces (restricted-v3)

With `hostUsers: false` and idmap mounts, the GID 0 pattern is
**not required**:

- The container sees files as owned by its declared UID (from the
  image `USER` directive or pod `runAsUser`)
- The kernel remaps UIDs at the VFS layer — no `chown` needed
- File ownership on disk is unchanged; only the mount-time view
  is translated

The GID 0 pattern is still **harmless** under user namespaces and
provides backward compatibility with `restricted-v2` clusters.

## Gotchas

- **umask**: The default umask (`0022`) means new files are `rw-r--r--`
  (group has read only, not write). If the app creates files that
  other processes in the container need to write, set `umask 0002`
  in the entrypoint or configure the application.
- **Recursive chown on large directories**: Avoid `chown -R` on
  directories with thousands of files in the Containerfile — it
  adds to build time and layer size. Use `COPY --chown` when
  possible and `chmod g=u` only on writable directories.
- **SELinux**: File labels also matter. Under `MustRunAs` SELinux
  strategy, the container gets MCS labels from the namespace. Files
  on hostPath volumes may have wrong SELinux labels.

## Sources

- [Docker Docs: Use Docker Hardened Images with Red Hat OpenShift](https://docs.docker.com/guides/dhi-openshift/)
- [Red Hat Blog: A Guide to OpenShift and UIDs](https://www.redhat.com/en/blog/a-guide-to-openshift-and-uids)
- [Kubernetes v1.36: User Namespaces GA](https://kubernetes.io/blog/2026/04/23/kubernetes-v1-36-userns-ga/)
