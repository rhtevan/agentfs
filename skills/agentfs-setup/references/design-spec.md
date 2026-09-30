# DotAgents Unified Design Specification

## Core Philosophy

Strict separation of **Identity**, **Capabilities**, **Semantic Context**,
and **Memories** — unified under a single `.agents/` tree that acts as the
agent-facing "LLM-wiki."

Two modes serve different scopes:

| Scope | Root | Description | Spec-kit |
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
| `plugins/` | ✅ shared | ✅ project-specific |
| `scripts/` | ✅ shared | ❌ never |
| `SOUL.md` | ❌ never | ✅ agent identity |
| `AGENTS.md` | ❌ never | ✅ (at repo root `./`) |
| `index.md` | ✅ | ✅ |
| `log.md` | ✅ | ✅ |

> **Rule of thumb:** If the agent says "USER scope", it means
> `~/.agents/`. If it says "PROJECT scope", it means `./.agents/`
> relative to the current repository root.

## Installation Paths

USER scope (`~/.agents/`) must be set up before PROJECT scope can work,
since PROJECT scope skills and scripts are typically invoked from the
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
   > *"Set up AgentFS in USER scope"*

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

Since PROJECT is the default scope, no additional scope hint is needed.
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

## USER Scope — File Structure

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
    ├── knowledge/                           # Semantic Context Layer (OKF)
    │   ├── index.md
    │   └── <topic>/
    │       └── <concept>.md                 # YAML frontmatter: type required
    │
    ├── plugins/                             # Goose Hooks Plugins
    │   └── <plugin-name>/
    │       ├── plugin.json
    │       ├── hooks/
    │       │   └── hooks.json
    │       └── scripts/
    │           └── <hook-scripts>
    │
    └── scripts/                             # AGENTS-specific scripts
        └── <script>.sh                      # Referenced directly from AGENTS.md
```

**Purpose:** A shared library of skills, knowledge, plugins, and scripts
that spans across all projects and is visible to any agent. No agent
identity, no memories, no profiles — purely a capability and knowledge store.

**Excluded from USER scope:**
- `SOUL.md` — Agent identity is project-scoped or agent-specific
- `profiles/` — Multi-agent collaboration is project-scoped
- `memories/` — Learned context is agent-scoped within a project
- `AGENTS.md` — Workspace entry point is per-repo

## PROJECT Scope — File Structure

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

PROJECT scope supports multiple agents working together on the same project.

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

**Template versioning:** Every generated AGENTS.md carries a version stamp
`<!-- agentfs-template-version: X.Y -->` on line 1. The `agentfs-setup`
skill's `--sync` mode compares this against the current template version
and regenerates template-owned sections while preserving project-owned
sections (Agent Profiles table, SPECKIT block).

**Section ownership:** AGENTS.md is divided into two zones:
- **Template-owned** (everything above `<!-- PROJECT-OWNED -->`) —
  regenerated by `--sync`; agents and users MUST NOT edit directly.
  Changes go through the seed template (`seed-agents-md.sh`).
- **Project-owned** (everything below the marker) — Agent Profiles
  table and SPECKIT block; preserved across sync operations.

**Signal Dispatch architecture (v6.0.0):**

All signal dispatch is unified under the `hey` prefix. When a user
message starts with `hey`, the agent matches keywords against the
Signal Dispatch table in AGENTS.md and routes accordingly:
- **Skill/knowledge dispatch** — `hey <keywords>` → `search_nodes`
  → `load_skill` or load OKF concept file
- **Memory management** — `hey remember/forget/check notes` → read/write
  `MEMORY.md`
- **Preference management** — `hey I prefer` → `USER.md`
- **Guardrail proposals** — `hey always/never` → propose AGENTS.md rule

The `hey` prefix is deterministically enforced by the `signal-dispatch`
plugin (`~/.agents/plugins/signal-dispatch/`), which uses a Goose
`PreToolUse` hook to block non-dispatch tool calls when a `hey`-prefixed
prompt is detected. This converts the highest-risk prose instruction
into deterministic code — the agent literally cannot use other tools
until it completes the dispatch.

**Skill-routed signals** continue to live in each SKILL.md's `description`
frontmatter field as signal phrases. They are aggregated into
`~/.agents/skills/index.md` by the `skill-index` skill (Description
column) as defense-in-depth.

**Scope Definitions** are no longer inlined in AGENTS.md. They are
relocated to `.agents/index.md` for progressive disclosure, reducing
the system prompt footprint by ~400 bytes.

**README sync rule:** When AgentFS design, guardrails, skills schema,
or template structure changes, the README (`~/.agents/README.md`) MUST
be updated in the same commit or session. This is a hard requirement,
not advisory — unlike the soft README staleness check in Guardrail #10.

**Rule format (v7.2+):** Every rule MUST be (1) numbered with
`### N. Name` heading, (2) written in `**When:**` / `**Do:**` prose
format. Rules are ordered by operational frequency (most-triggered
first). No severity annotations — ordering IS priority.

