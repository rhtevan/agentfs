---
name: hermes-install
description: >
  install hermes, hermes install status
argument-hint: "install hermes [--no-desktop] | hermes install status"
compatibility: "Linux (glibc), bash, git, curl, libatomic"
metadata:
  author: agentfs
  version: "1.2.0"
  model-tier: T2
  tags: [hermes, install, bootstrap, agent]
user-invocable: true
disable-model-invocation: false
---

# Hermes Install

Install Hermes Agent (CLI + Desktop) on this machine by running the
official upstream installer non-interactively, behind a dry-run gate,
a checksum report, and a data-survival check. The upstream installer is
normally piped from `curl` into `bash`, which cannot be previewed and
may prompt for `sudo`. This skill wraps it so the install is
repeatable, previewable, and never loses an existing `~/.hermes`
(sessions, kanban, skills, cron, logs). Use it for a first install or
after a home-directory loss. Use the follow-on skills afterwards:
`hermes-desktop-fixes`, `hermes-agentfs-setup`, `hermes-litellm-provider`.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0.0 |
| **Trigger** | `install hermes`, `hermes install status` |
| **Dependencies** | `git`, `curl`, `libatomic`; upstream `https://hermes-agent.nousresearch.com/install.sh` |
| **Upgrades** | Out of scope — use `hermes update` (patched by `hermes-desktop-fixes`) |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Report install state without changes | `scripts/status.sh` → exit 0 installed / 1 not installed |
| S2 | Preview the install | `scripts/install.sh --dry-run` → `DRY_RUN_RESULT=CONVERGED\|PENDING` |
| S3 | Gate missing system packages | `install.sh` exits 3 with the exact `sudo dnf install` command |
| S4 | Install CLI + Desktop non-interactively | `install.sh` → `status.sh` exit 0, desktop built |
| S5 | Preserve existing `~/.hermes` data | `install.sh` prints `All N pre-existing … entries preserved`; exit 1 on any loss |
| S6 | Never touch a complete install | `install.sh` on an installed host → `already installed — not touched`, exit 0 |
| S7 | Set up bash completion | `install.sh` writes `~/.local/share/bash-completion/completions/hermes` (lazy loader → `hermes completion bash` + `--help` option fallback); an older managed loader is updated; a file not managed by this skill is left untouched |

## Rules

Do NOT fabricate, generate, or invent data. Every fact in your output
MUST come from script output. If information is unavailable, say so.

Do NOT run the upstream installer directly (`curl … | bash`). Run it
only through `scripts/install.sh`.

Do NOT move, delete, or rename `~/.hermes`. The installer writes
`config.yaml` and `.env` only when they are missing.

Do NOT use this skill to upgrade. Use `hermes update`.

## Prerequisites

- Linux with glibc (Fedora tested)
- `git`, `curl`, `libatomic` (Step 1 gates them)
- Network access to `hermes-agent.nousresearch.com` and `github.com`

## Workflow

### Step 1 — Check state

```bash
bash ~/.agents/skills/hermes-install/scripts/status.sh
```

Exit 0 means Hermes is installed. Stop and report. Exit 1 means continue.

### Step 2 — Dry-run

```bash
bash ~/.agents/skills/hermes-install/scripts/install.sh --dry-run
```

Read the `DRY_RUN_RESULT=` line:
- `CONVERGED` → report "already installed". Stop.
- `PENDING` → present the planned actions to the user. Wait for approval.
- Exit 3 → follow Step 3.

### Step 3 — Privilege gate (🔒, only on exit 3)

The script prints a `sudo dnf install -y …` command. Present it to the
user. Wait for the user to confirm completion. Re-run Step 2.

### Step 4 — Install

```bash
bash ~/.agents/skills/hermes-install/scripts/install.sh
```

Add `--no-desktop` for CLI only. Add `--channel main` to follow every
commit. To run a copy the user already reviewed, add
`--installer FILE --sha256 HEX`. The install takes several minutes.
It ends with the Step 1 status report.

### Step 5 — Hand off

Report the status output, including the bash completion line (new shells:
`hermes <Tab>`; current shell: `source ~/.local/share/bash-completion/completions/hermes`).
Point to the next skills in order:
`hermes-desktop-fixes` → `hermes-agentfs-setup` → `hermes-litellm-provider`.

## Output Contract

`status.sh`:

