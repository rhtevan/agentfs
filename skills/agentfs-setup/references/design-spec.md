# DotAgents Unified Design Specification

## Core Philosophy

Strict separation of **Identity**, **Capabilities**, **Semantic Context**,
and **Memories** — unified under a single `.agents/` tree that acts as the
agent-facing "LLM-wiki."

Two modes serve different scopes:

| Mode | Root | Scope | Spec-kit |
|------|------|-------|----------|
| **USER** | `~` | Shared skills & knowledge visible across projects and agents | Not involved |
| **PROJECT** | `.` (repo root) | Per-project agent context with multi-agent collaboration | Optional, independent |

## Prompt Stacking Order

When an agent assembles its system prompt from `.agents/` resources,
the intended stacking order is:

```
1. SOUL.md           ← "Who am I?" — agent identity (human-authored)
2. AGENTS.md         ← "How does this project work?" — project rules (human-authored)
3. skills/           ← Available capabilities (shared across agents)
4. knowledge/        ← Domain context (USER-scoped, shared across projects)
5. MEMORY.md         ← "What have I learned?" — project/env facts (agent-learned)
6. USER.md           ← "Who are they?" — user profile (agent-learned)
```

Items 1, 5, 6 are per-agent (default agent uses `.agents/` root;
named agents use `.agents/profiles/<name>/`).
Items 2, 3 are shared across all agents in the project.
Item 4 (knowledge) is USER-scoped (`~/.agents/knowledge/`) — shared across all projects and agents.

## USER Mode — File Structure

```text
~/
└── .agents/
    ├── index.md                             # Directory listing (OKF entry point)
    ├── log.md                               # Append-only activity tracker
    │
    ├── skills/                              # Capability Layer (Agent Skills)
    │   ├── index.md                         # Skills directory
    │   └── <skill-name>/
    │       ├── SKILL.md
    │       └── <bundled_resources>
    │
    └── knowledge/                           # Semantic Context Layer (OKF)
        ├── index.md
        └── <topic>/
            └── <concept>.md                 # YAML frontmatter: type required
```

**Purpose:** A shared library of skills and knowledge that spans across
all projects and is visible to any agent. No agent identity, no memories,
no profiles — purely a capability and knowledge store.

**Excluded from USER mode:**
- `SOUL.md` — Agent identity is project-scoped or agent-specific
- `profiles/` — Multi-agent collaboration is project-scoped
- `memories/` — Learned context is agent-scoped within a project
- `AGENTS.md` — Workspace entry point is per-repo

## PROJECT Mode — File Structure

```text
./ (Repository Root)
├── AGENTS.md                                # Workspace entry point
│
├── .agents/                                 # The DotAgents Directory
│   ├── index.md                             # Directory listing (OKF entry point)
│   ├── log.md                               # Append-only activity tracker
│   ├── SOUL.md                              # Default agent identity (human-authored)
│   │
│   ├── profiles/                            # Named Agent Profiles
│   │   ├── index.md                         # Profile directory listing
│   │   └── <agent-name>/                    # Created by agentfs-profile skill
│   │       ├── SOUL.md                      # This agent's identity
│   │       └── memories/
│   │           ├── USER.md                  # This agent's model of the user
│   │           └── MEMORY.md                # This agent's learned project facts
│   │
│   ├── skills/                              # Capability Layer (Agent Skills)
│   │   ├── index.md                         # Skills directory
│   │   └── <skill-name>/                    # Shared across all agents
│   │       ├── SKILL.md
│   │       └── <bundled_resources>
│   │
│   └── memories/                            # Default Agent Memories
│       ├── USER.md                          # Default agent's model of the user
│       └── MEMORY.md                        # Default agent's project experiences
│
├── .specify/                                # Spec-kit engine (if used)
│   ├── templates/
│   ├── scripts/bash/
│   ├── memory/
│   │   └── constitution.md
│   ├── feature.json
│   └── init-options.json
│
└── specs/                                   # Spec-kit output (if used)
    └── <feature-branch-name>/
        ├── spec.md
        ├── plan.md
        ├── tasks.md
        └── ...
```

## Multi-Agent Collaboration

PROJECT mode supports multiple agents working together on the same project.

### Shared layers (all agents see these)
- **`skills/`** — Project-scoped agent workflows
- **`AGENTS.md`** — Project rules and conventions
- Knowledge bundles live at `~/.agents/knowledge/` (USER scope, shared across projects)

### Per-agent layers (scoped to each agent)
- **`SOUL.md`** — Agent identity and personality (human-authored)
- **`memories/USER.md`** — The agent's model of the user (agent-learned)
- **`memories/MEMORY.md`** — The agent's learned project/environment facts (agent-learned)

### Default agent vs named profiles

The **default agent** uses files at the `.agents/` root:
- `.agents/SOUL.md`
- `.agents/memories/USER.md`
- `.agents/memories/MEMORY.md`