**Template versioning policy:** Follows semantic versioning:

| Bump | When | Examples |
|------|------|----------|
| **MAJOR** (X.0.0) | Breaking change — rule format, section restructure, dispatch architecture | v6→v7: table→prose |
| **MINOR** (x.Y.0) | Rules added, removed, merged, reordered. New sections. Behavioral change. | v7.2.0: 10→8 rules |
| **PATCH** (x.y.Z) | Clarification, wording fix, resilience. No rule count/order change. | v7.2.1: git push gate |

**AGENTS.md v7.2 rule structure:** 8 numbered rules (reduced from
10 in v7.0, 17 in v5.x, consolidated from v6.0's 10). Behavioral
norms (no validation phrases, no assumed inputs, risk naming) live
in SOUL.md Principles. Rules enforce operational concerns only:

1. **Signal Dispatch** — route `hey`-prefixed messages per dispatch table
2. **Pre-Flight** — enumerate steps and obligations before multi-step tasks
3. **Post-Write** — run `post-write.sh` after `.agents/` writes
4. **Session Canary** — session continuity check; read USER.md on start
5. **Conflict Resolution** — state what changed on reversal; `[OVERRIDE]` for rule conflicts
6. **Checkpoint** — checkpoint before destructive `.agents/` ops
7. **Scope Rules** — memories PROJECT-only; skills default USER; graduation to OKF
8. **Path Hygiene** — use `~` not `/home/<user>/` in output

**AGENTS.md v6.0.0 rule structure (historical):** 10 rules,
organized by lifecycle phase.

The underlying design guardrails remain:
- 🔄 **Idempotency** — every skill and workflow must be idempotent
- ⚖️ **Anti-Sycophancy** — refuse conflicting requests, log overrides
- ⛔ **Git Push Safety** — mandatory preflight before any `git push`

### Guardrail Type System

Each guardrail is classified by its enforcement mechanism:

| Type | Marker | Trigger | Agent Behavior | Key Action Pattern |
|------|--------|---------|---------------|--------------------|
| **Gate** | ⛔ | Specific action point | STOP, complete checklist, then proceed | `STOP → [verb chain] → RESUME/WAIT` |
| **Rule** | ⚖️ | Decision point | Choose correctly from constrained options | `Default X; exception when Y` |
| **Habit** | 🔄 | Continuous / periodic | Maintain behavioral norm throughout session | `[trigger]: action` |

Three types map to three fundamental flow-control primitives:
Gate = checkpoint, Rule = branch, Habit = feedback loop.

Two additional patterns (Trigger and Invariant) were considered
during design but collapse into existing types at the agent
behavioral level:
- **Trigger** (react to detected condition) collapses into **Rule** —
  both are conditional responses; a Rule is a Trigger with a default
  path, a Trigger is a Rule without one.
- **Invariant** (property that must always hold) collapses into
  **Habit** — the agent enforces both through ongoing vigilance with
  no distinct structural mechanism.

Only guardrails with proven multi-step failure modes receive the Gate
type. Overusing Gate dilutes its interrupt force.

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
Human-authored agent identity. Uses a hybrid structure: a short prose
preamble ("who you are") followed by structured **Principles** as
bulleted items with bold labels. Principles represent self-discipline —
values, policies, and standards the agent internalizes. This structure
gives weaker models individually parseable constraints while stronger
models absorb the identity naturally.

The default agent's SOUL lives at `.agents/SOUL.md`;
named profiles have their own at `.agents/profiles/<name>/SOUL.md`.

**SOUL vs AGENTS separation:** SOUL contains self-discipline (what the
agent would follow even without AGENTS.md). AGENTS contains externally
enforced rules (operational hooks, routing tables, process obligations).
Behavioral norms live in SOUL; enforcement mechanisms live in AGENTS.

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
Shared across all agents. Present in both USER and PROJECT scopes.

#### SKILL.md Frontmatter Schema

Every SKILL.md MUST begin with YAML frontmatter containing:

| Field | Required | Type | Purpose |
|-------|----------|------|----------|
| `name` | Yes | string | Skill name — MUST match parent directory name |
| `description` | Yes | string | **Signal phrases** — comma-separated trigger phrases for intent matching. See Signal Phrase Rules below |
| `metadata.tags` | Yes | list[string] | Tag-based discovery (e.g., `[agentfs, setup]`) |

> **Schema change (v2.0.0):** `metadata.signals` has been removed.
> Signal phrases now live in the `description` field, which is the
> only metadata always loaded into the agent's context via the
> built-in skills listing.

**Signal Phrase Rules:**

The `description` field is the **signal routing surface** — the LLM
matches user intent against these phrases to select the correct skill.

- **Command pattern** (`verb + noun(s)`) — for actions: `setup agentfs`,
  `create skill`, `start crc`
- **Query pattern** (`noun(s)`) — for status/inspection: `crc status`,
  `litellm health`
- **Three principles:** Concise (2-4 words), No redundant (no two
  phrases matching the same intent), Complete (every mode covered)
- **Smell test:** 15+ phrases suggests the skill should be split

**Opening paragraph requirement:** Since `description` contains signal
phrases (not prose), the SKILL.md body MUST include a hydrated
human-readable paragraph immediately after the `# Title` heading.

Signal phrases are surfaced in `skills/index.md` by the `skill-index`
skill (in the Description column) for progressive discovery. They are
NOT compiled into AGENTS.md — the Signal Routing table in AGENTS.md
is reserved for LLM-direct routes and genuinely ambiguous multi-skill
triage entries.

See [`skill-gen/references/skill-schema.md`](~/.agents/skills/skill-gen/references/skill-schema.md)
for the full canonical schema.

### 6. Semantic Context Layer — ~/.agents/knowledge/ (USER only)
Open Knowledge Format. File path = concept identity. Every file requires
YAML frontmatter with `type` field. Markdown links form a knowledge graph.
Shared across all agents and projects. Present in USER scope only —
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

## Spec-kit Coexistence (PROJECT Scope)

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
  (initialized by default in PROJECT scope)

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
`.agents/`) by default in PROJECT scope. The `.gitignore` tracks
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
#6 Idempotency, #7 Anti-Sycophancy, #9 Checkpoints & Resumability
after the v3.3 consolidation from 13 → 9 guardrails, later expanded
to 10 with #8 Anti-Daydreaming):

