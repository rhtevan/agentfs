---
name: agentfs-setup
description: >
  setup agentfs, sync agentfs, update agentfs, verify agentfs
metadata:
  version: "4.13.0"
  tags: [agentfs, setup, scaffolding, guardrails, sync]
---

# AgentFS Setup

Scaffold the `.agents/` directory tree and seed foundational files for
AgentFS — a layered, agent-agnostic context structure that works across
AI coding agents.

## Overview

| Property         | Value                                                             |
| ---------------- | ----------------------------------------------------------------- |
| **Default mode** | `project`                                                         |
| **Modes**        | `project` (per-repo context) · `user` (shared library)            |
| **Scripts**      | `scaffold-dotagents.sh` · `seed-agents-md.sh` · `verify-setup.sh` |
| **Design spec**  | [references/design-spec.md](./references/design-spec.md)          |

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical.

| Scope | Root Path | Resolves To | Purpose |
|-------|-----------|-------------|----------|
| **USER** | `~/.agents/` | `/home/<user>/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | `<repo-root>/.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

### What Lives Where

| Resource | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|----------|:-------------------:|:----------------------:|
| `skills/` | ✅ shared | ✅ project-specific |
| `knowledge/` | ✅ shared | ❌ never |
| `memories/` | ❌ never | ✅ per-agent |
| `profiles/` | ❌ never | ✅ multi-agent |
| `SOUL.md` | ❌ never | ✅ agent identity |
| `AGENTS.md` | ❌ never | ✅ (at repo root `./`) |
| `index.md` | ✅ | ✅ |
| `log.md` | ✅ | ✅ |

## Prerequisites: USER Scope Setup

Before running PROJECT mode, `~/.agents/` must exist. There are two
paths to set it up:

### Path A: Full Install (recommended)

Clone the published AgentFS repository directly into `~/.agents/`:

```bash
git clone https://github.com/rhtevan/agentfs.git ~/.agents
```

This gives the complete skill library, knowledge bundles, and
structural scaffolding — ready to use immediately.

### Path B: Minimal Install

For users who want a clean, empty `~/.agents/` and prefer to
cherry-pick skills selectively:

1. Clone the repo to a **staging location** (not `~/.agents/`):
   ```bash
   git clone https://github.com/rhtevan/agentfs.git ~/repos/agentfs
   ```
2. Make the staging location visible to the agent (e.g., add
   `~/repos/agentfs/skills/` to the agent's skill search paths
   — see the relevant agent setup skill for details).
3. Ask the agent to run this skill with USER scope:
   > *"Set up AgentFS in USER mode"*

   The agent loads this skill, recognises the USER scope hint, and
   scaffolds an empty `~/.agents/` with `skills/`, `knowledge/`,
   `index.md`, and `log.md`.
4. Cherry-pick specific skills using the `skill-merge` skill or
   manual copy.

### After USER Setup: Agent Configuration

Each agent needs its own setup to discover AgentFS context files:

| Agent | Setup Skill |
|-------|-------------|
| Goose | `goose-agentfs-setup` |
| Hermes | `hermes-agentfs-setup` |

## Usage

### PROJECT mode (default — run once per repo)

Ask the agent to run this skill in the target repo:

> *"Set up AgentFS for this project"*

Since PROJECT is the default mode, no additional scope hint is needed.
The agent runs the following scripts:

```bash
# 1. Scaffold .agents/ directory
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh --mode project

# 2. Create AGENTS.md at repo root
bash ~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh
```

Creates:
- `.agents/skills/` — project-scoped agent workflows
- `.agents/profiles/` — named agent profiles for multi-agent collaboration
- `.agents/memories/` — default agent's experiences and user model
- `.agents/SOUL.md` — default agent identity
- `.agents/index.md`, `log.md`
- `AGENTS.md` — workspace entry point with scope definitions, progressive
  loading (SOUL.md, knowledge index), and ten structural guardrails

### USER mode (minimal install only)

Ask the agent to run this skill with a USER scope hint:

