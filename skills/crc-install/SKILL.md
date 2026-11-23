---
name: crc-install
description: >
  install crc, upgrade crc, uninstall crc, crc install status, log into crc vm
argument-hint: "install crc [--version X.Y.Z] | upgrade crc [--version X.Y.Z] | uninstall crc | crc install status | log into crc vm"
compatibility: "Linux amd64 (Fedora tested), libvirt/KVM (qemu:///system), bash, curl, python3, sha256sum, xz"
metadata:
  author: agentfs
  version: "1.0.2"
  model-tier: T2
  tags: [crc, openshift-local, install, upgrade, libvirt, ssh, vm-access]
user-invocable: true
disable-model-invocation: false
---

# CRC Install

Guided install, upgrade, repair and uninstall of CRC (OpenShift Local).
The agent and the user do it together: scripts automate every step they
can, and the user decides at two gates. CRC has no in-place upgrade. A new
version means a new binary, a new bundle and a recreated cluster VM. The
old cluster is deleted with its data, and the old binary, bundles and
downloads must be cleaned up. This skill does that in a fixed order:
assess → plan → 👤 confirm deletion → teardown → download → 👤 setup →
start → verify → prune. Day-2 start/stop belongs to `crc-cmd` / `crc-ctl`.
Cluster tuning and operators come after this skill.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0.0 |
| **Trigger** | `install crc`, `upgrade crc`, `uninstall crc`, `crc install status`, `log into crc vm` |
| **Default version** | latest on the mirror (2.65.0 = OpenShift 5.0.0 when written); `--version` pins one |
| **Source** | `https://mirror.openshift.com/pub/openshift-v4/clients/crc/<ver>/` (`release-info.json`, `sha256sum.txt`, `crc-linux-amd64.tar.xz`) |
| **Dependencies** | `crc-cmd` (crcstart/crcstop), libvirt group membership, `~/.crc/crc.json` + pull secret |
| **Follow-ups** | `crc-status`, `crc-post-setup-config`, operator skills, `skupper-model-provider` (CRC site) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Assess without changes → MODE | `status.sh` prints `MODE=FRESH\|RESUME\|CONVERGED\|UPGRADE\|REPAIR` |
| S2 | Preview every action | `install.sh --dry-run` → plan + `DRY_RUN_RESULT=PENDING\|CONVERGED` |
| S3 | Never delete without consent (Gate A) | UPGRADE/REPAIR/`--uninstall` without `--confirm-delete` → exit 4, nothing deleted |
| S4 | Save a rebuild list before an upgrade | `~/.local/share/crc-install/upgrade-notes-<old>-to-<new>-<ts>.txt` |
| S5 | Tear down with the wrappers | `crcstop` → lingering-process cleanup → `crc delete -f` with the OLD binary → `virsh undefine --nvram` / `pool-undefine` fallback |
| S6 | Install only a verified binary | sha256 vs mirror `sha256sum.txt`; mismatch → exit 1, binary unchanged; old binary kept as `crc-<old>` |
| S7 | Gate `crc setup` on sudo (Gate B) | `sudo -n` works → runs it; else exit 3 with the exact command |
| S8 | Start + verify | `crcstart` → `crc status` Running + target OpenShift version → `verified-<ver>` marker |
| S9 | Prune only after verify | `prune.sh` refuses without the marker; removes old bundles, `crc-<old>`, downloads |

## Rules

Do NOT fabricate, generate, or invent data. Every version, state and size
in your output MUST come from script output. If information is unavailable, say so.

Do NOT run `crc start` or `crc stop` directly. Use `crcstart` / `crcstop`
(the scripts do). The libvirt driver (`crc-org/machine-driver-libvirt`
`Driver.Stop()`) sends one ACPI shutdown, waits 120 s, then force-kills.
A large RHCOS guest needs 2.5–6 min to shut down. See `crc-cmd` Background.

Do NOT pass `--confirm-delete` until the user has said yes to the Gate A list
in this conversation. The request "upgrade crc" is not that yes.

Do NOT run `prune.sh` before `install.sh` has verified the new cluster.
Until prune, `install.sh --version <old>` can roll back.

Do NOT edit `~/.crc/crc.json` or the pull secret. Sizing is the user's call.

## Prerequisites

- User in the `libvirt` group; `virtqemud` (or `libvirtd`) reachable at `qemu:///system`
- `~/.crc/crc.json` with `pull-secret-file` set (status.sh checks it)
- ≥ 40 GiB free in `$HOME` (the OpenShift 5.0.0 bundle alone is 5.3 GB compressed)
- `crc-cmd` skill present (install.sh installs the wrappers through it)