- **Idempotency** — skills must be re-runnable safely (existence
  checks, upsert patterns, no append-without-dedup)
- **Checkpoints & Resumability** — record state before destructive
  operations in `.agents/.checkpoint`
- **Anti-Sycophancy** — agent must flag conflicts with existing
  guardrails, not silently comply; overrides logged with `[OVERRIDE]`

## Scopes: USER, PROJECT, and LITE

AgentFS operates in three scopes. USER and PROJECT are the original
two; LITE was added in v4.19.0 for small-context models.

| Scope | Root | Target Use | AGENTS.md |
|-------|------|------------|-----------|
| **USER** | `~/.agents/` | Machine-wide shared library | None |
| **PROJECT** | `./.agents/` (CWD) | Full per-repo workspace | Full (~3,750 tokens) |
| **LITE** | `./.agents/` (remote path) | Minimal per-repo workspace | Lite (~850 tokens) |

### LITE Scope

LITE is a constrained form of PROJECT scope, designed for projects
consumed by small-context models (e.g., Granite 3B at 16K context).

**What's different from PROJECT:**
- No `skills/`, `profiles/`, `skills/index.md`, `profiles/index.md`
- AGENTS.md uses a minimal template with 6 terse rules (no script deps)
- No SPECKIT markers, no Agent Profiles table, no Scope Definitions
- Includes a Session Start section that detects unnecessary extensions
- Cannot self-manage — always managed externally by a full-capability session

**Inference rule:** When the agent invokes setup/sync with an explicit
target directory that does NOT resolve to CWD, the scope is LITE.
No explicit path or path resolving to CWD = PROJECT.

**Metadata:** `<!-- agentfs-template-version: X.Y agentfs-scope: lite -->`

