# AgentFS

**Shared agent scaffolding with skills, knowledge bundles, and cross-agent context.**

AgentFS is a structured filesystem convention for AI coding agents (Goose, Hermes, Claude Code, etc.) that enables persistent memory, reusable skills, and shared knowledge across agents and sessions.

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical.

| Scope | Root Path | Resolves To | Purpose |
|-------|-----------|-------------|----------|
| **USER** | `~/.agents/` | `/home/<user>/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | `<repo-root>/.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

> **Rule of thumb:** USER scope = `~/.agents/`. PROJECT scope = `./.agents/`.
>
> **This repository is a USER scope AgentFS instance.**

## Getting Started

### Step 1: Set Up USER Scope (`~/.agents/`)

Choose one of two paths:

#### Path A: Full Install (recommended)

Clone this repo directly into `~/.agents/`:

```bash
git clone https://github.com/rhtevan/agentfs.git ~/.agents
```

You get the complete skill library, knowledge bundles, and structural
scaffolding — ready to use immediately.

#### Path B: Minimal Install

For a clean, empty `~/.agents/` where you cherry-pick skills:

1. Clone the repo to a staging location:
   ```bash
   git clone https://github.com/rhtevan/agentfs.git ~/repos/agentfs
   ```
2. Make the staging location visible to your agent (e.g., add
   `~/repos/agentfs/skills/` to the agent's skill search paths
   — see the relevant agent setup skill for details).
3. Ask your agent to run the `agentfs-setup` skill with USER scope:
   > *"Set up AgentFS in USER mode"*

   The agent will load the `agentfs-setup` skill and scaffold an
   empty `~/.agents/` with `skills/`, `knowledge/`, `index.md`,
   and `log.md`.
4. Cherry-pick specific skills using the `skill-merge` skill or
   manual copy.

### Step 2: Configure Your Agent

#### With Goose

Load the `goose-agentfs-setup` skill to register AgentFS context files
(`CLAUDE.md`, `AGENTS.md`, etc.) in Goose's `CONTEXT_FILE_NAMES`.

#### With Hermes Agent

Load the `hermes-agentfs-setup` skill to register `~/.agents/skills`
in Hermes's `skills.external_dirs`.

### Step 3: Set Up PROJECT Scope (per repo)

In any git repository, ask your agent to run the `agentfs-setup` skill:

> *"Set up AgentFS for this project"*

The agent will scaffold `.agents/` (with skills, profiles, memories,
SOUL.md) and create `AGENTS.md` at the repo root. Since PROJECT is the
default mode, no additional scope hint is needed.

### Adding Skills

Create a new directory under `skills/` with a `SKILL.md` file, then
ask the agent to run the `skill-index` skill to regenerate the index.

### Adding Knowledge

Ask the agent to run the `okf-bundle-setup` skill to scaffold a new
OKF-conformant knowledge bundle under `~/.agents/knowledge/` (USER
scope — knowledge is shared across all projects).

## Directory Structure

```
~/.agents/
├── skills/          # Reusable agent workflows (SKILL.md format)
├── knowledge/       # Shared knowledge base (Open Knowledge Format)
├── index.md         # Navigation hub — start here
└── log.md           # Activity log (reverse chronological)
```

### Skills (`skills/`)

Each skill is a self-contained directory with a `SKILL.md` file that
provides step-by-step instructions an agent can load and follow.
Skills cover topics like:

| Category | Examples |
|----------|----------|
| **Agent Setup** | AgentFS scaffolding, Goose/Hermes configuration, agent profiles |
| **LLM Providers** | LiteLLM proxy, Headroom proxy, Vertex AI, MaaS providers |
| **OpenShift/CRC** | Operator installs (COO, NOO, NMState, MetalLB), cluster config |
| **Knowledge Mgmt** | OKF bundle creation, indexing, generation |
| **Desktop/System** | Hermes desktop fixes, Fedora window list, Goose CLI fixes |

See [`skills/index.md`](skills/index.md) for the full list.

### Skill Design Principles