**Named agents** get their own profile under `.agents/profiles/<name>/`:
- `.agents/profiles/<name>/SOUL.md`
- `.agents/profiles/<name>/memories/USER.md`
- `.agents/profiles/<name>/memories/MEMORY.md`

Profiles are created by the companion `agentfs-profile` skill,
which scaffolds the directory structure and seeds template files.

Each profile is equivalent to a distinct **ROLE** — it defines who the
agent is, what it remembers, and how it models the user. All roles
share the same skills and knowledge, and all follow the same guardrails
defined in `AGENTS.md` at the project root. This ensures coherent
collaboration: a "verifier" agent and a "coder" agent both see the
same project rules but bring different expertise and perspectives.

This design is **compatible with Hermes Agent out of the box**:

| Hermes Agent | DotAgents Profile |
|--------------|-------------------|
| `~/.hermes/SOUL.md` | `.agents/profiles/<name>/SOUL.md` |
| `~/.hermes/memories/USER.md` | `.agents/profiles/<name>/memories/USER.md` |
| `~/.hermes/memories/MEMORY.md` | `.agents/profiles/<name>/memories/MEMORY.md` |

The key difference: Hermes profiles are user-level (each is a separate
Hermes instance), while DotAgents profiles are project-level (multiple
agents collaborate on the same project with shared capabilities).

## Layer Descriptions

### 1. Workspace Layer — AGENTS.md (PROJECT only)
Entry point for coding agents. Contains operational guardrails, build/test
commands, code style. Points to `.agents/`. Carries `<!-- SPECKIT START/END -->`
markers for Spec-kit's agent-context extension to manage automatically.

Defines eight structural guardrails that all agents MUST follow:
1. **Link Integrity** — no broken, obsolete, or missing links
2. **Log Currency** — append-only `log.md` in reverse chronological order
3. **Content File Currency** — changelogs in reverse chronological order
4. **Progressive Disclosure** — browse `index.md` before opening files
5. **Skill Placement** — default to USER, PROJECT only when explicit
6. **Index Currency** — `skills/index.md` and `profiles/index.md` MUST
   stay current whenever skills or profiles are created, renamed, moved,
   or deleted; entries MUST include an ISO 8601 timestamp
   (`YYYY-MM-DD HH:MM`) and be sorted newest-first (reverse
   chronological order)
7. **Cross-Agent Context Discovery** — read CLAUDE.md, .cursorrules, etc.
8. **Memory Scope** — memories are PROJECT-only; NL-signal routing;
   graduation path to OKF

Includes an **Agent Profiles** table — an agent-agnostic registry of all
profiles in the project:

```markdown
## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |
| hermes | [SOUL](./.agents/profiles/hermes/SOUL.md) | [memories/](./.agents/profiles/hermes/memories/MEMORY.md) |
```

The `default` row is seeded by `seed-agents-md.sh` during initial setup.
Named profile rows are appended automatically by `create-profile.sh`
(from `agentfs-profile` skill). This makes profiles discoverable by
any agent reading `AGENTS.md` — framework-independent.

### 2. Navigation & Log — .agents/ root
- **index.md** — OKF entry point; directory listing; no YAML frontmatter.
- **log.md** — Append-only; ISO 8601 timestamp headings (`## YYYY-MM-DD HH:MM`); tracks activity.
  Standard format:
  - Title: `# Directory Update Log`
  - Comment: `<!-- Append-only. Newest entries at top. -->`
  - Headings: `## YYYY-MM-DD HH:MM`
  - Entries: `- ` (dash prefix)

### 3. Identity Layer — SOUL.md
Human-authored agent personality and communication defaults. Analogous to
Hermes Agent's `SOUL.md`. The default agent's SOUL lives at `.agents/SOUL.md`;
named profiles have their own at `.agents/profiles/<name>/SOUL.md`.

### 4. Profiles Layer — .agents/profiles/ (PROJECT only)

The `profiles/` directory serves two complementary purposes:

**1. Multi-Agent Collaboration Hub**
Named agent profiles enable multiple AI agents to collaborate on the same
project while maintaining distinct identities and memory spaces. Each
profile is a self-contained agent persona with its own SOUL.md (identity)
and `memories/` directory (USER.md + MEMORY.md). This design is
**compatible with Hermes Agent out of the box** — the file structure maps
directly to Hermes's own profile concept (`SOUL.md`, `memories/USER.md`,
`memories/MEMORY.md`), making it possible to use DotAgents profiles with
Hermes without adaptation.

**2. ROLE-Based Agent Specialization**
Each profile is equivalent to defining a different **ROLE**. A profile
carries its own:
- **Identity** (`SOUL.md`) — who the agent IS, its tone, expertise, and
  behavioral defaults
- **Memory** (`memories/MEMORY.md`) — what the agent has learned about
  the project from its perspective
- **Target user model** (`memories/USER.md`) — the agent's understanding
  of the user it serves (which may differ per role)

