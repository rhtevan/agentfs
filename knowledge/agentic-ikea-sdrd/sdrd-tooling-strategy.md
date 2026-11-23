---
type: Decision
title: SDRD Tooling Strategy
description: SDKMAN, Devbox, RPM/Flatpak, Direct — the four-layer package strategy on Fedora workstations, layer-assignment rules, Devbox global operation, and the SSSD NSS bridge for Nix binaries
tags: [sdrd, tooling, installation, devbox, sdkman, rpm, flatpak, fedora, k9s, kubectl, sssd, nss, nix, glibc]
timestamp: 2026-11-23T16:20:00-05:00
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
- On SSSD hosts k9s needs the [NSS bridge](#devbox-on-sssd-hosts-nss-bridge);
  without it k9s exits at startup. The layer choice stays Devbox.

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

## Devbox on SSSD hosts (NSS bridge)

On hosts where users come from SSSD (corporate LDAP/IdM/AD) rather than
`/etc/passwd`, Devbox (Nix) binaries cannot resolve the current user.

### Symptom

- k9s: exits at startup, log shows
  `Die getting user home directory error="user: unknown userid <uid>"`
  (after `Kubernetes connectivity OK`).
- `fd --owner <name>`: `'<name>' is not a recognized user name`.
- Tools that never look up the user (hey, uv, yq) are unaffected; tools
  that link `getpwuid_r` only on rare paths (gh, fd, herdr) fail only
  there. Exposure depends on *when* a tool performs the lookup.

### Root cause

Nix glibc is isolated from host libraries by design:

| Step | Nix glibc behavior |
|---|---|
| Reads `/etc/nsswitch.conf` | Yes — uses host config (`passwd: files sss systemd`) |
| Loads `libnss_sss.so.2` | Searches only its own `ld.so.cache` and `lib/` in `/nix/store` → *no such file* |
| Bundled NSS modules | `compat, db, dns, files, hesiod` — no `sss`, no `systemd` |
| Fallback | `files` → `/etc/passwd`, which lacks SSSD users |

Confirm with `LD_DEBUG=libs fd --owner <name> ...` and look for
`find library=libnss_sss.so.2 ... (no such file)`. NixOS avoids this
with an nscd/nsncd daemon; Fedora ships neither.

### Fix (applied on fedora-csb 2026-11-23)

```bash
mkdir -p ~/.local/lib/nss-bridge
ln -sfn /usr/lib64/libnss_sss.so.2 ~/.local/lib/nss-bridge/libnss_sss.so.2
```

Add to `~/.local/share/devbox/global/default/devbox.json`:

```json
"env": { "LD_LIBRARY_PATH": "$HOME/.local/lib/nss-bridge" }
```

`devbox global shellenv` exports it (with `$HOME` expanded) into every
shell that sources Devbox global; run `refresh-global` in open shells.

### Why it is safe

- The bridge directory holds only `libnss_sss.so.2`, which glibc loads
  only for NSS lookups. Host binaries load the same file anyway.
- `libnss_sss.so.2` depends only on `libc.so.6` and needs ≤ `GLIBC_2.34`;
  Nix glibc (2.39–2.44 in the store) is newer, the direction glibc symbol
  versioning supports.
- Failure mode is benign: if a future `sssd-client` needs a newer glibc
  than a Nix tool has, the module fails to load and the tool returns to
  the pre-fix behavior. No crash.

### Rejected alternatives

| Option | Why not |
|---|---|
| Move affected tools to RPM | Per-tool symptom patch; leaves the rest of the Devbox layer broken |
| Add user to `/etc/passwd` | Conflicts with centrally managed SSSD identity |
| nscd / nsncd daemon | Not packaged in Fedora repos; nscd caching alongside SSSD is discouraged |
| Global `LD_LIBRARY_PATH` via `environment.d` | Wider blast radius than needed; scope to the Devbox layer |

## Source of record

The live inventory per layer is maintained in the recovery plan's SDRD
table. This concept holds the durable rules. Update the inventory when
installing; update this concept only when a rule changes.

See [I.K.E.A. → AgentFS Mapping](./ikea-agentfs-mapping.md) for why
these rules live in OKF rather than in per-tool skills.

# Citations

[1] `~/app/playground/incident-2026-11-18-fedora-home-wipe/recovery-plan-and-progress.md` — §2 "Package & Tooling Strategy: SDRD".
