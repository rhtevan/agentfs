---
name: agentfs-profile
description: >
  create profile, new agent profile, add agent
metadata:
  version: "1.10.0"
  tags: [agentfs, profiles, multi-agent, identity]
---

# Agent FS Profile

Create and manage named agent profiles for multi-agent collaboration
within a DotAgents PROJECT scope setup.

## Overview

In PROJECT scope, the **default agent** uses `.agents/SOUL.md` and
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

- **`agentfs-setup`** must have been run in PROJECT scope first
- **Not available in LITE scope** — LITE scope does not support agent profiles
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

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
