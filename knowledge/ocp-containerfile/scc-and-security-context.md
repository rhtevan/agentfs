# SCC and SecurityContext Relationship

**Applies to:** All OCP versions

## Two Layers

### Kubernetes SecurityContext (The Request)

The pod/container author declares desired security properties in the
pod spec. Kubernetes passes these to the container runtime with
minimal enforcement. SecurityContext exists at two levels:

**Pod-level** (`spec.securityContext` — PodSecurityContext):

| Field | Purpose |
|-------|---------|
| `runAsUser` | UID for all container entrypoints (overridable per container) |
| `runAsGroup` | Primary GID for all containers |
| `runAsNonRoot` | Reject if effective UID = 0 |
| `fsGroup` | Supplemental GID applied to volumes; kubelet chowns volume files to this GID |
| `supplementalGroups` | Additional GIDs for file access |
| `seLinuxOptions` | SELinux label for all containers |
| `seccompProfile` | Seccomp filter: `RuntimeDefault`, `Localhost`, `Unconfined` |
| `sysctls` | Namespaced kernel parameters |
| `fsGroupChangePolicy` | `Always` (recursive chown) or `OnRootMismatch` (lazy) |

**Container-level** (`spec.containers[*].securityContext` — SecurityContext):

| Field | Purpose |
|-------|---------|
| `runAsUser` | Override pod-level UID for this container |
| `runAsGroup` | Override pod-level GID |
| `runAsNonRoot` | Override pod-level check |
| `privileged` | Full host access — root on the host, all capabilities |
| `allowPrivilegeEscalation` | Controls `no_new_privs` flag |
| `capabilities.add` / `.drop` | Linux capabilities to add or remove |
| `readOnlyRootFilesystem` | Mount root FS read-only |
| `procMount` | `Default` (masked) or `Unmasked` (full /proc) |
| `seLinuxOptions` | Override pod-level SELinux context |
| `seccompProfile` | Override pod-level seccomp |

Container-level **wins** when both are set for the same field.

### OpenShift SCC (The Policy)

SCC is an OpenShift-specific admission controller that **validates
AND mutates** the SecurityContext. This is the critical difference
from upstream Kubernetes Pod Security Admission (PSA), which only
validates (accept/reject).

## SCC Admission Flow

```
Pod submitted
  → API Server
    → SCC Admission Controller
      1. Collect all SCCs the pod's service account can "use" (RBAC)
      2. Sort by priority (most restrictive first)
      3. For each SCC:
         a. Apply strategy DEFAULTS (fill missing fields)
         b. VALIDATE resulting context against SCC constraints
         c. If valid → admit, annotate pod, stop
         d. If invalid → try next SCC
      4. No SCC matches → reject pod
      5. Pod annotated: openshift.io/scc: <name>
```

## SCC Strategy Fields (Mutation Engine)

### runAsUser Strategies

| Strategy | Default Behavior | Validation |
|----------|-----------------|------------|
| `MustRunAsRange` | Injects first UID from namespace `uid-range` annotation | Rejects UID outside range |
| `MustRunAs` | Injects configured `uid` | Rejects if UID ≠ configured value |
| `MustRunAsNonRoot` | No injection | Rejects UID 0 or root username |
| `RunAsAny` | No injection | Accepts any UID including 0 |

### Other Strategy Fields

| Field | Strategies |
|-------|-----------|
| `seLinuxContext` | `MustRunAs` (inject from namespace), `RunAsAny` |
| `fsGroup` | `MustRunAs` (inject from namespace range), `RunAsAny` |
| `supplementalGroups` | `MustRunAs` (validate against ranges), `RunAsAny` |

### Boolean/Set Fields

| Field | Effect |
|-------|--------|
| `allowPrivilegedContainer` | Accept/reject `privileged: true` |
| `requiredDropCapabilities` | Force-drop capabilities (`ALL` in `restricted-v2`) |
| `allowedCapabilities` | Whitelist for `capabilities.add` |
| `volumes` | Allowed volume types |
| `allowHostNetwork/PID/IPC` | Accept/reject host namespace sharing |
| `userNamespaceLevel` | `RequirePodLevel` = mandate `hostUsers: false` (OCP 4.20+) |

## Default SCCs (OCP 4.20)

| SCC | runAsUser | Key Constraints | Default For |
|-----|-----------|-----------------|-------------|
| `restricted-v3` | `MustRunAsRange` | `hostUsers: false` mandatory, all caps dropped, seccomp RuntimeDefault | Authenticated users (new installs) |
| `restricted-v2` | `MustRunAsRange` | All caps dropped, seccomp RuntimeDefault | Authenticated users (upgrades from ≤4.19) |
| `nonroot-v2` | `MustRunAsNonRoot` | Like restricted-v2 but any non-zero UID | Explicitly granted |
| `anyuid` | `RunAsAny` | Any UID including 0, host user namespace | Explicitly granted |
| `privileged` | `RunAsAny` | Full host access | Explicitly granted |
| `nested-container` | `MustRunAsRange` | `hostUsers: false`, caps not dropped, `container_engine_t` SELinux | Explicitly granted |

## Granting SCC Access

SCCs are not applied directly to pods. They're granted to **service
accounts** via RBAC:

```bash
# Create dedicated service account
oc create serviceaccount my-sa -n my-project

# Grant SCC access
oc adm policy add-scc-to-user anyuid -z my-sa -n my-project

# Reference in deployment
# spec.template.spec.serviceAccountName: my-sa

# Verify assigned SCC
oc get pod <name> -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Force specific SCC via annotation
# metadata.annotations:
#   openshift.io/required-scc: restricted-v2
```

## Containerfile Relevance

The Containerfile author cannot control which SCC runs the image.
What the author controls:

| Containerfile Directive | SCC Interaction |
|------------------------|----------------|
| `USER <uid>` | May be overridden by `MustRunAsRange`. Must be numeric and non-root for certification. |
| `EXPOSE <port>` | Ports <1024 fail without privilege. SCC doesn't override this — use >1024. |
| File ownership (`chown`, `chmod`) | Must accommodate whatever UID the SCC assigns. GID 0 is the safe pattern under `MustRunAsRange`. |
| `ENTRYPOINT` | Not affected by SCC, but process receives signals differently in exec vs shell form. |

## Sources

- [Kubernetes: Configure a Security Context for a Pod or Container](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/)
- [Kubernetes API: SecurityContext v1 core](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.33/#securitycontext-v1-core)
- [OKD 4.20: Managing SCCs](https://docs.okd.io/4.20/authentication/managing-security-context-constraints.html)