All profiles in a project follow the **same structural guardrails**
defined in the project-root `AGENTS.md`. While each profile has its own
identity and memories, every agent operating under any profile MUST
adhere to the link integrity, log currency, index currency, progressive
disclosure, and skill placement rules codified in `AGENTS.md`. This
ensures consistent, predictable behavior across all agents collaborating
on the project.

Skills remain **shared** across all profiles — only identity and
memories are per-profile. Knowledge lives at `~/.agents/knowledge/`
(USER scope) and is shared across all projects and agents. This allows specialized agents
(e.g., a "verifier" role focused on testing, a "researcher" role focused
on information gathering) to leverage the same capability set while
maintaining distinct perspectives.

Created and managed by the `agentfs-profile` skill.

### 5. Capability Layer — .agents/skills/
Agent Skills format. Each skill = folder with SKILL.md + optional bundled
resources. Progressive disclosure via metadata → body → resources.
Shared across all agents. Present in both USER and PROJECT modes.

### 6. Semantic Context Layer — ~/.agents/knowledge/ (USER only)
Open Knowledge Format. File path = concept identity. Every file requires
YAML frontmatter with `type` field. Markdown links form a knowledge graph.
Shared across all agents and projects. Present in USER mode only —
projects do NOT get a local `knowledge/` directory.

### 7. Memories Layer — .agents/memories/ (PROJECT only)
Agent-authored files capturing learned context:
- **USER.md** — The agent's evolving model of the user (role, preferences,
  interests, communication style). Updated proactively during conversations.
- **MEMORY.md** — Project-specific experiences and observations (build
  quirks, discovered patterns, tool configurations). Records experiences,
  not rules — rules belong in `AGENTS.md`.

Each named profile has its own `memories/` subdirectory.

### 8. Planning Layer — specs/ (PROJECT only, managed by Spec-kit)
Full SDD lifecycle artifacts from Spec-kit. One subdirectory per feature.
This directory lives at the **repo root** (not inside `.agents/`) and is
fully managed by the `specify` CLI. DotAgents does not create, move, or
override this directory.

## Spec-kit Coexistence (PROJECT mode)

Spec-kit is an independent tool that manages its own directories:
- `.specify/` — engine room (templates, scripts, config, constitution)
- `specs/` — feature output (spec, plan, tasks, etc.)

DotAgents and Spec-kit coexist as **siblings**, not parent-child:

```text
./
├── .agents/      ← DotAgents (this skill)
├── .specify/     ← Spec-kit engine
└── specs/        ← Spec-kit output
```

No path overrides, no `sed` patches, no create-new-feature.sh wrappers.
Spec-kit's own integration system (`specify init --integration <agent>`)
handles slash command installation. The only connection is the
`<!-- SPECKIT START/END -->` markers in `AGENTS.md` that Spec-kit's
agent-context extension uses to write the active plan reference.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-08 13:38 | v2.10 — Memory redesign: knowledge USER-only, memories PROJECT-only, 8 guardrails, MEMORY.md="experiences", removed `.agents/knowledge/` from PROJECT tree |
| 2026-06-30 23:49 | v2.7 — Expanded guardrail §2: explicit USER/PROJECT/sub-bundle scope; mandatory skill/concept change logging; standardized `log.md` format |
| 2026-06-30 23:36 | v2.6 — Changelog tables now use `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v2.5 — Renamed index column `Added` → `Updated`; timestamp precision increased to `YYYY-MM-DD HH:MM`; log.md headings now use timestamp format |
| 2026-06-30 23:16 | v2.4 — Added Index Currency guardrail (§6); expanded Profiles Layer narrative with dual-purpose (multi-agent hub + ROLE-based specialization); added Hermes compatibility table; profiles/index.md schema now includes Identity + Memories + Updated columns; skills/index.md uses Updated column; all entries sorted newest-first |
| 2026-06-30 18:30 | v2.3 — Added `profiles/index.md`; fixed `profiles/` and `memories/` link targets across all trees and examples |
| 2026-06-30 17:30 | v2.2 — Idempotent re-run: verify `--fix` mode repairs missing files/dirs without overwriting; link integrity checks; profile completeness checks; `skills/index.md` replaces `.gitkeep` |
| 2026-06-30 15:30 | v2.1 — Added Agent Profiles table to AGENTS.md workspace layer; agent-agnostic profile discovery |
| 2026-06-30 14:00 | v2.0 — Renamed USER mode → USER mode; `memory/` → `memories/`; `roles/` → `profiles/`; added SOUL.md, USER.md, MEMORY.md; removed constitution.md (Spec-kit owns it); added multi-agent collaboration design; added prompt stacking order; introduced `agentfs-profile` companion skill |
| 2026-06-26 22:00 | v1.1 — Added optional git/spec-kit init; verify script opt-in flags; fixed index.md links; fixed `((PASS++))` bash arithmetic bug |
| 2026-06-26 14:00 | v1.0 — Initial design: USER/PROJECT dual-mode, Spec-kit coexistence |
