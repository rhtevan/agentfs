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

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical —
all guardrails, skills, and documentation reference them.

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

> **Rule of thumb:** If the agent says "USER scope", it means
> `~/.agents/`. If it says "PROJECT scope", it means `./.agents/`
> relative to the current repository root.

## Installation Paths

USER scope (`~/.agents/`) must be set up before PROJECT scope can work,
since PROJECT mode skills and scripts are typically invoked from the
USER-scoped skill library.

### Path A: Full Install (recommended)

Clone the published AgentFS repository directly into `~/.agents/`:

```bash
git clone https://github.com/rhtevan/agentfs.git ~/.agents
```

This gives the user the complete skill library, knowledge bundles,
and structural scaffolding — ready to use immediately.

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
3. Ask the agent to run the `agentfs-setup` skill with USER scope:
   > *"Set up AgentFS in USER mode"*

   The agent loads the skill, recognises the USER scope hint, and
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

### After USER Setup: PROJECT Setup

In any git repository, ask the agent to run the `agentfs-setup` skill:

> *"Set up AgentFS for this project"*

Since PROJECT is the default mode, no additional scope hint is needed.
The agent scaffolds `.agents/` and creates `AGENTS.md` at the repo root.

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

The profile structure uses a well-known convention (`SOUL.md`,
`memories/USER.md`, `memories/MEMORY.md`) that maps naturally to any
agent framework's native profile concept. Agent-specific compatibility
details belong in the corresponding agent setup skill (e.g.,
`hermes-agentfs-setup`, `goose-agentfs-setup`).

## Layer Descriptions

### 1. Workspace Layer — AGENTS.md (PROJECT only)
Entry point for coding agents. Contains operational guardrails, build/test
commands, code style. Points to `.agents/`. Carries `<!-- SPECKIT START/END -->`
markers for Spec-kit's agent-context extension to manage automatically.

Defines nine structural guardrails (reordered by usage frequency):
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
8. **Checkpoints & Resumability** — checkpoint before destructive ops
9. **Git Push Safety** — mandatory 5-step preflight before any
   `git push`: stop → scan → present report → wait for approval → push

Includes an **Agent Profiles** table — an agent-agnostic registry of all
profiles in the project:

```markdown
## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |
| coder | [SOUL](./.agents/profiles/coder/SOUL.md) | [memories/](./.agents/profiles/coder/memories/MEMORY.md) |
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
Human-authored agent personality and communication defaults. The default
agent's SOUL lives at `.agents/SOUL.md`;
named profiles have their own at `.agents/profiles/<name>/SOUL.md`.

### 4. Profiles Layer — .agents/profiles/ (PROJECT only)

The `profiles/` directory serves two complementary purposes:

**1. Multi-Agent Collaboration Hub**
Named agent profiles enable multiple AI agents to collaborate on the same
project while maintaining distinct identities and memory spaces. Each
profile is a self-contained agent persona with its own SOUL.md (identity)
and `memories/` directory (USER.md + MEMORY.md). The profile structure
uses a well-known convention (`SOUL.md`, `memories/USER.md`,
`memories/MEMORY.md`) that maps naturally to any agent framework's
native profile concept.

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

## Evaluation

AgentFS enforces guardrails through prescriptive rules in `AGENTS.md`,
but prescriptive rules alone are insufficient — they rely on the
agent's compliance, which is undermined by the very AI model flaws
(hallucination, stochasticity, sycophancy) the guardrails aim to
control. The `agentfs-eval` skill closes this gap with assertive
verification.

### Challenges

**Safe Agent Actions:**
- **Idempotency** — skills and workflows must produce the same
  filesystem state when re-run. Without verification, agents may
  append duplicates, create conflicting files, or corrupt state.
- **Resumability** — interrupted agent sessions can leave partial
  state. Without checkpoints, there's no way to detect or recover.
- **Auditability** — `log.md` records what the agent claims happened,
  but nothing cross-references claims against actual filesystem
  changes. The audit trail is only as trustworthy as the agent.

**AI Model Flaws:**
- **Hallucination** — agents may create MEMORY.md entries referencing
  files, functions, or APIs that don't exist in the project.
- **Stochasticity** — the same skill invoked twice may produce
  different directory structures, different frontmatter formats,
  or different log entry styles.
- **Sycophancy** — agents may silently comply with user requests
  that violate guardrails (e.g., creating `~/.agents/memories/`
  when the user asks, despite scope rules forbidding it).

### Three-Layer Verification Architecture

The eval uses three progressively deeper verification layers, each
with a fundamentally different paradigm:

| Layer | Paradigm | LLM? | Assertions |
|-------|----------|:----:|------------|
| **L1: Structural** | Filesystem assertions | No | Link integrity, log monotonicity, index completeness, frontmatter validity, scope correctness, changelog monotonicity, orphan detection |
| **L2: Behavioral** | Forensic evidence correlation | No | Action-log correlation, log-git timestamp alignment, scope leakage, idempotency spot-check, rule-in-memory heuristic |
| **L3: Semantic** | Constrained LLM classification | Yes | Memory content classification, reference verification, sycophancy detection, skill accuracy |

**Key design choices:**
- Layer 3 uses closed-ended classification questions with majority
  voting, not open-ended LLM judgment — resisting the very flaws
  being evaluated
- No golden test cases — eval tests real workspace content
- Checks gracefully degrade to N/A when evidence is insufficient
  (e.g., fresh projects with no behavioral history)
- Git provides tamper-resistant forensic evidence for Layer 2
  (initialized by default in PROJECT mode)

### Maturity Levels

| Level | Name | Requirements |
|-------|------|--------------|
| L0 | Absent | No `.agents/` directory |
| L1 | Scaffolded | `.agents/` exists with basic structure |
| L2 | Structurally Sound | All Layer 1 assertions pass |
| L3 | Behaviorally Safe | Layer 1 + Layer 2 assertions pass |
| L4 | Semantically Accurate | All three layers pass |
| L5 | Self-Correcting | Agent detects and fixes its own violations |

### Git as Audit Infrastructure

`agentfs-setup` initializes git in the project directory (parent of
`.agents/`) by default in PROJECT mode. The `.gitignore` tracks
everything under `.agents/` including `memories/` — privacy is the
user's decision at push time, not gitignore time. Git provides:

- Content-level diffing for action-log correlation (L2)
- Tamper-resistant history (log.md can be edited; git history can't)
- Free checkpoint/revert via `git checkout`
- Per-file change attribution across sessions

### L3 → L2 Graduation

Over time, patterns observed in Layer 3 semantic results can be
codified as Layer 2 deterministic heuristics (e.g., a grep check
for imperative language in MEMORY.md). This graduation is
**human-driven** — the eval skill is updated manually after a human
observes recurring patterns in eval reports. Eval never modifies
itself.

### Eval-Driven Guardrails

The evaluation work motivated three additional guardrails (now numbered
#6 Idempotency, #7 Anti-Sycophancy, #8 Checkpoints & Resumability
after the v3.3 consolidation from 13 → 9 guardrails):

- **Idempotency** — skills must be re-runnable safely (existence
  checks, upsert patterns, no append-without-dedup)
- **Checkpoints & Resumability** — record state before destructive
  operations in `.agents/.checkpoint`
- **Anti-Sycophancy** — agent must flag conflicts with existing
  guardrails, not silently comply; overrides logged with `[OVERRIDE]`

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-14 17:49 | v3.3 — Consolidated guardrails from 13 to 9 (reordered by usage frequency); merged Memory Scope + Signal Routing; merged Link/Log/Changelog/Index into Filesystem Integrity; Quick Orientation now includes SOUL.md and knowledge index; updated eval-driven guardrails section numbering |
| 2026-07-13 15:45 | v3.1 — Added Evaluation section: three-layer verification architecture, maturity levels L0–L5, git as audit infrastructure, L3→L2 graduation, guardrails #10–12; git init now default in PROJECT mode; memories/ no longer excluded from .gitignore |
| 2026-07-10 18:07 | v3.0 — Added canonical Scope Definitions section (USER=`~/.agents/`, PROJECT=`./.agents/`); added Installation Paths section (Full vs Minimal USER setup); PROJECT is now the primary skill workflow |
| 2026-07-10 16:10 | v2.11 — Added Guardrail #9 (Memory Signal Routing): NL signal → route decision table with Executor column; two-layer override architecture (agent-agnostic AGENTS.md + agent-specific instructions.md); skill creation defaults to USER scope; harvest signal routes to skill-harvest or okf-bundle-harvest; priority-based runtime resolution via tool availability check |
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
