---
name: agentfs-setup
description: >
  Scaffold the AgentFS `.agents/` directory tree in USER or PROJECT mode,
  seed AGENTS.md with scope definitions and thirteen structural guardrails,
  and verify setup integrity. Default mode is PROJECT.
metadata:
  tags: [agentfs, setup, scaffolding, guardrails]
---

# AgentFS Setup

Scaffold the `.agents/` directory tree and seed foundational files for
AgentFS — a layered, agent-agnostic context structure that works across
AI coding agents.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 3.0 |
| **Default mode** | `project` |
| **Modes** | `project` (per-repo context) · `user` (shared library) |
| **Scripts** | `scaffold-dotagents.sh` · `seed-agents-md.sh` · `verify-setup.sh` |
| **Design spec** | [references/design-spec.md](./references/design-spec.md) |

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
- `AGENTS.md` — workspace entry point with scope definitions and nine
  structural guardrails

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

### Verification

The agent can verify the setup by running:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/verify-setup.sh [--mode user|project] [--fix]
```

Checks all expected files/directories exist (including the Scope
Definitions section in AGENTS.md for PROJECT mode). With `--fix`,
creates missing ones.

## Structural Guardrails (in AGENTS.md)

The `seed-agents-md.sh` script creates `AGENTS.md` with thirteen guardrails:

1. **Link Integrity** — no broken, obsolete, or missing links
2. **Log Currency** — append-only `log.md` in reverse chronological order
3. **Content File Currency** — changelogs in reverse chronological order
4. **Progressive Disclosure** — browse `index.md` before opening files
5. **Skill Placement** — default to USER, PROJECT only when explicit
6. **Index Currency** — `skills/index.md` and `profiles/index.md` stay current
7. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
8. **Memory Scope** — memories are PROJECT-only; NL-signal routing for
   experiences vs rules vs preferences; graduation path to OKF
9. **Memory Signal Routing** — decision table mapping NL signals to
   memory actions; agent-specific overrides take priority
10. **Idempotency** — every skill and workflow must be idempotent
11. **Checkpoints & Resumability** — checkpoint before destructive ops
12. **Anti-Sycophancy** — refuse conflicting requests, log overrides
13. **Git Push Safety** — mandatory 5-step preflight before any
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

| Updated | Change |
|---------|--------|
| 2026-07-14 15:22 | v3.2 — AGENTS.md template now includes thirteen guardrails (was nine): added #10 Idempotency, #11 Checkpoints & Resumability, #12 Anti-Sycophancy, #13 Git Push Safety (mandatory 5-step preflight before any git push) |
| 2026-07-13 15:44 | v3.1 — Git init now runs by default in PROJECT mode (calls init-git.sh at project root); .gitignore no longer excludes .agents/memories/ (full audit trail); updated for agentfs-eval compatibility |
| 2026-07-10 18:07 | v3.0 — PROJECT is now the default mode; added canonical Scope Definitions section; documented two USER setup paths (full clone vs minimal install); added Prerequisites section; AGENTS.md template now includes Scope Definitions; nine guardrails (was eight) |
| 2026-07-08 13:38 | v2.10 — Recreated SKILL.md after accidental deletion; reflects memory redesign (knowledge USER-only, memories PROJECT-only, 8 guardrails, updated layer reference) |
| 2026-07-07 16:52 | v2.9 — Added Cross-Agent Context Discovery guardrail (§7) to AGENTS.md template |
| 2026-06-30 23:49 | v2.7 — Expanded guardrail §2: explicit USER/PROJECT/sub-bundle scope; mandatory skill/concept change logging |
| 2026-06-30 23:36 | v2.6 — Changelog tables now use `Updated` header and `YYYY-MM-DD HH:MM` timestamps |
| 2026-06-30 23:31 | v2.5 — Renamed index column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM` |
| 2026-06-30 23:16 | v2.4 — Added Index Currency guardrail (§6); expanded Profiles Layer |
| 2026-06-30 18:30 | v2.3 — Added `profiles/index.md`; fixed link targets |
| 2026-06-30 17:30 | v2.2 — Idempotent re-run verify `--fix` mode |
| 2026-06-30 15:30 | v2.1 — Added Agent Profiles table to AGENTS.md |
| 2026-06-30 14:00 | v2.0 — Renamed modes; `memory/` → `memories/`; `roles/` → `profiles/`; added SOUL.md, USER.md, MEMORY.md |
| 2026-06-26 22:00 | v1.1 — Added optional git/spec-kit init; verify script |
| 2026-06-26 14:00 | v1.0 — Initial design: USER/PROJECT dual-mode |
