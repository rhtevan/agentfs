---
name: hermes-desktop-fixes
description: >
  fix hermes desktop, hermes desktop health
argument-hint: "fix hermes desktop | hermes desktop health"
metadata:
  author: agentfs
  version: "4.0.0"
  model-tier: T3
  tags: [hermes, desktop, electron, fix, wayland]
user-invocable: true
disable-model-invocation: false
---

# Hermes Desktop Fixes

Check Hermes Desktop health on Fedora/GNOME Wayland and apply a fix only
when a known problem is detected. Since Hermes v0.23.x, upstream ships the
fixes this skill used to patch in (Wayland app-id desktop entry, provider
identity, userns sandbox, `update --check`). Version 4.0.0 therefore retires
the v3 launcher wrapper, source patches, and desktop-entry watcher. It keeps
a check-first script that detects the remaining failure modes (Intel Arc GPU
crash, visible duplicate entry) and cleans up v3 leftovers, which break the
current upstream launcher. Use it after `hermes-install` or when Desktop
misbehaves.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 4.0.0 |
| **Trigger** | `fix hermes desktop`, `hermes desktop health` |
| **Dependencies** | Hermes installed (`hermes-install`), `git` |
| **Tested** | Hermes v0.23.3, Fedora, Intel Arc (Meteor Lake-P), GNOME Wayland |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Report Desktop health without changes | `setup.sh --dry-run` → `DRY_RUN_RESULT=CONVERGED\|PENDING`, exit 0 |
| S2 | Disable GPU only after a GPU-process FATAL | FATAL in `desktop-chromium.log` → `desktop.disable_gpu true` |
| S3 | Remove a visible legacy `hermes.desktop` | Entry without `NoDisplay=true` removed |
| S4 | Clean up v3 leftovers | wrapper → upstream shim; skip-worktree cleared; old hook/scripts removed |
| S5 | Refuse when Hermes is not installed | exit 1 with `run the hermes-install skill first` |

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script output.

Do NOT write a launcher wrapper, source patch, or desktop entry by hand.
Upstream owns all three.

NEVER call `gdbus call org.gnome.Shell.Eval` to inspect windows on
Wayland. It can crash the GNOME session (full logout).

## Workflow

### Step 1 — Dry-run

```bash
bash ~/.agents/skills/hermes-desktop-fixes/scripts/setup.sh --dry-run
```

- `DRY_RUN_RESULT=CONVERGED` → report "healthy". Stop.
- `DRY_RUN_RESULT=PENDING` → show the `would:` lines to the user. Continue.
- Exit 1 → Hermes is missing. Run the `hermes-install` skill.

### Step 2 — Apply

```bash
bash ~/.agents/skills/hermes-desktop-fixes/scripts/setup.sh
```

Expect `APPLY_RESULT=OK`.

### Step 3 — Verify

Re-run Step 1. Expect `DRY_RUN_RESULT=CONVERGED`. Ask the user to launch
`hermes desktop` from a terminal. Ask the user to report any sudo prompt,
a window that disappears, or a generic icon.

## Output Contract

Dry-run ends with exactly one `DRY_RUN_RESULT=CONVERGED|PENDING` line.
Apply ends with `APPLY_RESULT=OK (N fix(es) applied)` (exit 0) or
`APPLY_RESULT=FAILED (F of N)` (exit 1).

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `setup.sh --dry-run` on a healthy v0.23.3 host | `CONVERGED`, nothing written |
| T2 | S2–S4 | Sandbox `HOME` with v3 wrapper, skip-worktree file, hook, scripts, visible legacy entry, GPU FATAL log → `--dry-run` | `PENDING`, 7 fixes |
| T3 | S2–S4 | Same sandbox → apply | `APPLY_RESULT=OK (7 …)`; shim execs `.hermes/bin/hermes`; file restored |
| T4 | S5 | `HERMES_HOME=/nonexistent setup.sh --dry-run` | exit 1 |
| T5 | — | `setup.sh --bogus` | exit 2 |

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `setup.sh --dry-run` | ✅ (read-only) | Exit 1 → `hermes-install`. Exit 2 → fix arguments. |
| `setup.sh` | ✅ | Exit 1 → show the `❌ failed:` lines to the user. Do not improvise. |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Window disappears ~40 s after launch | Intel Arc GPU process crash (Electron + Wayland) | `setup.sh` sets `desktop.disable_gpu true` when the FATAL is logged |
| Two Hermes icons in the Apps grid | Visible pre-rename `hermes.desktop` | `setup.sh` removes it (upstream keeps a hidden alias) |
| `hermes` fails: `venv/bin/hermes: No such file` | v3 wrapper still installed | `setup.sh` restores the upstream shim |
| `hermes update`: `not uptodate. Cannot merge` | Old skip-worktree patch | `setup.sh` clears the flag and restores the file |
| Window translucent on Linux | Renderer default in `localStorage` (no Linux toggle) | See Bug #7 in references |
| `ERROR … ozone-platform=wayland is not compatible with Vulkan` in the terminal | Chromium noise | Ignore. Not a failure. |

## References

- [references/history.md](./references/history.md) — v1–v3 bug history,
  which upstream change absorbed each fix, and the Bug #7 renderer-JS technique

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