Detection pattern:
```bash
AGENTFS_SCOPE=$(grep -oP 'agentfs-scope: \K\w+' "$TARGET/AGENTS.md" 2>/dev/null || echo "project")
```

### LITE Scope — File Structure

```text
<target-project>/
├── AGENTS.md
└── .agents/
    ├── index.md
    ├── log.md
    ├── SOUL.md
    └── memories/
        ├── USER.md
        └── MEMORY.md
```

### Lifecycle Model

LITE projects are **provisioned and maintained** by normal-capability
sessions (with skills extension), then **consumed** by lite sessions
(developer-only). A lite session cannot sync or scaffold — it can
only read AGENTS.md, follow the rules, and write to memories/log.

### Mode Switching

Sync preserves scope — it never auto-switches. To convert a project
from LITE to PROJECT scope, explicitly re-seed with `--scope project`
and re-scaffold with `--scope project`.

## Known Issues

### KI-1: Command-Shaped Signal Phrases vs Shell Tool Dispatch

**Status:** Mitigated (v6.0.0) — deterministic enforcement via `signal-dispatch` plugin
**Affected models:** Granite 4.2 8B (and likely other ≤14B models)
**Added:** 2026-09-25 v5.14.0
**Updated:** 2026-09-25 v6.0.0

**Problem:**

Rule 8 requires models to call `search_nodes` before any other tool.
However, when user input resembles a shell command (e.g., `"skupper status"`,
`"crc status"`, `"litellm proxy status"`), weaker models bypass Rule 8
entirely and call the `shell` tool directly. This happens because:

1. The `shell` tool description ("Execute a shell command") is a stronger
   pattern match for command-shaped inputs than Rule 8's instruction to
   call `search_nodes` ("Search for nodes in the knowledge graph").
2. The `developer` extension instructions ("operate a terminal") reinforce
   `shell` as the natural tool for anything that looks like a command.
3. Smaller models (≤8B params) lack the instruction-following depth to
   override tool-description-level pattern matching with system-prompt-level
   dispatch rules.

The issue extends beyond CLI tool names — Granite also hallucinates tool
names from the `# Skills` section (e.g., tries to call `litellm-proxy-status`
or `headroom-proxy-status` as direct tools) rather than routing through
`search_nodes` → `load_skill`.

**Mitigations applied (v5.14.0):**

| Mitigation | Effect |
|-----------|--------|
| Disabled `extensionmanager` extension | Removed competing "search first" instruction | 
| Added `## Tool Priority` section above Rules table | Standalone numbered dispatch order visible before dense rules |
| Strengthened Rule 8 with explicit anti-shell clause | *"Never call `shell` as the first tool"* |
| Changed behavioral test B1 to use natural-language phrasing | Avoids testing inputs that are unsolvable for weaker models |

**Behavioral test results (v5.14.0):**

| Model | B1 (skill dispatch) | B2 (explicit signal) | B3 (anti-pattern) |
|-------|:-------------------:|:--------------------:|:-----------------:|
| Claude Opus | ✅ `search_nodes` | ✅ `load_skill` | ✅ `search_nodes` |
| Granite 4.2 8B | ❌ `shell` (non-deterministic) | ✅ `load_skill` | ⚠️ non-deterministic |

**Root cause:** This is a model capability ceiling, not a template deficiency.
Larger models (Claude Opus, GPT-4+) consistently follow Rule 8 because they
can process multi-step dispatch chains in system prompts. Models ≤8B params
cannot reliably override tool-description pattern matching with system-prompt
rules, especially when the input surface-matches a tool description.

**v6.0.0 mitigation — `signal-dispatch` plugin:**

The `signal-dispatch` plugin (`~/.agents/plugins/signal-dispatch/`)
provides deterministic enforcement of the `hey` dispatch prefix using
Goose lifecycle hooks:

1. `UserPromptSubmit` hook detects `hey`-prefixed prompts and sets a
   session-scoped flag file
2. `PreToolUse` hook blocks any non-`search_nodes` tool call when the
   flag is set, injecting a dispatch reminder as the block reason
3. The block reason is visible to the model as a message, serving as
   a just-in-time reminder of the dispatch rule
4. Flag is cleared after one enforcement (prevents infinite loops)

This implements "potential future mitigation #1" from v5.14.0 — tool
routing priorities enforced by the platform before the model acts —
using hooks rather than a native platform feature.

**Remaining limitations:**
- If the model responds to a `hey` prompt with pure text (no tool calls),
  `PreToolUse` never fires and the flag persists to the next turn
