# AgentFS

**Shared agent scaffolding with skills, knowledge bundles, and cross-agent context.**

AgentFS is a structured filesystem convention for AI coding agents (Goose, Hermes, Claude Code, etc.) that enables persistent memory, reusable skills, and shared knowledge across agents and sessions.

## Directory Structure

```
~/.agents/
├── skills/          # Reusable agent workflows (SKILL.md format)
├── knowledge/       # Shared knowledge base (Open Knowledge Format)
├── index.md         # Navigation hub — start here
└── log.md           # Activity log (reverse chronological)
```

### Skills (`skills/`)

Each skill is a self-contained directory with a `SKILL.md` file that provides step-by-step instructions an agent can load and follow. Skills cover topics like:

| Category | Examples |
|----------|----------|
| **Agent Setup** | AgentFS scaffolding, Goose/Hermes configuration, agent profiles |
| **LLM Providers** | LiteLLM proxy, Headroom proxy, Vertex AI, MaaS providers |
| **OpenShift/CRC** | Operator installs (COO, NOO, NMState, MetalLB), cluster config |
| **Knowledge Mgmt** | OKF bundle creation, indexing, generation |
| **Desktop/System** | Hermes desktop fixes, Fedora window list, Goose CLI fixes |

See [`skills/index.md`](skills/index.md) for the full list of 33 skills.

### Knowledge (`knowledge/`)

Knowledge bundles follow the [Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) — each bundle contains concept documents, an `index.md` navigation hub, and a `log.md` changelog.

Current bundles:

- **Telecom GNN-Based Root Cause Analysis** — GNN and DRL for autonomous telecom network fault diagnosis
- **RCA Labeled Dataset** — Realistic labeled dataset for training GNNs on telecom network faults
- **AgentFS ↔ Claude Compatibility** — Cross-agent context discovery gap analysis
- **Headroom Compression Analysis** — Proxy compression analysis for OpenAI-compatible endpoints

## Modes

AgentFS operates in two modes:

### USER Mode (`~/.agents/`)

A **machine-wide shared library** of skills and knowledge visible to any agent across all projects. No agent identity, memories, or profiles — purely a capability and knowledge store.

```
~/.agents/
├── skills/          # Shared agent workflows
├── knowledge/       # Shared knowledge bundles
├── index.md
└── log.md
```

> **This repository is a USER mode AgentFS instance.**

### PROJECT Mode (`./.agents/` in a repo)

A **per-repository agent workspace** that adds identity, memory, and multi-agent collaboration on top of skills. Each project can have its own agent profiles with independent memories.

```
./
├── AGENTS.md                # Workspace entry point
└── .agents/
    ├── SOUL.md              # Default agent identity
    ├── profiles/            # Named agent profiles (each with SOUL.md + memories)
    ├── memories/            # Default agent's learned context (USER.md, MEMORY.md)
    ├── skills/              # Project-specific skills
    ├── index.md
    └── log.md
```

> **Note:** `knowledge/` is USER-scoped only — projects do NOT get a
> local `knowledge/` directory. `memories/` is PROJECT-scoped only —
> there is no `~/.agents/memories/`.

Both modes can coexist — agents discover USER-level skills and knowledge globally while maintaining project-scoped identity and memory in PROJECT mode.

## Structural Guardrails

AgentFS enforces eight guardrails to maintain consistency:

1. **Link Integrity** — No broken, obsolete, or missing links in `index.md` files
2. **Log Currency** — All changes logged in reverse chronological order (ISO 8601 timestamps)
3. **Content Changelog** — Files with `Changelog` sections maintain reverse-chronological entries
4. **Progressive Disclosure** — Browse `index.md` hubs before diving into individual files
5. **Skill Placement** — Default to USER scope; PROJECT only when explicitly requested
6. **Index Currency** — `skills/index.md` and `profiles/index.md` regenerated on every change
7. **Cross-Agent Context Discovery** — Read `CLAUDE.md`, `.cursorrules`, etc. as supplementary guidelines
8. **Memory Scope** — `memories/` is PROJECT-only; NL-signal routing for experiences vs rules vs preferences; graduation path to OKF knowledge

## Memory Architecture

AgentFS implements a layered memory system inspired by cognitive science.
Each layer serves a distinct purpose, scope, and mutability model.

### The Full Memory Model