Skills follow three foundational design principles that govern how
interactivity, determinism, and orchestration are separated across
architectural layers.

#### 1. Non-Interactive Scripts

Scripts under `scripts/` MUST be non-interactive. They MUST NOT use
`read`, `select`, interactive prompts, or any mechanism that blocks
waiting for stdin. All inputs MUST be accepted via command-line
arguments, environment variables, or input files.

```bash
# ✅ Correct — inputs as arguments
bash scripts/provision.sh --name "$NAME" --email "$EMAIL"

# ❌ Wrong — blocks on stdin
read -p "Enter name: " NAME
```

This ensures scripts remain testable, composable, and executable in
automated contexts (scheduled jobs, skill chaining, CI pipelines)
where no human is present at the terminal.

#### 2. Agent-as-Orchestrator Pattern

Skills implement a three-layer architecture that cleanly separates
concerns:

```
┌────────────────────────────────────────┐
│              SKILL.md                  │
│       (Process Definition)             │
│  Defines steps, decision points,       │
│  interaction gates, and script calls   │
└──────────────┬─────────────────────────┘
               │ instructs
               ▼
┌──────────────────────┐       ┌──────────────┐
│       Agent          │◄─────►│     User     │
│   (Orchestrator)     │ conversation  (External │
│                      │  context      Input)    │
│  Mediates human      │       └──────────────┘
│  interaction,        │
│  holds state,        │
│  feeds data between  │
│  steps               │
└──────────┬───────────┘
           │ executes
           ▼
┌──────────────────────┐
│  Deterministic       │
│  Scripts (Actions)   │
│                      │
│  Non-interactive,    │
│  idempotent,         │
│  args in → exit      │
│  code out            │
└──────────────────────┘
```

| Layer | Responsibility | Interactive? |
|---|---|---|
| **SKILL.md** | Defines the process — sequence, decision points, gates | N/A (blueprint) |
| **Agent** | Orchestrates flow, mediates user interaction, translates between human language and script arguments | ✅ Conversationally |
| **Scripts** | Execute deterministic, repeatable actions | ❌ Never |

The agent handles the "messy human stuff" — ambiguous inputs,
clarifications, approvals, error explanations. The scripts handle
the "precise machine stuff" — validation, API calls, data
transformations. The SKILL.md is the contract between them.

#### 3. Skills as Business Process Definitions

Skills can model multi-step business processes that include human
interaction points. The key insight is that **interactivity belongs
in the agent ↔ user conversation layer**, not in script execution.

A business process skill defines:
- **Action steps** — deterministic scripts the agent runs
- **Interaction steps** — points where the agent gathers input,
  presents results, or requests approval from the user
- **Decision points** — conditional branching based on script
  exit codes or user responses
- **External gates** — steps that wait for external input
  (approvals, reference numbers, third-party responses)

Example pattern in a SKILL.md:

```markdown
## Steps

1. **Collect requirements**
   Ask the user for: name, department, role.

2. **Validate input**
   Run: `bash scripts/validate.sh --name "$NAME" --dept "$DEPT"`
   If exit code 1 → report errors, return to Step 1.

3. **Present plan and confirm**
   Show the provisioning plan. Ask for user confirmation.

4. **Execute**
   Run: `bash scripts/provision.sh --config /tmp/plan.json`

5. **External approval gate**
   Tell the user: "Manager approval required. Provide the
   approval reference when ready."
   Run: `bash scripts/verify-approval.sh --ref "$REF"`

6. **Finalize and report**
   Run: `bash scripts/finalize.sh --id "$ID"`
```

This pattern preserves all structural guardrails — scripts stay
idempotent (Guardrail #10), the process is documented (SKILL.md
*is* the documentation), each script is independently testable,
and the same scripts can be reused by other skills or automated
jobs with pre-known inputs.

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

A **machine-wide shared library** of skills and knowledge visible to
any agent across all projects. No agent identity, memories, or
profiles — purely a capability and knowledge store.

