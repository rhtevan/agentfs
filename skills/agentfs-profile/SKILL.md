---
name: agentfs-profile
description: >
  Create named agent profiles under .agents/profiles/ in PROJECT mode.
  Each profile gets its own SOUL.md (identity), memories/USER.md (user model),
  and memories/MEMORY.md (project experiences). Requires agentfs-setup to
  have been run in PROJECT mode first. Skills remain shared across all
  agents at the project level.
metadata:
  tags: [agentfs, profiles, multi-agent, identity]
---

# Agent FS Profile

Create and manage named agent profiles for multi-agent collaboration
within a DotAgents PROJECT mode setup.

## Overview

In PROJECT mode, the **default agent** uses `.agents/SOUL.md` and
`.agents/memories/` at the root level. When multiple agents need to
collaborate on the same project, each additional agent gets its own
**named profile** under `.agents/profiles/<name>/`.

### What a profile contains

```text
.agents/profiles/<agent-name>/
├── SOUL.md                    # Agent identity (human-authored)
└── memories/
    ├── USER.md                # Agent's model of the user (agent-learned)
    └── MEMORY.md              # Agent's learned project facts (agent-learned)
```

### What is shared (NOT in profiles)

Skills are project-scoped and shared across all agents:
- `.agents/skills/` — all agents use the same skills
- Knowledge bundles live at `~/.agents/knowledge/` (USER scope, shared across projects)

## Prerequisites

- **`agentfs-setup`** must have been run in PROJECT mode first
  (`.agents/profiles/` directory must exist).

## Usage

### From an agent console

The agent should run the script with the profile name:

```bash
bash <skill-dir>/scripts/create-profile.sh <profile-name> <project-root>
```

Examples:

```bash
# Create a profile for a specialized coding agent
bash <skill-dir>/scripts/create-profile.sh coder .

# Create a profile for a research agent
bash <skill-dir>/scripts/create-profile.sh researcher .
```

### Natural-language signals

When the user says things like:
- "add an agent called coder"
- "set up a researcher profile"

Extract the profile name and run the script.

## After Creation

1. **AGENTS.md updated** — The script automatically registers the new
   profile in the **Agent Profiles** table in `AGENTS.md`. Any agent
   reading `AGENTS.md` can discover the profile and navigate to its
   SOUL and memories. The registration is idempotent — running the
   script again for the same profile name skips the table update.
2. **`profiles/index.md` updated** — The script registers the profile
   in `.agents/profiles/index.md` with links to both `SOUL.md` and
   `memories/MEMORY.md`, plus a timestamp. Entries are sorted newest-
   first (reverse chronological order) per the Index Currency guardrail.
3. **Edit `SOUL.md`** — The user should customize the agent's identity
   and personality in the profile's `SOUL.md`.
4. **Memories auto-populate** — `USER.md` and `MEMORY.md` are seeded
   with comment headers. The agent fills them in during conversations.
5. **Skills** — No per-profile setup needed. All agents share
   `.agents/skills/`. Knowledge lives at `~/.agents/knowledge/` (USER scope).

## AGENTS.md Integration

When a profile is created, the script appends a row to the **Agent
Profiles** table in `AGENTS.md`:

```markdown
## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |
| coder | [SOUL](./.agents/profiles/coder/SOUL.md) | [memories/](./.agents/profiles/coder/memories/MEMORY.md) |
```

This makes profiles **discoverable by any agent** that reads `AGENTS.md`
— agent-agnostic and framework-independent.

**Prerequisites for auto-registration:**
- `AGENTS.md` must exist at the project root
- `AGENTS.md` must contain an `## Agent Profiles` section (created by
  `seed-agents-md.sh` from the `agentfs-setup` skill)

If either is missing, the profile is still created but the AGENTS.md
registration step is silently skipped.

## Compatibility

The profile structure uses a well-known convention (`SOUL.md`,
`memories/USER.md`, `memories/MEMORY.md`) that maps naturally to any
agent framework's native profile concept. Agent-specific compatibility
details belong in the corresponding agent setup skill (e.g.,
`hermes-agentfs-setup`, `goose-agentfs-setup`).

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-08 13:38 | v1.8 — Updated MEMORY.md template to "Project Experiences" with scope/NL-signal guidance; removed `.agents/knowledge/` references (knowledge is USER-scoped) |
| 2026-07-01 00:07 | v1.7 — `create-profile.sh` now updates profile count in `profiles/index.md` summary line |
| 2026-06-30 23:36 | v1.6 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v1.5 — Renamed index column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM`; log.md entries use timestamp headings |
| 2026-06-30 23:16 | v1.4 — `profiles/index.md` schema now has Identity + Memories + Updated columns; entries inserted newest-first (reverse chronological); `create-profile.sh` updated to match; After Creation section expanded |
| 2026-06-30 18:30 | v1.3 — `create-profile.sh` registers profiles in `profiles/index.md`; `memories/` links now point to `memories/MEMORY.md` |
| 2026-06-30 17:45 | v1.2 — `create-profile.sh` now appends to `.agents/log.md` per the Log Currency guardrail |
| 2026-06-30 15:30 | v1.1 — Auto-register profiles in AGENTS.md Agent Profiles table; idempotent duplicate detection |
| 2026-06-30 14:00 | v1.0 — Initial skill: create named agent profiles with SOUL.md + memories/ |