```
=== Hermes Agent — STATUS ===
  ✅ Command:   <path> (<version>)
  ✅ Checkout:  <tag|sha>
  ✅ Config:    ~/.hermes/config.yaml
  ✅ Desktop:   built (...)          # ⚠️ when not built
  ✅ Completion: ~/.local/share/bash-completion/completions/hermes   # ⚠️ when not set up
  ℹ️  Data:      state.db kanban.db skills ...
✅ Hermes Agent installed            # or ❌ … (N missing)
```

`install.sh --dry-run` ends with exactly one `DRY_RUN_RESULT=CONVERGED`
or `DRY_RUN_RESULT=PENDING` line.

## Tests

| Test | Spec | Command | Expected |
|:----:|:----:|---------|----------|
| T1 | S1 | `status.sh` (before install) | `❌ … not installed`, exit 1 |
| T2 | S2 | `install.sh --dry-run` (before install) | `DRY_RUN_RESULT=PENDING`, exit 0, nothing written |
| T3 | S3 | `PATH=/nonexistent bash install.sh --dry-run` | 🔒 gate prints `sudo dnf install -y git curl libatomic`, exit 3 |
| T4 | S4, S5 | `install.sh` | entries preserved, status exit 0, desktop built |
| T5 | S6 | `install.sh` (after install) | `already installed — not touched`, exit 0 |
| T6 | S2 | `install.sh --dry-run` (after install) | `DRY_RUN_RESULT=CONVERGED` |
| T7 | S7 | Installed host without the loader → `install.sh --dry-run`, `install.sh`, then `bash -ic 'source <loader>; complete -p hermes'` | `PENDING` (`Would write: …/completions/hermes`) → `✅ Bash completion: wrote …` → `complete -F _hermes_completion_wrap hermes`; `hermes -<Tab>`, `hermes config set --<Tab>` list options; next dry-run `CONVERGED` |

## Error Handling

| Script | Idempotent | On Failure |
|--------|:----------:|------------|
| `status.sh` | ✅ (read-only) | Exit 1 = not installed. Not an error. |
| `install.sh --dry-run` | ✅ (read-only) | Exit 3 → Step 3. Exit 2 → fix arguments once. |
| `install.sh` | ✅ | Exit 1 → match Troubleshooting. Re-run is safe (upstream repairs a partial checkout). Exit 3 → Step 3. |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| exit 3 `missing system packages` | git/curl/libatomic absent | User runs the printed `sudo dnf install` command; re-run |
| exit 1 `Download failed` | No network / site down | Check connectivity; re-run. Nothing changed. |
| exit 1 `checksum mismatch` | Upstream changed since review | Review the new installer; pass the new `--sha256` |
| exit 1 `Upstream installer failed` | A stage failed | Read `~/.hermes/logs/install.log`; re-run |
| exit 1 `DATA CHECK FAILED` | An entry in `~/.hermes` disappeared | Stop. Report to the user. Restore from backup. Do not re-run. |
| `hermes: command not found` after success | New shell PATH not loaded | `source ~/.bashrc` (installer adds `~/.local/bin`) |

## Gotchas

- The upstream installer updates an existing but incomplete checkout to
  the latest release of its channel. Only a complete install is skipped.
- A damaged checkout is moved aside to `~/.hermes/hermes-agent.broken-<ts>`
  by upstream. Clean it up manually after a successful install.
- `--non-interactive` skips the setup wizard and the gateway service.
  Configure the model with `hermes-litellm-provider`. Run
  `hermes gateway install` only if messaging gateways are needed.
- The installer checks each shell rc file on its own. It appends a
  guarded `~/.local/bin` PATH line (`# Hermes Agent command`) to
  `~/.bash_profile` and creates `~/.profile` even when `~/.bashrc`
  already adds `~/.local/bin`. The line is a no-op when PATH already
  has it. Remove it only if the user asks.
- The installer always prints "Switching to an older stable release may
  not read state written by canary" when the channel is set to `stable`
  explicitly. It is a generic notice, not a detected downgrade.
- Upstream writes a local install receipt under
  `~/.hermes/telemetry/shared_metrics/`.
- **Upstream completion lists options only for leaf subcommands** (v0.23.3): `hermes -<Tab>`, `hermes config -<Tab>`, `hermes config set --<Tab>` return nothing. The managed loader wraps `_hermes_completion` and falls back to the options in `hermes <path> --help` (cached per shell: first Tab ~0.4s, then instant). Drop the fallback once upstream emits full option lists.

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
