---
name: hermes-agentfs-setup
description: >
  configure hermes agentfs, hermes skills dirs, hermes agentfs
platforms: ['linux']
metadata:
  version: "1.3.0"
  model-tier: T2
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

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Prerequisites

- Hermes Agent installed (`~/.hermes/` exists with `config.yaml`)
- AgentFS initialized (`~/.agents/skills/` exists — run `agentfs-setup`
  skill in USER scope if needed)

## Steps

### Step 1 — Check Current Compatibility

The agent MUST run the setup script in check mode:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --check
```

The agent MUST report the script output verbatim.

### Step 2 — USER Setup

The agent MUST run the setup script:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh
```

The script handles configuration changes and backup automatically.
The agent MUST report the script output verbatim.

### Step 3 — PROJECT Setup (per-project)

The agent MUST run the setup script with `--project` in each project
directory that has `.agents/skills/`:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --project
```

Or specify a path explicitly:

```bash
bash ~/.agents/skills/hermes-agentfs-setup/scripts/setup.sh --project /path/to/project
```

The script handles project registration automatically.
The agent MUST report the script output verbatim.

### Step 4 — Restart Hermes

The agent MUST instruct the user to restart any active Hermes session
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

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
