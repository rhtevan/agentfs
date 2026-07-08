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

See [`skills/index.md`](skills/index.md) for the full list of 31 skills.

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

A **per-repository agent workspace** that adds identity, memory, and multi-agent collaboration on top of skills and knowledge. Each project can have its own agent profiles with independent memories.

```
./
├── AGENTS.md                # Workspace entry point
└── .agents/
    ├── SOUL.md              # Default agent identity
    ├── profiles/            # Named agent profiles (each with SOUL.md + memories)
    ├── memories/            # Default agent's learned context (USER.md, MEMORY.md)
    ├── skills/              # Project-specific skills
    └── knowledge/           # Project-specific knowledge
```

Both modes can coexist — agents discover USER-level skills/knowledge globally while maintaining project-scoped identity and memory in PROJECT mode.

## Structural Guardrails

AgentFS enforces four guardrails to maintain consistency:

1. **Link Integrity** — No broken, obsolete, or missing links in `index.md` files
2. **Log Currency** — All changes logged in reverse chronological order (ISO 8601)
3. **Content Changelog** — Files with `Changelog` sections maintain reverse-chronological entries
4. **Progressive Disclosure** — Browse `index.md` hubs before diving into individual files

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

Use the `okf-bundle-setup` skill to scaffold a new OKF-conformant knowledge bundle under `knowledge/`.

## License

This repository contains personal agent configuration and knowledge. Use at your own discretion.