| Memory Type | Cognitive Analogy | Scope | Location | Mutability |
|-------------|-------------------|-------|----------|------------|
| **MEMORY.md** | Episodic / experiential | PROJECT | `.agents/memories/` | Agent-written, session-to-session |
| **OKF bundles** | Semantic / conceptual | USER | `~/.agents/knowledge/` | Distilled, graduated |
| **SKILLs** | Procedural / SOP | Both | `~/.agents/skills/` or `.agents/skills/` | Human + agent authored |
| **SOUL.md** | Identity | PROJECT | `.agents/SOUL.md` | Human-authored |
| **USER.md** | User model | PROJECT | `.agents/memories/USER.md` | Agent-written |
| **AGENTS.md** | Working agreements | PROJECT | `./AGENTS.md` | Human-authored + templated |
| **instructions.md** | Agent instincts | USER (agent-specific) | e.g. `~/.config/goose/instructions.md` | Human-authored |

### Layer Details

#### Episodic Memory — `MEMORY.md`

Concrete, project-specific observations and discoveries recorded by the
agent during work. Each agent profile (default, named profiles) maintains
its own `MEMORY.md`.

- **Scope:** PROJECT only — lives under `.agents/memories/` (default agent)
  or `.agents/profiles/<name>/memories/` (named profiles)
- **Content:** "I found that X", "the build breaks when Y",
  "this codebase prefers pattern W"
- **Triggered by:** User signals ("remember this", "note that", "keep in mind")
  or agent-initiated discovery during work
- **Not here:** Rules → `AGENTS.md`; preferences → `USER.md`;
  matured cross-project patterns → graduate to OKF

#### Semantic Memory — OKF Knowledge Bundles

Abstract concepts, patterns, and methodology distilled from episodic
memories across one or more projects. Strictly USER-scoped to protect
personal intellectual property — never committed to any project repository.

- **Scope:** USER only — lives under `~/.agents/knowledge/`
- **Content:** Methodology, design patterns, architectural principles,
  cross-project insights
- **Origin:** Graduated from `MEMORY.md` entries (single or multi-project)
  or distilled from session context
- **Managed by:** `okf-bundle-gen`, `okf-bundle-harvest`, `okf-bundle-setup`,
  `okf-bundle-index` skills

#### Procedural Memory — Skills

Actionable, preferably idempotent workflows — standard operating procedures
(SOPs), exercises, and automation functions.

- **Scope:** Both USER (`~/.agents/skills/`, shared across projects) and
  PROJECT (`.agents/skills/`, repo-specific)
- **Structure:** `SKILL.md` (instructions) + `scripts/` (executable) +
  `references/` (supporting docs)
- **Default placement:** USER scope unless the user explicitly requests
  project scope
- **Portability:** `skill-merge` promotes PROJECT skills → USER skills
  for cross-project reuse

### Guardrail Layering

Guardrails themselves exist at three levels:

| Level | Location | Scope | Purpose |
|-------|----------|-------|---------|
| **AgentFS template** | `seed-agents-md.sh` in the `agentfs-setup` skill | Cross-project | Canonical source of the 8 structural guardrails; projects are aligned to this template |
| **AGENTS.md** | `./AGENTS.md` in each project | PROJECT | Rendered instance of the template guardrails, plus any project-specific additions |
| **Agent config** | e.g. `~/.config/goose/instructions.md` | USER (agent-specific) | Agent-level instincts — path hygiene, git push safety, memory routing overrides |

When the AgentFS template is updated, existing projects are brought into
alignment by re-running setup verification (`verify-setup.sh --mode project`).

## Getting Started

### With Goose

1. Clone this repo to `~/.agents/`
2. Load the `agentfs-setup` skill: Goose will scaffold the directory and configure context file discovery
3. Load the `goose-agentfs-setup` skill to register AgentFS context files (`CLAUDE.md`, `AGENTS.md`, etc.)

### With Hermes Agent

1. Clone this repo to `~/.agents/`
2. Load the `hermes-agentfs-setup` skill to register `~/.agents/skills` in Hermes's `skills.external_dirs`

### Adding Skills

Create a new directory under `skills/` with a `SKILL.md` file, then run the `skill-index` skill to regenerate the index.

### Adding Knowledge

Use the `okf-bundle-setup` skill to scaffold a new OKF-conformant knowledge bundle under `~/.agents/knowledge/` (USER scope — knowledge is shared across all projects).

## License

This repository contains personal agent configuration and knowledge. Use at your own discretion.
