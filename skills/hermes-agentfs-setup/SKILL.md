---
name: hermes-agentfs-setup
description: >
  Configure Hermes Agent for AgentFS compatibility by registering
  ~/.agents/skills (USER) and per-project .agents/skills/ (PROJECT)
  in skills.external_dirs
version: 1.1.0
platforms: [linux]
metadata:
  tags: [hermes, agentfs, configuration, skills, compatibility]
  related_skills: [agentfs-setup, hermes-litellm-provider, hermes-desktop-fixes]
---

# Hermes Agent — AgentFS Compatibility Setup

Configure Hermes Agent so it discovers AgentFS skills, making the same
skill library available to both Goose and Hermes without duplication.

## Problem

AgentFS stores skills at two levels:

| Scope | Path | Goose | Hermes (default) |
|-------|------|-------|------------------|
| USER | `~/.agents/skills/` | ✅ native | ❌ not scanned |
| PROJECT | `.agents/skills/` (CWD) | ✅ native | ❌ not scanned |

Hermes only scans `~/.hermes/skills/` by default. It supports additional
paths via `skills.external_dirs` in `~/.hermes/config.yaml`, but nothing
is configured out of the box.

## What This Skill Fixes

**USER scope** — adds `~/.agents/skills` to `skills.external_dirs` so
Hermes discovers every SKILL.md under `~/.agents/skills/` alongside its
own `~/.hermes/skills/`.

**PROJECT scope** — registers a specific project's `.agents/skills/`
directory (as an absolute path) in `skills.external_dirs`. This is a
per-project action because Hermes has no CWD-relative skill scanning —
there is no way to configure a single relative path that follows the
working directory. Each project must be registered individually.

## Compatibility Matrix (After Setup)

| Feature | Goose | Hermes |
|---------|-------|--------|
| `AGENTS.md` from CWD | ✅ native (default #1) | ✅ native (priority #2) |
| `~/.agents/skills/` (USER) | ✅ native | ✅ via `external_dirs` |
| `.agents/skills/` (PROJECT) | ✅ native (auto) | ✅ via `external_dirs` (manual per-project) |
| SKILL.md format | ✅ YAML frontmatter | ✅ same format |

## Prerequisites

- Hermes Agent installed (`~/.hermes/` exists with `config.yaml`)
- AgentFS initialized (`~/.agents/skills/` exists — run `agentfs-setup`
  skill in USER mode if needed)

## Steps

### Step 1: Check Current Compatibility

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --check
```

Reports USER and PROJECT status, registered project paths, and any
issues to fix.

### Step 2: USER Setup

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh
```

Adds `~/.agents/skills` to `skills.external_dirs`. Idempotent — safe to
run multiple times. Creates a timestamped backup of `config.yaml`.

### Step 3: PROJECT Setup (per-project)

Run this in each project directory that has `.agents/skills/`:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --project
```

Or specify a path:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --project /path/to/project
```

This registers the project's `.agents/skills/` as an absolute path in
`external_dirs`. Idempotent per project.

### Step 4: Restart Hermes

Hermes reads `config.yaml` at session startup. Restart any active session
to pick up the new skill directories.

### Step 5: Verify

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --check
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --list
```

You can also verify from inside Hermes:
- Type `/skills` — AgentFS skills should appear in the list
- Ask Hermes "what skills are available"

## Undo

```bash
# Remove USER entry
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --undo

# Remove current project entry
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --undo-project

# Remove a specific project entry
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --undo-project /path/to/project
```

Undo only removes config entries — it does not delete any skill files.

## Script Reference

| Command | Effect |
|---------|--------|
| `setup.sh` | USER setup — add `~/.agents/skills` |
| `setup.sh --project [path]` | PROJECT setup — register CWD or path |
| `setup.sh --check` | Non-destructive compatibility diagnostic |
| `setup.sh --list` | List all registered AgentFS paths |
| `setup.sh --undo` | Remove USER entry |
| `setup.sh --undo-project [path]` | Remove PROJECT entry for CWD or path |
| `setup.sh --help` | Show usage |

## How It Works

Hermes skill discovery scans directories in this order:

1. `~/.hermes/skills/` — built-in, always scanned
2. Each path in `skills.external_dirs` — scanned in config order

When names collide, `~/.hermes/skills/` wins (local takes precedence).
External dirs are read-only from Hermes's perspective — new skills
created by Hermes go to `~/.hermes/skills/`, not to external dirs.

AgentFS USER skills are authored with the same `SKILL.md` + YAML
frontmatter format that Hermes expects (and that the Agent Skills
standard defines at [agentskills.io](https://agentskills.io)), so no
format conversion is needed.

### Why PROJECT Scope Requires Per-Project Registration

Goose natively scans `.agents/skills/` relative to CWD at every session
start — no config needed.

Hermes resolves `external_dirs` entries once at config load time:
- Absolute paths are used as-is
- Relative paths resolve against `HERMES_HOME` (`~/.hermes/`), NOT CWD
- There is no CWD-relative path expansion

So the only way to make Hermes see a project's `.agents/skills/` is to
register its **absolute path** in `external_dirs`. This is a one-time
action per project — the entry persists across sessions.

## AGENTS.md — No Setup Required

Both Goose and Hermes auto-load `AGENTS.md` from the project root (CWD)
at session startup. No configuration is needed for this.

| Agent | Priority | Scope |
|-------|----------|-------|
| Goose | #1 (in `CONTEXT_FILE_NAMES` default) | CWD + nested subdirs |
| Hermes | #2 (after `.hermes.md` / `HERMES.md`) | CWD + subdirs via `SubdirectoryHintTracker` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-06 11:00 | v1.1 — Added PROJECT scope support (`--project`, `--undo-project`, `--list`) |
| 2026-07-06 10:52 | v1.0 — Initial skill (USER scope only) |