> *"Set up AgentFS in USER mode"*

The agent runs:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh --mode user
```

Creates an empty structural skeleton:
- `~/.agents/skills/` — shared agent workflows (initially empty)
- `~/.agents/knowledge/` — shared OKF knowledge bundles (initially empty)
- `~/.agents/index.md`, `log.md`

> **Note:** If you used Path A (full clone), this step is unnecessary —
> the clone already contains the complete structure.

### Sync mode (update existing project AGENTS.md)

When a project's AGENTS.md was created by an older template version,
use sync to bring it up to date:

> *"sync agentfs"* or *"update agentfs"*

The agent performs these steps:

1. **Read the current AGENTS.md** and extract the template version
   from `<!-- agentfs-template-version: X.Y -->` (if absent, assume
   pre-versioning).
2. **Compare** against the current template version in
   `seed-agents-md.sh`.
3. **If versions match** — report "already up to date" and stop.
4. **If versions differ** — extract project-owned sections:
   - Agent Profiles table rows (below `## Agent Profiles`)
   - SPECKIT block content (between `<!-- SPECKIT START/END -->`)
5. **Regenerate** AGENTS.md from the current template via
   `seed-agents-md.sh` (delete the old file first so the script
   generates a fresh one).
6. **Re-inject** the preserved project-owned sections into the
   newly generated file.
7. **Report** what changed (old version → new version, sections
   updated).

### Verification

The agent can verify the setup by running:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/verify-setup.sh [--mode user|project] [--fix]
```

Checks all expected files/directories exist (including the Scope
Definitions section in AGENTS.md for PROJECT mode). With `--fix`,
creates missing ones.

## Structural Guardrails (in AGENTS.md)

The `seed-agents-md.sh` script creates `AGENTS.md` with ten guardrails
(reordered by usage frequency):

1. **Progressive Disclosure** — browse `index.md` before opening files
2. **Memory Scope & Signal Routing** — memories are PROJECT-only;
   decision table mapping NL signals to memory actions; graduation
   path to OKF; agent-specific overrides take priority
3. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
4. **Skill Placement** — default to USER, PROJECT only when explicit
5. **Filesystem Integrity** — link integrity, log currency, content
   file currency, and index currency in a single guardrail
6. **Idempotency** — every skill and workflow must be idempotent
7. **Anti-Sycophancy** — refuse conflicting requests, log overrides
8. **Anti-Daydreaming** — ephemeral session canary name; spot-check
   for context drift; never persisted to AgentFS files
9. **Checkpoints & Resumability** — checkpoint before destructive ops
10. **Git Push Safety** — mandatory 5-step preflight before any
    `git push`: stop → scan → present report → wait for approval → push

## Layer Reference

| Layer | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|-------|-----------|---------------|
| Identity | — | `.agents/SOUL.md` |
| Profiles | — | `.agents/profiles/` |
| Capability | `~/.agents/skills/` | `.agents/skills/` |
| Knowledge | `~/.agents/knowledge/` | — |
| Memories | — | `.agents/memories/` |
| Workspace | — | `AGENTS.md` |

## Supporting Files

- `scripts/scaffold-dotagents.sh` → `load_skill(name: "agentfs-setup/scripts/scaffold-dotagents.sh")`
- `scripts/seed-agents-md.sh` → `load_skill(name: "agentfs-setup/scripts/seed-agents-md.sh")`
- `scripts/verify-setup.sh` → `load_skill(name: "agentfs-setup/scripts/verify-setup.sh")`
- `references/design-spec.md` → `load_skill(name: "agentfs-setup/references/design-spec.md")`

## Companion Skills

- **`agentfs-profile`** — Create named agent profiles under `.agents/profiles/`
- **`goose-agentfs-setup`** — Configure Goose's `CONTEXT_FILE_NAMES` for
  cross-agent context file discovery
- **`hermes-agentfs-setup`** — Configure Hermes's `skills.external_dirs`
  for AgentFS skill discovery


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
