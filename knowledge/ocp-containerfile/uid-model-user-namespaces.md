# UID Model — User Namespaces (restricted-v3)

**Applies to:** OCP 4.20+ | SCC: `restricted-v3` | `hostUsers: false` (mandatory)

## How It Works

`restricted-v3` adds one constraint over `restricted-v2`:
`userNamespaceLevel: RequirePodLevel`, which mandates that pods run
in a Linux user namespace (`hostUsers: false`).

With `hostUsers: false`:

1. The kubelet allocates a **unique host UID range** for the pod from
   `/etc/subuid` (e.g., `65536–131071`). Each pod on the same node
   gets a different range.
2. The container runtime creates a **new user namespace** and writes
   the mapping to `uid_map`/`gid_map`: container UID 0 → host UID
   65536, container UID 1000 → host UID 66536, etc.
3. The Containerfile `USER` directive **is honored**. The process runs
   as that UID inside the container. On the host, it's mapped to an
   unprivileged UID.
4. **ID-mapped mounts** (Linux 5.12+) transparently remap file
   ownership at the VFS layer. No `chown` needed. O(1) operation.

## Key Facts

- `runAsUser: 0` (root) **is allowed** under user namespaces. Root
  inside the container is an unprivileged UID on the host.
- Kubernetes PSA **relaxes** `runAsNonRoot` and `runAsUser` checks
  for user-namespaced pods — these fields are not constrained.
- Each pod gets a **different UID mapping** on the host, preventing
  lateral movement between compromised containers.
- Capabilities are **namespace-scoped** — `CAP_SYS_ADMIN` inside
  the user namespace does not grant host-level privilege.
- The namespace annotation `openshift.io/sa.scc.uid-range` must be
  adjusted to **≤65535** for user namespaces (default is
  `1000000000/10000`, which is too high).

## Additional SCCs for User Namespaces

| SCC | Purpose |
|-----|---------|
| `restricted-v3` | Default for authenticated users. Requires `hostUsers: false`. Inherits `MustRunAsRange` from `restricted-v2`. |
| `nested-container` | Like `restricted-v2` but with `RequirePodLevel` + `container_engine_t` SELinux type + capabilities not dropped. For buildah/docker-in-docker. |

## Containerfile Implications

### Correct Pattern (User Namespace Target)

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y nodejs npm && \
    microdnf clean all

COPY app /app
WORKDIR /app

# With user namespaces + idmap mounts, GID 0 pattern is
# not required. File ownership is remapped by the kernel.
# USER 0 is safe — root inside is unprivileged on host.
USER 1001

EXPOSE 8080
ENTRYPOINT ["node", "server.js"]
```

### Running as Root Inside (Safe with User Namespaces)

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

# Root inside the container = unprivileged on the host
USER 0

RUN microdnf install -y httpd && microdnf clean all

# No need for chgrp/chmod gymnastics — idmap handles ownership
COPY app /var/www/html

EXPOSE 8080
ENTRYPOINT ["httpd", "-D", "FOREGROUND"]
```

Pod spec:

```yaml
spec:
  hostUsers: false    # mandatory under restricted-v3
  containers:
  - name: app
    image: myapp:latest
    securityContext:
      runAsUser: 0    # allowed — user namespace makes this safe
```

### Backward-Compatible Pattern (Works on Both v2 and v3)

```dockerfile
FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN microdnf install -y nodejs npm && \
    microdnf clean all

COPY --chown=1001:0 app /app
WORKDIR /app

# GID 0 pattern — needed for restricted-v2, harmless on v3
RUN chgrp -R 0 /app/data && chmod -R g=u /app/data

USER 1001

EXPOSE 8080
ENTRYPOINT ["node", "server.js"]
```

## Limitations

- **NFS** does not support idmap mounts — pods using NFS-backed PVs
  may have permission issues under user namespaces.
- **NVIDIA GPU Operator** device plugins are incompatible with
  `hostUsers: false` as of 2026. These workloads must use
  `restricted-v2` via annotation override.
- **`hostNetwork: true`**, **`hostPID: true`**, **`hostIPC: true`**
  are incompatible with `hostUsers: false`.
- **`tmpfs`** requires kernel ≥6.3 for idmap mount support. This
  affects secrets, configmaps, and projected volumes.

## Sources

- [Kubernetes: User Namespaces](https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/)
- [Kubernetes v1.36: User Namespaces GA](https://kubernetes.io/blog/2026/04/23/kubernetes-v1-36-userns-ga/)
- [Kubernetes v1.33: User Namespaces enabled by default](https://kubernetes.io/blog/2025/04/25/userns-enabled-by-default/)
- [OKD 4.20: Running pods in Linux user namespaces](https://docs.okd.io/4.20/nodes/pods/nodes-pods-user-namespaces.html)
- [Red Hat Blog: OpenShift 4.20 What You Need to Know](https://www.redhat.com/en/blog/red-hat-openshift-42-what-you-need-to-know)
- [NVIDIA NIM: Troubleshooting OpenShift SCC Admission](https://docs.nvidia.com/nim/large-language-models/2.0.5/troubleshooting/openshift-scc.html)