- One-shot enforcement means the hook can be "tanked" by a model that
  retries without reading the block reason
- Models ≤8B params may still struggle with the dispatch table
  classification even after being reminded

### KI-2: Session Poisoning from PreToolUse Block Reasons

**Status:** Mitigated (v6.0.1) — affirmative block reason framing
**Affected models:** Granite 4.2 8B (and likely other ≤14B models)
**Added:** 2026-09-27 v6.0.1

**Problem:**

When the `signal-dispatch` plugin blocks a tool call via `PreToolUse`,
the block reason is returned to the model as an error message. Weaker
models over-generalize from the block — learning "all tools are blocked
during hey prompts" rather than "only this specific tool was blocked."
The model then refuses to call ANY tool (including allowed ones like
`search_nodes` and `load_skill`) for the remainder of the session,
answering from stale cached context instead.

**Root cause:** The model's reasoning traces record the wrong conclusion
from the block reason. Subsequent turns reference this cached reasoning
rather than re-reading the system prompt rules. The poisoned conclusion
persists in conversation history and compounds with each turn.

**Mitigations applied:**

| Mitigation | Effect |
|-----------|--------|
| Affirmative block reason framing (v1.2.0+) | "You CAN and SHOULD use tools" instead of "You MUST NOT call shell" |
| Remove alarm language | "This tool is not needed yet" instead of "SIGNAL DISPATCH REQUIRED" |
| No prohibition lists | Removed explicit lists of blocked tools — model memorizes prohibitions more strongly than permissions |
| Include user keywords | Model sees what to match against without re-reading AGENTS.md |

**Recovery pattern — compaction as session reset:**

Goose compaction (`/compact` or auto-compaction) is an effective
recovery mechanism for session poisoning. Compaction replaces the
conversation history with a structured JSON summary (user intents,
files, errors, pending tasks). The model's thinking traces — where
the poisoned conclusions live — are discarded because they are not
part of tool responses or user messages. After compaction:

1. System prompt (AGENTS.md + SOUL.md) is intact at top of context
2. Compacted summary contains work context without poisoned reasoning
3. Model re-reads dispatch rules from system prompt with clean slate

This is an accidental but reliable recovery: **compaction erases bad
reasoning while preserving work context.** When a weaker model shows
signs of learned tool avoidance, trigger compaction to reset.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-09-25 23:30 | v6.0.0 — **Breaking:** AGENTS.md template reduced from 17 to 10 rules. Behavioral norms (no validation phrases, no assumed inputs, risk naming) moved to SOUL.md Principles. Signal dispatch rules (6 rules) collapsed into 1 rule + Signal Dispatch table; all signals unified under `hey` prefix. Scope Definitions relocated from AGENTS.md to `.agents/index.md`. SOUL.md restructured: prose → hybrid (identity preamble + structured Principles with bold labels). Added `signal-dispatch` plugin (`~/.agents/plugins/signal-dispatch/`) for deterministic `hey` enforcement via Goose `PreToolUse` hooks. Added `~/.agents/scripts/` directory for AGENTS-specific scripts. Added `plugins/` and `scripts/` to scope tables. KI-1 status updated to Mitigated. SOUL/AGENTS separation clarified: SOUL = self-discipline, AGENTS = external enforcement. |
| 2026-08-13 12:40 | v3.11 — SKILL.md Frontmatter Schema: `description` field redefined as signal phrases (Command/Query patterns); `metadata.signals` removed; added Signal Phrase Rules, Opening Paragraph requirement; updated Signal Routing architecture (signals now in `description`, skills index Description column as defense-in-depth) |
| 2026-07-31 21:42 | v3.8 — Added Guardrail #8 Anti-Daydreaming (ephemeral session canary name for context-drift detection); renumbered Checkpoints → #9, Git Push Safety → #10; clarified Index Currency trigger to include metadata-only changes; updated all cross-references |
| 2026-07-27 18:30 | v3.7 — Added Signal Routing architecture (LLM-direct in AGENTS.md, skill signals in SKILL.md frontmatter, skills index as lookup table); added template versioning and `--sync` mechanism; added template-owned vs project-owned section markers; added SKILL.md Frontmatter Schema with `metadata.signals` field; added README sync rule (hard requirement); renamed Guardrail #2 to Memory Scope (Signal Routing promoted to standalone section) |
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
