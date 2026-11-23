---
type: Decision
title: SDRD Tooling Strategy
description: SDKMAN, Devbox, RPM/Flatpak, Direct — the four-layer package strategy on Fedora workstations, layer-assignment rules, and Devbox global operation
tags: [sdrd, tooling, installation, devbox, sdkman, rpm, flatpak, fedora, k9s, kubectl]
timestamp: 2026-11-23T09:55:00-05:00
---

# SDRD Tooling Strategy

**SDRD** = **S**DKMAN, **D**evbox, **R**PM (and Flatpak), **D**irect.
It is the package and tooling strategy adopted for the Fedora workstation
(`fedora-csb`) during recovery from the 2026-11-18 home-directory wipe.

## History

It replaced **SSD** (SDKMAN, Snap, Devbox). Snap was dropped completely
because of SELinux/classic-snap friction and loop-mount overhead.
`snapd`, `snapd-selinux`, and all snaps were removed.

## Layers

| Layer | Role | Typical contents |
|---|---|---|
| **S — SDKMAN** | JVM toolchain and version switching (`~/.sdkman`) | java, maven, jbang, quarkus |
| **D — Devbox** | Reproducible user CLI toolchain (`devbox global`, backed by Determinate Nix `/nix`) | gh, yq, uv, fzf, fd, k9s; parked: helm, tkn |
| **R — RPM / Flatpak** | System packages, vendor RPMs, Fedora-native GUI Flatpaks | podman, git, gcloud, Goose Desktop, Chrome; Flatpaks: Slack, Obsidian (user-scope unfiltered flathub) |
| **D — Direct** | Upstream binaries/installers not served by Devbox or RPM | `~/.local/bin`: agy, claude, goose CLI, skupper, hermes; `/usr/local/bin/kubectl`; crc |

## Layer-assignment rules

Apply in order; first match wins.

1. **JVM tool** (needs version switching alongside a JDK) → SDKMAN.
2. **User CLI tool** available in Devbox → Devbox (`devbox global add`).
3. **System integration** (daemons, SELinux policy, systemd system units,
   vendor RPM repos) or **GUI app** → RPM or Flatpak.
4. **Not packaged** in Devbox or RPM, or vendor-mandated installer →
   Direct, into `~/.local/bin` where possible.

Same version in Devbox and RPM does not change the answer: a user CLI
tool goes to Devbox (rule 2 precedes rule 3).

### Worked example: k9s (2026-11-22)

- Not a JVM tool → skip S.
- User CLI, `devbox search k9s` → available (0.51.0) → **Devbox**.
- RPM `k9s-0.51.0-2.fc44` existed too, but rule 2 wins. It also keeps
  k9s next to the other Kubernetes CLIs parked for Devbox (helm, tkn).
- Install: `devbox global add k9s`. A per-tool skill is not justified
  (one idempotent command).

### Classification audit: kubectl

`kubectl` at `/usr/local/bin` was listed under RPM. Check:
`rpm -qf /usr/local/bin/kubectl` → *not owned by any package*. It is a
manual install, so it belongs to **Direct**. Verify ownership with
`rpm -qf` before assigning a binary to the R layer.

## Operating the Devbox global layer

| Need | Command | Notes |
|---|---|---|
| Add a tool | `devbox global add <pkg>` (pin: `<pkg>@<ver>`) | Existing packages are `@latest` |
| Pick up changes in the current shell | `refresh-global` | Alias, no dev shell needed |
| New shells | automatic | `~/.bashrc` evals `devbox global shellenv` |
| List | `devbox global list` | |

- `refresh-global` is an alias defined by the output of
  `devbox global shellenv`:
  `eval "$(devbox global shellenv --preserve-path-stack -r)" && hash -r`.
  Run it in the shell that printed *"Your devbox environment may be out
  of date"*.
- `devbox shell` is unrelated. It needs a project `devbox.json` in the
  current directory or a parent, and fails otherwise ("no devbox.json
  found").
- `~/.bashrc` guards the `shellenv` eval with a shell-local
  `__devbox_shellenv_done` variable to prevent a fork bomb under Goose
  shells (see `goose-desktop-env-fix`).

## Source of record

The live inventory per layer is maintained in the recovery plan's SDRD
table. This concept holds the durable rules. Update the inventory when
installing; update this concept only when a rule changes.

See [I.K.E.A. → AgentFS Mapping](./ikea-agentfs-mapping.md) for why
these rules live in OKF rather than in per-tool skills.

# Citations

[1] `~/app/playground/incident-2026-11-18-fedora-home-wipe/recovery-plan-and-progress.md` — §2 "Package & Tooling Strategy: SDRD".