```
~/.agents/
├── skills/          # Shared agent workflows
├── knowledge/       # Shared knowledge bundles
├── index.md
└── log.md
```

### PROJECT Mode (`./.agents/` in a repo)

A **per-repository agent workspace** that adds identity, memory, and
multi-agent collaboration on top of skills. Each project can have its
own agent profiles with independent memories.

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

Both modes can coexist — agents discover USER-level skills and knowledge
globally while maintaining project-scoped identity and memory in PROJECT
mode.

## Structural Guardrails

AgentFS enforces nine guardrails to maintain consistency:

1. **Link Integrity** — No broken, obsolete, or missing links in `index.md` files
2. **Log Currency** — All changes logged in reverse chronological order (ISO 8601 timestamps)
3. **Content Changelog** — Files with `Changelog` sections maintain reverse-chronological entries
4. **Progressive Disclosure** — Browse `index.md` hubs before diving into individual files
5. **Skill Placement** — Default to USER scope; PROJECT only when explicitly requested
6. **Index Currency** — `skills/index.md` and `profiles/index.md` regenerated on every change
7. **Cross-Agent Context Discovery** — Read `CLAUDE.md`, `.cursorrules`, etc. as supplementary guidelines
8. **Memory Scope** — `memories/` is PROJECT-only; NL-signal routing for experiences vs rules vs preferences; graduation path to OKF knowledge
9. **Memory Signal Routing** — Decision table mapping natural-language signals to memory actions; agent-specific override tables take priority when their tools are available

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

### Memory Signal Routing

When multiple memory systems coexist (e.g., AgentFS file-based memory,
agent-specific extensions like Goose Memory/Cognee, or external MCP
servers), natural-language signals like "remember this" can create
ambiguity. AgentFS solves this with a **two-layer decision table
architecture**:

#### Layer 1: Agent-Agnostic Table (AGENTS.md Guardrail #9)

Defines signal → route mappings that work with ANY agent. Routes to
AgentFS files and skills. Each row includes an **Executor** column
clarifying whether the LLM acts directly (file read/write) or
delegates to a named skill.

Key routing rules:
- "remember this" → `MEMORY.md` (LLM direct)
- "always do X" → propose `AGENTS.md` guardrail (LLM direct, human approval)
- "I prefer" → `USER.md` (LLM direct)
- "learn this document" → OKF bundle (`okf-bundle-gen`/`okf-bundle-harvest` skill)
- "create a skill" → `~/.agents/skills/` (LLM intrinsic or agent Skills extension, USER scope default)
- "harvest" → scan `MEMORY.md` files, route to `skill-harvest` (procedural) or `okf-bundle-harvest` (semantic)

#### Layer 2: Agent-Specific Table (e.g., Goose `instructions.md`)

Overrides Layer 1 when the agent has its own memory extensions enabled.
The table is **static** — it lists all possible routes with priority
numbers. The agent resolves dynamically at runtime by checking whether
each referenced tool exists in the current session's available tools.

Example (Goose):

| Priority | Extension | When Available |
|----------|-----------|----------------|
| 1 (highest) | Cognee MCP | Knowledge graph with semantic search — subsumes Memory when enabled |
| 2 | Goose Memory | Simple persistent `.txt` storage — fallback when Cognee unavailable |
| 3 | Chat Recall | Past session search — unique capability, no overlap with storage |

**Resolution rule:** Process rows in priority order. First row whose
tool exists in the current tools list wins. If no agent-specific tool
matches, fall through to Layer 1 (AGENTS.md).

**Tool existence = extension enabled.** Agents only inject tools when
their parent extension is active, so checking tool availability is
equivalent to checking extension state — no config file inspection
needed.

### Guardrail Layering

Guardrails themselves exist at three levels:

| Level | Location | Scope | Purpose |
|-------|----------|-------|----------|
| **AgentFS template** | `seed-agents-md.sh` in the `agentfs-setup` skill | Cross-project | Canonical source of the 9 structural guardrails; projects are aligned to this template |
| **AGENTS.md** | `./AGENTS.md` in each project | PROJECT | Rendered instance of the template guardrails, plus any project-specific additions |
| **Agent config** | e.g. `~/.config/goose/instructions.md` | USER (agent-specific) | Agent-level instincts — path hygiene, git push safety, memory routing overrides |