## Workflow

### Step 1 — Assess

```bash
bash ~/.agents/skills/crc-install/scripts/status.sh [--version X.Y.Z]
```

Show the full output. `MODE=CONVERGED` → report and stop.

### Step 2 — Plan

```bash
bash ~/.agents/skills/crc-install/scripts/install.sh --dry-run [--version X.Y.Z]
```

`DRY_RUN_RESULT=CONVERGED` → stop. `PENDING` → show the plan and wait for approval.
For an upgrade, name the data loss and point to the notes file (S4).

### Step 3 — Run, and handle the gates

```bash
bash ~/.agents/skills/crc-install/scripts/install.sh [--version X.Y.Z] [--no-start]
```

Run with `timeout_secs` ≥ 3300 (crcstart may take up to 45 min). Exit codes:

| Exit | Meaning | Agent action |
|:----:|---------|--------------|
| 0 | Installed, started, verified | Step 4 |
| 4 | 👤 Gate A: deletion list printed | Show the list. Ask. Only on an explicit yes, re-run with `--confirm-delete`. |
| 3 | 🔒 Gate B: `crc setup` needs sudo | Give the user the printed command for their own terminal (prompts for sudo, downloads the bundle). After they confirm, re-run Step 3. The script resumes (MODE=RESUME). |
| 1 | Failure | Match Troubleshooting. Nothing past the failed phase ran. |

### Step 4 — Prune

```bash
bash ~/.agents/skills/crc-install/scripts/prune.sh --dry-run
bash ~/.agents/skills/crc-install/scripts/prune.sh
```

Show the candidate list and wait for approval before the real run.

### Step 5 — Hand off

Check the `oc PATH` line of `status.sh`. On `⚠️`, give the user the printed line for
`~/.bashrc` (their file — do not write it). Current shell: `eval $(crc oc-env)`.
`crc` is in `~/.local/bin`. Bash completion for `oc` and `crc` needs no setup.

Point to, in order: `crc-status` → `crc-post-setup-config` → operator skills
(use the upgrade notes as the to-do list) → `skupper-model-provider` CRC site.
Check that each operator channel exists on the new OpenShift version first.

### Uninstall

`install.sh --uninstall --dry-run` → Gate A → `install.sh --uninstall --confirm-delete`.
It removes the VM, binaries, `~/.crc/{cache,bin,machines}` and the downloads,
then runs `crc cleanup`. It keeps `crc.json`, the pull secret, the notes and the wrappers.

## Output Contract

`status.sh` prints `✅/⚠️/❌/ℹ️` lines (Target, Binary, VM, Pool, Machine,
Cluster, Setup, Bundle, Downloads, Config, Pull secret, Free disk, Wrapper,
oc PATH, virt-manager) and ends with exactly one `MODE=<mode> — <reason>` line.
`install.sh --dry-run` and `prune.sh --dry-run` end with one `DRY_RUN_RESULT=` line.
`install.sh` prints `── Phase N: <name> ──` per phase and ends with
`✅ crc <ver> running OpenShift <ocp>` or one `❌` / `🔒` / `👤` line.

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | — | `crc <cmd> --help` on the target binary | `version -o json`, `delete -f`, `setup --check-only` (exit 2 when not set up), `cleanup`, `status -o json` exist |
| T2 | S1 | `status.sh` on a clean host | `MODE=FRESH` |
| T3 | S2 | `install.sh --dry-run` on a clean host | plan + `DRY_RUN_RESULT=PENDING` |
| T4 | S1, S3 | sandbox `CRC_HOME` with `machines/crc`, `install.sh` | `MODE=REPAIR`, Gate A list, exit 4, dir kept |
| T5 | S3 | sandbox fake crc 2.64.0, `install.sh` | `MODE=UPGRADE`, exit 4, binary unchanged |
| T6 | S6 | `CRC_MIRROR=file://…` with a wrong sha256 | exit 1, tarball removed, no binary installed |
| T7 | S9 | `prune.sh` without, then with, the marker | exit 1 refused → lists only old bundles/binaries/downloads |
| T8 | S5–S8 | real fresh install → Gate B → start → verify → prune | `✅ crc <ver> running OpenShift <ocp>` |
| T9 | S1 | `status.sh` on this host, then with `HOME=<empty sandbox>` | `✅ oc PATH: … (via ~/.bashrc)` → `⚠️ oc PATH: not set for new shells — add to ~/.bashrc: …` |

