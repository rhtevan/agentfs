---
name: spec-kit-setup
description: >
  install spec-kit, setup specify, upgrade spec-kit
metadata:
  version: "1.1.0"
  model-tier: T3
  tags: [speckit, specify, cli, setup, installation]
---

# Spec-kit Setup

Detect, install, or upgrade the `specify` CLI (GitHub Spec Kit) via `uv tool`.

## What This Skill Does

Install or upgrade the `specify` CLI to the latest version.
The script handles all detection, comparison, and installation
steps automatically.

## Workflow

### Step 1 — Run the install script

The agent MUST run the install script:

```bash
bash ~/.agents/skills/spec-kit-setup/scripts/check-and-install.sh
```

The script handles version detection, download, and installation
automatically. The agent MUST report the script output verbatim.

Optional flags: `--force` (reinstall), `--tag vX.Y.Z` (pin version),
`--json` (machine-readable output).

### Step 2 — Verify

The agent MUST confirm installation:

```bash
specify version
```

## Output Contract

- Exit 0 → installation successful (or already up to date)
- Exit 1 → installation failed (script output explains the cause)

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

This skill is purely mechanical — no semantic judgment is required.
All decisions are made by the install script.

## Prerequisites

- **uv** — must be installed and locatable (the script searches common paths)
- **Python 3.11+** — required by the specify CLI
- **Git** — required by `uv tool install` to clone the spec-kit repo
- **Network access** — to reach `api.github.com` and `github.com`

If `uv` is not found, install it first: https://docs.astral.sh/uv/

## Verification

- [ ] `specify version` reports the expected version
- [ ] Script exits 0 with a success message


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