When the AgentFS template is updated, existing projects are brought into
alignment by re-running setup verification (`verify-setup.sh --mode project`).

## Evaluation

AgentFS includes an evaluation skill (`agentfs-eval`) that assesses the
health and maturity of an AgentFS workspace through three progressively
deeper verification layers.

### The Problem

Guardrails in `AGENTS.md` are **prescriptive** — they tell the agent
what to do. But nothing verifies the agent actually followed them.
This is equivalent to having coding standards without a linter. The
guardrails rely entirely on the agent's willingness and ability to
follow instructions — which is exactly what AI model flaws undermine.

### Guiding Principles

Two sets of non-negotiable principles drive the evaluation design:

**Safe Agent Actions:**

| Property | Requirement |
|----------|-------------|
| Idempotency | Actions can be retried without catastrophic consequences |
| Resumability | A series of actions can be resumed or reverted after interruptions |
| Auditability | An audit trail exists for all actions |

**AI Flaw Mitigation:**

| Flaw | Risk to AgentFS |
|------|------------------|
| Hallucination | Agent invents files, references, or observations that don't exist |
| Stochasticity | Same skill produces inconsistent workspace structures across runs |
| Sycophancy | Agent silently complies with requests that violate guardrails |

### Three-Layer Verification

| Layer | Paradigm | LLM Required? | What It Verifies |
|-------|----------|:-:|------------------|
| **L1: Structural** | Filesystem assertions (shell scripts) | No | Links, log ordering, index completeness, frontmatter, scope correctness, orphans |
| **L2: Behavioral** | Forensic evidence correlation | No | Action-log correlation, timestamp alignment, scope leakage, idempotency, rule-in-memory |
| **L3: Semantic** | Constrained LLM classification | Yes | Memory content classification, reference verification, sycophancy detection, skill accuracy |

Layer 3 uses the LLM as a **classifier** with closed-ended questions
and majority voting — not as an open-ended judge. This resists the
very AI flaws being evaluated.

### Maturity Levels

| Level | Name | Requirements |
|-------|------|--------------|
| L0 | Absent | No `.agents/` directory |
| L1 | Scaffolded | `.agents/` exists with valid structure |
| L2 | Structurally Sound | All Layer 1 assertions pass |
| L3 | Behaviorally Safe | Layer 1 + Layer 2 pass |
| L4 | Semantically Accurate | Layer 1 + Layer 2 + Layer 3 pass |
| L5 | Self-Correcting | Agent detects and fixes its own violations |

### Usage

Run `agentfs-eval` explicitly by asking any agent:

> "Run agentfs eval" or "Run agentfs eval against /path/to/project"

For the most reliable results, run in a **fresh session** with a
capable model to eliminate self-evaluation bias.

### Key Design Decisions

- **No golden test cases** — eval tests real workspace content, not
  synthetic scenarios
- **Explicit trigger only** — no hooks, cron, or automated triggers
  in v1.0
- **Graceful degradation** — checks report N/A when evidence is
  insufficient (fresh projects) rather than failing
- **Git provides audit evidence** — `agentfs-setup` initializes git
  in PROJECT mode by default; `.agents/memories/` is tracked for
  full audit trail
- **L3 → L2 graduation is human-driven** — patterns observed in
  semantic eval reports are manually codified as deterministic
  heuristics over time

See [`skills/agentfs-eval/SKILL.md`](skills/agentfs-eval/SKILL.md)
for full details and
[`skills/agentfs-eval/references/design-decisions.md`](skills/agentfs-eval/references/design-decisions.md)
for the complete design rationale.

## License

Copyright 2025 Evan Zhang

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
implied. See the License for the specific language governing
permissions and limitations under the License.

See [LICENSE](./LICENSE) for the full text.
