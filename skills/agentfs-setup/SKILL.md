---
name: agentfs-setup
description: >
  Configure Goose for full AgentFS compatibility by scaffolding the
  .agents/ directory tree in USER or PROJECT mode, seeding AGENTS.md
  with eight structural guardrails, and verifying setup integrity.
---

# AgentFS Setup

Scaffold the `.agents/` directory tree and seed foundational files for
AgentFS — a layered, agent-agnostic context structure that works across
AI coding agents.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 2.10 |
| **Modes** | `user` (shared library) · `project` (per-repo context) |
| **Scripts** | `scaffold-dotagents.sh` · `seed-agents-md.sh` · `verify-setup.sh` |
| **Design spec** | [references/design-spec.md](./references/design-spec.md) |

### Two Modes

| Mode | Root | Creates |
|------|------|---------|
| **USER** | `~` | `skills/`, `knowledge/` — shared across projects |
| **PROJECT** | `.` | `skills/`, `profiles/`, `memories/` — per-repo context |

> **Note:** `knowledge/` is USER-scoped only. Projects do NOT get a
> local `knowledge/` directory. `memories/` is PROJECT-scoped only.
> There is no `~/. agents/memories/`.

## Usage

### USER mode (run once per machine)

```bash
bash ~/.agents/skills/agentfs-setup/scripts/scaffold-dotagents.sh --mode user
```

Creates:
- `~/.agents/skills/` — shared agent workflows
- `~/.agents/knowledge/` — shared OKF knowledge bundles
- `~/.agents/index.md`, `log.md`

### PROJECT mode (run once per repo)

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
- `AGENTS.md` — workspace entry point with eight structural guardrails

### Verification

```bash
bash ~/.agents/skills/agentfs-setup/scripts/verify-setup.sh [--mode user|project] [--fix]
```

Checks all expected files/directories exist. With `--fix`, creates
missing ones.

## Structural Guardrails (in AGENTS.md)

The `seed-agents-md.sh` script creates `AGENTS.md` with eight guardrails:

1. **Link Integrity** — no broken, obsolete, or missing links
2. **Log Currency** — append-only `log.md` in reverse chronological order
3. **Content File Currency** — changelogs in reverse chronological order
4. **Progressive Disclosure** — browse `index.md` before opening files
5. **Skill Placement** — default to USER, PROJECT only when explicit
6. **Index Currency** — `skills/index.md` and `profiles/index.md` stay current
7. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
8. **Memory Scope** — memories are PROJECT-only; NL-signal routing for
   experiences vs rules vs preferences; graduation path to OKF

## Layer Reference

| Layer | USER (`~`) | PROJECT (`.`) |
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

## Changelog

| Updated | Change |
|---------|--------|
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
