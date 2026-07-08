---
name: spec-kit-setup
description: >
  Check the existence of GitHub's spec-kit (specify CLI) and then install or
  upgrade it to the latest release. Use when a user asks to install spec-kit,
  set up Spec-Driven Development, check for spec-kit updates, upgrade specify,
  or when another skill or workflow requires spec-kit as a prerequisite.
---

# Spec-kit Setup

Detect, install, or upgrade the `specify` CLI (GitHub Spec Kit) via `uv tool`.

## What This Skill Does

1. Locates `uv` (checks PATH, `~/.hermes/bin`, `~/.local/bin`, `~/.cargo/bin`,
   nix store).
2. Checks whether `specify` is already installed and reads its current version.
3. Fetches the latest release tag from
   `github.com/github/spec-kit/releases/latest`.
4. Compares the installed version against the latest tag.
5. Installs (fresh) or upgrades (if behind or `--force`) using
   `uv tool install specify-cli --force --from git+...@<tag>`.
6. Verifies the new installation by running `specify version`.

## Usage

Run the bundled script from the skill directory:

```bash
bash <skill-dir>/scripts/check-and-install.sh
```

### Options

| Flag | Effect |
|------|--------|
| `--json` | Machine-readable JSON output |
| `--force` | Reinstall even if already at the latest version |
| `--tag vX.Y.Z` | Pin to a specific release tag instead of latest |

### Examples

```bash
# Auto-detect and install/upgrade to latest
bash <skill-dir>/scripts/check-and-install.sh

# Force reinstall at current latest
bash <skill-dir>/scripts/check-and-install.sh --force

# Pin to a specific release
bash <skill-dir>/scripts/check-and-install.sh --tag v0.11.8

# JSON output for scripted use
bash <skill-dir>/scripts/check-and-install.sh --json
```

## Prerequisites

- **uv** — must be installed and locatable (the script searches common paths)
- **Python 3.11+** — required by the specify CLI
- **Git** — required by `uv tool install` to clone the spec-kit repo
- **Network access** — to reach `api.github.com` and `github.com`

If `uv` is not found, install it first: https://docs.astral.sh/uv/

## Version Detection

Spec-kit has shipped two different `specify version` output formats:

| Format | CLI Version Field | Release Version Source |
|--------|-------------------|------------------------|
| Old (CLI ≤ 0.0.x) | `CLI Version` + `Template Version` | Template Version matches the release tag |
| New (CLI ≥ 0.11.x) | `CLI Version` only | CLI Version matches the release tag |

The script handles both formats automatically — it checks for `Template Version`
first (old format) and falls back to `CLI Version` (new format).

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success — installed, upgraded, or already current |
| 1 | Fatal error — missing `uv`, missing `python3`, install failure |
| 2 | User-actionable issue — bad arguments |

## After Installation

Once `specify` is available, common next steps:

```bash
# Verify
specify version
specify check

# Initialize a project
cd <project-root>
specify init . --integration <agent>

# Or proceed to the agentfs-setup skill for the DotAgents structure
```

## JSON Output Schema

When `--json` is passed, the script emits a single JSON object:

```json
{
  "action": "installed | upgraded | current | error",
  "version": "0.11.8",
  "latest_tag": "v0.11.8",
  "message": "Human-readable summary"
}
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-06-24 23:19 | v1.0 — Initial skill |
