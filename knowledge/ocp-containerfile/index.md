# OpenShift Containerfile Best Practices

Knowledge bundle covering best practices for authoring Containerfiles
(Dockerfiles) that are compatible with Red Hat OpenShift Container Platform.
Covers both the legacy `restricted-v2` SCC model (OCP 4.11–4.19) and the
`restricted-v3` user namespace model (OCP 4.20+).

## Concepts

* [UID Model — restricted-v2 (Legacy)](uid-model-restricted-v2.md) — How OpenShift overrides the Containerfile USER directive with a random project-scoped UID under MustRunAsRange.
* [UID Model — User Namespaces (restricted-v3)](uid-model-user-namespaces.md) — How Linux user namespaces with hostUsers: false change UID handling, and what restricted-v3 enforces.
* [SCC and SecurityContext Relationship](scc-and-security-context.md) — How Kubernetes SecurityContext fields interact with OpenShift's SCC admission controller (validate + mutate).
* [File Permissions — GID 0 Pattern](file-permissions-gid0.md) — The root group ownership pattern required under restricted-v2, and how idmap mounts change the picture under restricted-v3.
* [Base Images — UBI Selection](base-images-ubi.md) — UBI variants (standard, minimal, micro, init), registries, and selection criteria.
* [Image Metadata and Labels](image-metadata-labels.md) — Required certification labels, OpenShift-specific labels, and OCI label conventions.
* [Layer Optimization](layer-optimization.md) — Multi-stage builds, cache ordering, dnf clean, layer count limits.
* [Runtime Constraints](runtime-constraints.md) — Non-privileged ports, read-only root filesystem, entrypoint patterns, /etc/passwd injection.
* [Red Hat Certification Requirements](certification-requirements.md) — Certification test checklist: RunAsNonRoot, BasedOnUBI, HasLicense, HasRequiredLabel, LayerCountAcceptable, and more.
* [S2I Compatibility](s2i-compatibility.md) — Source-to-Image labels and scripts for building S2I builder images.

## Sources

- [Red Hat Blog: A Guide to OpenShift and UIDs](https://www.redhat.com/en/blog/a-guide-to-openshift-and-uids) — William Caban Babilonia
- [Docker Docs: Use Docker Hardened Images with Red Hat OpenShift](https://docs.docker.com/guides/dhi-openshift/)
- [OKD Cookbook: How can I enable an image to run as a set user ID?](https://cookbook.openshift.org/users-and-role-based-access-control/how-can-i-enable-an-image-to-run-as-a-set-user-id.html)
- [Red Hat Certification Troubleshooting](https://github.com/redhat-openshift-ecosystem/certification-releases/blob/main/containers/troubleshooting.md)
- [OpenShift Origin: Image Metadata Proposal](https://github.com/openshift/origin/blob/main/docs/proposals/metadata.md)
- [Kubernetes: User Namespaces](https://kubernetes.io/docs/concepts/workloads/pods/user-namespaces/)
- [Kubernetes v1.33: User Namespaces enabled by default](https://kubernetes.io/blog/2025/04/25/userns-enabled-by-default/)
- [Kubernetes v1.36: User Namespaces GA](https://kubernetes.io/blog/2026/04/23/kubernetes-v1-36-userns-ga/)
- [OKD 4.20: Managing SCCs](https://docs.okd.io/4.20/authentication/managing-security-context-constraints.html)
- [OKD 4.20: Running pods in Linux user namespaces](https://docs.okd.io/4.20/nodes/pods/nodes-pods-user-namespaces.html)
- [Red Hat Blog: OpenShift 4.20 What You Need to Know](https://www.redhat.com/en/blog/red-hat-openshift-42-what-you-need-to-know)
