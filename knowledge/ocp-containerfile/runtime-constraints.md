# Runtime Constraints

**Applies to:** Both legacy and user namespace modes (noted where different)

## Non-Privileged Ports

Non-root users cannot bind ports below 1024. This applies under
**both** `restricted-v2` and `restricted-v3` — user namespaces
do not grant `NET_BIND_SERVICE` on the host.

```dockerfile
# ✅ Correct — non-privileged port
EXPOSE 8080

# ❌ Incorrect — requires root or NET_BIND_SERVICE
EXPOSE 80
```

Common remappings:

| Default Port | Remap To | Application |
|:------------:|:--------:|-------------|
| 80 | 8080 | HTTP (nginx, httpd, app servers) |
| 443 | 8443 | HTTPS |
| 3306 | 33060 | MySQL (or keep 3306 — it's >1024) |

## Entrypoint Patterns

### Exec Form (Recommended)

```dockerfile
ENTRYPOINT ["python3", "-m", "app"]
CMD ["--port", "8080"]
```

- Process is PID 1 — receives SIGTERM directly for graceful shutdown
- `CMD` provides overridable defaults
- No shell interpretation — no variable expansion, no pipes

### Shell Form (Avoid)

```dockerfile
# ❌ Shell wraps the process — PID 1 is /bin/sh, not your app
ENTRYPOINT python3 -m app --port 8080
```

- `/bin/sh -c` is PID 1 — SIGTERM goes to shell, not the app
- Application doesn't shut down gracefully on `oc delete pod`
- Kubernetes sends SIGKILL after terminationGracePeriodSeconds

### Wrapper Script Pattern

When startup logic is needed (passwd injection, env setup):

```dockerfile
COPY --chown=1001:0 entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python3", "-m", "app"]
```

The wrapper **must** use `exec` to replace itself:

```bash
#!/bin/sh
# Any startup logic here
exec "$@"
```

`exec "$@"` replaces the shell with the CMD process, which
becomes PID 1 and receives signals directly.

## /etc/passwd Injection

### When Needed

Some applications require a valid `/etc/passwd` entry for the
running user (home directory lookup, username resolution).

### OCP 4.x Behavior

OpenShift 4.x **auto-injects** the random UID into `/etc/passwd`
inside the container. For most applications this is sufficient.

### Manual Fallback (Legacy)

For applications that need a specific username or home directory:

```dockerfile
# Make /etc/passwd writable by group 0
RUN chgrp 0 /etc/passwd && chmod g=u /etc/passwd

COPY --chown=1001:0 entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
```

```bash
#!/bin/sh
# entrypoint.sh — inject passwd entry for arbitrary UID
if ! whoami > /dev/null 2>&1; then
  if [ -w /etc/passwd ]; then
    echo "${USER_NAME:-appuser}:x:$(id -u):0:dynamic user:${HOME:-/tmp}:/sbin/nologin" >> /etc/passwd
  fi
fi
exec "$@"
```

### Under User Namespaces (restricted-v3)

Not needed. The container runs as its declared UID with a valid
user namespace context. The process sees itself as the expected
UID with a valid passwd entry.

## Read-Only Root Filesystem

Design for `readOnlyRootFilesystem: true` in the pod security
context:

```yaml
securityContext:
  readOnlyRootFilesystem: true
```

This means the container cannot write to any path except:
- Explicitly declared `VOLUME` paths
- `emptyDir` or PVC-mounted volumes
- `/tmp` (if mounted as a volume)

### Containerfile Patterns

```dockerfile
# Declare writable paths as volumes
VOLUME ["/tmp", "/var/log/myapp"]

# Log to stdout/stderr instead of files
# Configure app to use /tmp for transient data
ENV TMPDIR=/tmp
```

### Common Violations

| App Writes To | Fix |
|---------------|-----|
| `/var/log/` | Redirect to stdout: `ln -sf /dev/stdout /var/log/myapp/access.log` |
| `/tmp` | Mount emptyDir at `/tmp` in pod spec |
| `/var/cache/` | Mount emptyDir or configure app cache location |
| PID files | Use `/tmp/myapp.pid` or mount emptyDir at PID file location |

## No Hardcoded Hosts or IPs

```dockerfile
# ❌ Hardcoded
ENV DATABASE_HOST=192.168.1.50

# ✅ Configurable via environment or ConfigMap
ENV DATABASE_HOST=""
# Set at deployment time via env/configmap/secret
```

## Gotchas

- **SIGTERM handling**: If the app doesn't handle SIGTERM, Kubernetes
  waits `terminationGracePeriodSeconds` (default 30s) then sends
  SIGKILL. Use exec form entrypoint to ensure the app is PID 1.
- **ubi-micro has no shell**: Entrypoint wrapper scripts don't work
  with `ubi-micro`. Use exec form only, or use a `-dev` variant
  as the runtime base (at the cost of larger image).
- **/dev/stdout permissions**: Some apps need group-write on log
  symlinks. The GID 0 pattern covers this.

## Sources

- [Docker Docs: Use Docker Hardened Images with Red Hat OpenShift](https://docs.docker.com/guides/dhi-openshift/)
- [Red Hat Blog: A Guide to OpenShift and UIDs](https://www.redhat.com/en/blog/a-guide-to-openshift-and-uids)