Sandbox variables: `CRC_BIN_DIR`, `CRC_HOME`, `CRC_STATE_DIR`, `CRC_STAGE_DIR`, `CRC_MIRROR`.
The full upgrade path (S4/S5 with a live cluster) can be tested only when a newer CRC than the installed one exists.

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `status.sh` | ✅ read-only | Exit 1 = mirror unreachable or unknown `--version` |
| `install.sh --dry-run` | ✅ read-only | Exit 1 = mirror or disk check failed |
| `install.sh` | ✅ re-run resumes (MODE recomputed; done phases are skipped) | Exit 1 → Troubleshooting; exit 3/4 → gates |
| `prune.sh` | ✅ | Exit 1 = not verified (expected before Step 3 ends) |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cannot undefine domain with nvram` | UEFI domain (OVMF NVRAM) | `virsh -c qemu:///system undefine crc --nvram` (install.sh does this) |
| `release 'X' not found` | Offline or no such version | Check `https://mirror.openshift.com/pub/openshift-v4/clients/crc/` |
| `sha256 mismatch` | Corrupt or partial download | Re-run; nothing was installed |
| `crcstart exceeded …s` | Slow first start / operators settling | `crc status`; `tail ~/.crc/crc.log`; re-run Step 3 (RESUME) |
| `OpenShift X running, want Y` | Cluster created by another crc version | `status.sh` (Bundle lines); re-run as UPGRADE with `--confirm-delete` after Gate A |
| Host swaps during start | crc.json memory too high for the host | User lowers `memory` in crc.json; re-run |
| `oc whoami failed` | kubeconfig not set | `eval $(crc oc-env); oc login -u kubeadmin https://api.crc.testing:6443` |

## Gotchas

- `crc status -o json` exits 0 even on errors. Parse `.success`, not the exit code.
- `oc` is `~/.crc/bin/oc/oc`, a symlink into the current bundle, so one static PATH line works
  across versions (`crc oc-env` prints the same path). Bash completion needs nothing:
  bash-completion (2.17, Fedora 44) ships fallback loaders `_oc` / `_crc` that run
  `<cmd> completion bash` on the first <Tab>. `complete -p oc` is empty until then.
- Running any `crc` command creates empty `~/.crc/{bin,cache,sockets}` and logs. These are not leftovers.
- `crc delete` must run with the binary that created the cluster, so teardown runs before the new binary goes in.
- The `latest/` mirror tarball answers HEAD with a redirect (length 0). Downloads use the versioned directory.
- `/etc/hosts` entries for `*.crc.testing` / `*.apps-crc.testing` are managed by `crc-admin-helper` (network-mode user). Leave them.
- A new major OpenShift (e.g. 5.0) can drop operator channels: AAP has only `stable-2.7` on 5.0. Check before Step 5.
- `crc config view` lists only values that are set. `network-mode` may be missing from it even when crc.json sets it.

## CRC VM Access (SSH)

Node-level access to the VM — systemd, journalctl, disk, VM networking —
and the only way in when the cluster API is down. `oc debug node/crc` is a
privileged *pod* on the node, not a VM login, and needs a healthy API
server to schedule it. Kept here (not in `crc-cmd`) because the key and
forwards share this skill's lifecycle: created by the install, removed by
`--uninstall`.

```bash
crc status                     # VM must be Running
ss -tln | grep ':2222'         # user networking: 127.0.0.1:2222 -> VM:22
ssh -i ~/.crc/machines/crc/id_ed25519 -p 2222 core@127.0.0.1
sudo -i                        # root inside the VM (passwordless)
```

- Current `crc` releases have **no `ssh` subcommand** — `crc ssh` fails
  with `unknown command "ssh" for "crc"`. Do not suggest it.
- `crc ip` printing `127.0.0.1` means network-mode user: the VM's internal
  IPs (192.168.126.x / 192.168.127.x) are not routable from the host. The
  loopback forwards (2222 → VM:22, 6443 → API server) are the access path
  and are bound to 127.0.0.1 only.
- The 2222 forward is recreated on every `crc start`; the key
  `~/.crc/machines/crc/id_ed25519` is stable until `crc delete`.
- One-word alias in `~/.ssh/config` (keep it above any `Host *` block):

  ```
  Host crc-vm
      HostName 127.0.0.1
      Port 2222
      User core
      IdentityFile ~/.crc/machines/crc/id_ed25519
      IdentitiesOnly yes
  ```

  Then `ssh crc-vm`.
- Interactive node debugging via the API (only when the cluster is
  healthy): `oc debug node/crc`, then `chroot /host`. A trailing
  `-- chroot /host bash` exits immediately (no TTY) and the debug pod is
  removed without output.

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
