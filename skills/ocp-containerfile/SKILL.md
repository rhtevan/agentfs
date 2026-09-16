---
name: ocp-containerfile
description: >
  audit containerfile, generate containerfile, openshift container image,
  containerfile best practices, ocp containerfile
argument-hint: "[--mode legacy|userns|both]"
compatibility: "podman (for verify), bash"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [openshift, containerfile, container-image, security, scc, ubi, audit]
user-invocable: true
disable-model-invocation: false
---

# OpenShift Containerfile Best Practices

Audit existing Containerfiles or generate new ones that comply with
Red Hat OpenShift security constraints and container certification
requirements. Supports three modes targeting different OpenShift SCC
models: legacy (`restricted-v2`, OCP 4.11–4.19), user namespaces
(`restricted-v3`, OCP 4.20+), or both for backward compatibility.

This skill references the `ocp-containerfile` knowledge bundle at
`~/.agents/knowledge/ocp-containerfile/` for detailed explanations
of each rule. The skill handles the procedural workflow; the
knowledge bundle provides the "why."

## Prerequisites

- `bash` for audit and generate scripts
- `podman` for image verification (verify mode only)
- A project directory with application source (generate mode)

## Modes

| Mode | Flag | Target SCC | When to Use |
|------|------|-----------|-------------|
| `legacy` | `--mode legacy` | `restricted-v2` | OCP 4.11–4.19 clusters only |
| `userns` | `--mode userns` | `restricted-v3` | OCP 4.20+ with user namespaces |
| `both` | `--mode both` | Both | **Default.** Backward compat across versions |

If the user doesn't specify a mode, default to `both`.

## Steps

### 1. Determine Operation

Ask the user what they need:

| User Intent | Operation |
|-------------|-----------|
| "audit my containerfile", "check containerfile" | **Audit** — lint existing Containerfile |
| "generate containerfile", "create containerfile" | **Generate** — create from CWD |
| "verify image", "check image" | **Verify** — inspect a built image |

### 2. Select Mode

Ask which OpenShift version range the image targets. If unclear,
use `both` (default).

### 3. Execute

#### Audit

```bash
bash ~/.agents/skills/ocp-containerfile/scripts/audit.sh \
  --mode <legacy|userns|both> \
  --file <path-to-containerfile>
```

Review the output. For each ❌ failure, explain the rule and
provide the fix, referencing the knowledge bundle concepts.

#### Generate

```bash
bash ~/.agents/skills/ocp-containerfile/scripts/generate.sh \
  --mode <legacy|userns|both> \
  --output Containerfile
```

The script detects the language from CWD (go.mod, package.json,
requirements.txt, pom.xml, Cargo.toml) and generates an
appropriate Containerfile. Review and customize the output —
replace CHANGEME placeholders in labels.

If the language is unsupported (exit 1), use the templates in
`references/containerfile-templates.md` as a starting point and
adapt with model judgment.

#### Verify

```bash
bash ~/.agents/skills/ocp-containerfile/scripts/verify.sh \
  <image-ref> --mode <legacy|userns|both>
```

Requires `podman` and the image must exist locally.

### 4. Report

Present results as a structured table. For failures, reference
the relevant knowledge bundle concept for the user to understand
the "why."

## Audit Rules

| ID | Rule | Legacy | UserNS | Script Check |
|:--:|------|:------:|:------:|-------------|
| R1 | Non-root USER directive | ✅ | ✅ | `USER` present, not root/0 |
| R2 | Numeric UID | ✅ | ✅ | `USER` value is integer |
| R3 | GID 0 permissions | ✅ | ⚠️ compat | chgrp/chmod/chown pattern |
| R4 | Non-privileged ports | ✅ | ✅ | EXPOSE < 1024 |
| R5 | UBI base image | ✅ | ✅ | FROM line |
| R6 | Required labels (6) | ✅ | ✅ | LABEL presence |
| R7 | /licenses directory | ✅ | ✅ | /licenses in RUN/COPY |
| R8 | Layer count (<40) | ✅ | ✅ | FROM+RUN+COPY+ADD count |
| R9 | Package cache cleanup | ✅ | ✅ | dnf/microdnf clean |
| R10 | Multi-stage build | ✅ | ✅ | Multiple FROM |
| R11 | Entrypoint exec form | ✅ | ✅ | ENTRYPOINT [...] |
| R12 | No RPM modifications | ✅ | ✅ | sed -i on system paths |

## Gotchas

- **NFS volumes** do not support idmap mounts — pods using NFS PVs
  will have permission issues under user namespaces.
- **NVIDIA GPU Operator** is incompatible with `hostUsers: false`
  as of 2026. Use `restricted-v2` via annotation override.
- **Namespace UID range** must be adjusted to ≤65535 for user
  namespaces (admin task, not Containerfile concern).
- **`COPY --chown` at build time** doesn't help runtime-created files
  under `restricted-v2` — the GID 0 pattern is still needed.
- **Mixed cluster versions** — use `both` mode if images run on
  OCP 4.11–4.19 AND 4.20+ clusters.

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `audit.sh` | ✅ (read-only) | Report findings. No state change. |
| `generate.sh` | ✅ | Safe to retry. Output is to stdout or file. |
| `verify.sh` | ✅ (read-only) | Report findings. No state change. |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `audit.sh` exit 2 | No Containerfile found | Use `--file <path>` |
| `generate.sh` exit 1 | Unsupported language | Use templates from `references/containerfile-templates.md` |
| `verify.sh` exit 1 + "Failed to inspect" | Image not in local storage | `podman pull <image>` first |
| False positive on R3 (GID 0) | Pattern in a comment | Script strips comments — check for non-standard comment syntax |
| False positive on R5 (UBI) | Multi-stage with non-UBI build stage | Only final stage matters — script checks last FROM |

## References

- [Containerfile Templates](references/containerfile-templates.md) — full
  annotated templates per language and mode
- Knowledge bundle: `~/.agents/knowledge/ocp-containerfile/`

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
