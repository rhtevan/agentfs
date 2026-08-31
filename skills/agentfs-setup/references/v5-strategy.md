# AgentFS v5 Enhancement Strategy

> Version: 3 — 2026-08-31
> Status: Strategy approved. Action plan: [agentfs-v5-action-plan.md](./agentfs-v5-action-plan.md)

## Problem Statement

AgentFS AGENTS.md serves as the system prompt entry point for agent
sessions. The current design (v4.x) has three structural inefficiencies:

1. **Token bloat** — AGENTS.md carries ~2,776 tokens/turn of inline
   prose (293 lines, 7 sections), including full guardrail detail that
   could be progressively loaded. Over a 20-turn session, this costs
   ~55K input tokens.

2. **Double encoding** — Guardrails appear twice: once in the Quick
   Reference summary table and again in the full detail section.
   Same information, double the cost.

3. **Knowledge retrieval fragility** — OKF knowledge bundles lack a
   progressive disclosure mechanism equivalent to skills. Discovery
   depends on the LLM traversing a 3–4 hop index chain
   (`AGENTS.md → knowledge/index.md → bundle/index.md → concept.md`),
   which fails silently when the model skips a hop.

## Strategy

### S1. AGENTS.md as Index-of-Indexes

Reduce AGENTS.md to a concise entry point containing only lookup
tables and compact guardrail rules. All procedural detail delegates
to skills.

**Target:** ~874 tokens (down from ~2,776 — a 69% reduction).
Saves ~38,100 tokens over a 20-turn session.

**Rationale:** The system prompt is injected every turn. Every token
in AGENTS.md is paid N times per session. Content that is only needed
at specific moments (git push workflow, filesystem integrity details)
should be loaded on demand via skills, following the same progressive
disclosure pattern that skills already use.

### S2. Trigger/Context/Action Triples as Instruction Format

All guardrail instructions use a triple structure:

```
Trigger  = Signal (external input) or Event (tool call return)
Context  = In-turn knowledge enrichment from OKF index chain
           (or KG Memory index when available)
Action   = Imperative command or Declarative postcondition
```

This is NOT strict BDD/Gherkin notation. The triple structure captures
the same decomposition benefit without prescriptive notation.

**Context enrichment is NOT optional — it is conditionally required.**
A general context-loading rule in AGENTS.md instructs the agent:

> Before executing any action that involves policy, domain concepts,
> or unfamiliar procedures, consult the knowledge index
> (`~/.agents/knowledge/index.md`) for relevant context.

This is a single rule (~30 tokens) rather than per-rule annotations.
It makes the Context leg of the triple a first-class concern without
bloating each rule entry.

**Knowledge discovery path (primary):** The OKF index chain remains
the primary and required mechanism:
`AGENTS.md → knowledge/index.md → bundle/index.md → concept.md`

**Knowledge discovery path (accelerated, optional):** When KG Memory
index is available, `search_nodes` provides a deterministic shortcut
that collapses the chain to a single tool call. See S6.

In the flat table format, the triple renders as:

| # | Trigger | Action |
|---|---------|--------|

The trigger column captures the When. The action column captures the
Then. The Context leg is governed by the general context-loading rule
rather than per-row annotations.

**Rationale:** Evaluated strict BDD, free-form prose, and
Trigger/Context/Action triples. BDD keywords add token cost without
measurable compliance improvement. Free-form prose lacks decomposition
discipline. Triples give structural consistency at zero notation
overhead. Making Context conditionally required (vs "optional") ensures
the agent actively enriches its understanding before acting on
policy-sensitive or domain-specific rules.

### S3. Flat Guardrail Table — No Categories

Use a single flat table with 12 rules (11 from v5 draft + 1 context-
loading rule from S2). No category labels. No enforcement levels.

**Decisions and rationale for what was dropped:**

- **Categories (Procedure/Gate/Stance):** Evaluated three taxonomies —
  Gate/Rule/Habit (enforcement level), Procedure/Gate/Stance
  (scope × prose type), and flat (no categories). Categories were
  redundant. The trigger column ('Always' vs discrete event) and
  action format (numbered steps vs ✅ checklist) already self-describe
  the rule type. Saves 103 tokens vs categorized version.

- **Enforcement levels (⛔ hard vs ⚖️ soft):** The LLM has no
  graduated compliance engine. Both levels rely on the same mechanism —
  model reads instruction, chooses to comply or not. ⛔ GATE markers
  don't produce measurable compliance difference over ⚖️.

**Anti-Sycophancy split:** Split into two rules:
- **Communication style** — no validation phrases, lead with substance,
  name risks proactively
- **Conflict resolution** — don't reverse position without new
  information, quote conflicting guardrails, log overrides

Cost: ~20 tokens. Benefit: each rule has a single concern, reducing
the chance the model selectively drops constraints from an overloaded
rule.

**Rule organization:** Discrete-triggered rules first, then continuous
('Always') behavioral rules. This ordering provides implicit grouping
without explicit labels.

### S4. Signal Routing: Non-Skill Routes Only

The Signal Routing table retains only LLM-direct routes (memory
writes, preference writes, git shorthand). Skill-routed signals are
removed — reduced from 8 to 6 rows.

**Rationale:** Skill signals appeared in both the routing table and
each skill's `description` field — double encoding with divergence
risk. Skills self-route through their description field; the routing
table adds no value for them.

### S5. Externalize Complex Workflows to Skills

Rules whose action contains complex multi-step workflows delegate to
a dedicated skill. The AGENTS.md entry retains only the trigger and a
`load_skill` reference.

**Primary candidate:** Git Push Safety — the largest workflow in
current AGENTS.md (387 tokens, 8 steps, conditional branching). A new
`agentfs-git-push` skill absorbs this workflow.

**Risk assessment:** Originally assessed as HIGH risk for compliance
regression. Downgraded to LOW — the risk of the model not following
an inline instruction equals the risk of it not following the
instruction to load a skill. The gate trigger is identical in both
versions.

**What stays inline:** Rules with simple postconditions (2–5 items).
Signal-First Dispatch (Rule 1) — it's the bootstrap loader and cannot
depend on skill loading. Continuous behavioral rules — no discrete
trigger for skill loading.

**Rationale:** Follows the agent-as-orchestrator principle — AGENTS.md
is the blueprint, skills are the instructions, scripts are the
execution.

### S6. KG Memory as Optional Knowledge Index

Add KG Memory MCP server as an **optional, complementary search
index** over OKF knowledge bundles. KG entities map to bundles and
concepts with `Source:` observations pointing to the actual Markdown
files.

**Relationship to OKF:** KG Memory is a derived acceleration layer.
The OKF index chain is the primary, required discovery mechanism
(see S2). KG Memory does NOT replace OKF — it provides a faster
lookup path when available:

| Component | Role | Required? |
|---|---|---|
| OKF index chain | Primary knowledge discovery | Yes — always |
| KG Memory index | Deterministic search shortcut | No — optional accelerator |

When KG Memory is enabled: `search_nodes` collapses 3–4 hop index
chain to a single deterministic tool call.
When not enabled: the system operates on the OKF index chain alone —
no functionality is lost.

KG Memory is **not used** for guardrails, signals, or memories. It
indexes knowledge concepts only.

**Cost:** ~500 tokens/turn baseline when enabled (10 tool definitions).

**Goose-specific integration:** Since KG Memory MCP is a Goose
extension, a new `goose-kgm` skill manages its lifecycle:
- `setup` — configure and install the KG Memory extension
- `teardown` — remove configuration
- `enable` / `disable` — toggle the extension (disabled by default)
- `status` — check current state

**KGM index sync:** Integrated into the existing `agentfs-setup`
sync workflow. When `sync agentfs` runs, it detects whether KGM is
enabled and conditionally triggers a reindex of OKF bundles into the
KG. This keeps the sync workflow unified — `agentfs-setup` owns the
"what needs syncing" decision; `goose-kgm` owns the "how to sync KGM"
execution. The reindex is skipped silently when KGM is not enabled.

**Open problems:** JSONL not diff-friendly for version control,
KGM entity schema design for OKF bundles.

**Rationale:** Knowledge bundles lack the deterministic signal-based
loading that skills have via `load_skill`. KG search gives knowledge
the same signal → deterministic lookup → full content path. Making it
optional preserves agent-agnostic compatibility.

## Conceptual Framework

### Autonomy Model

Imperative and declarative instruction prose represent different
**autonomy levels** granted to the LLM core:

| Prose Style | Autonomy | Agent Behavior |
|---|---|---|
| **Imperative** | Low — follow prescribed sequence | Agent executes steps in order, minimal deviation |
| **Declarative** | High — achieve postcondition | Agent plans and sequences its own steps |

Use imperative when step order matters (dependencies between steps).
Use declarative when outcome matters more than path.

### Agentic Controller Architecture

The LLM is always an **orchestrator** functioning inside an Agentic
Controller. The Agentic Controller wraps the LLM core with runtime
infrastructure (tool dispatch, MCP, event loops).

```
┌─────────────────────────┐
│   Agentic Controller    │  ← The system (Goose, Claude Code, etc.)
│  ┌───────────────────┐  │
│  │       LLM         │  │  ← Core reasoning, always orchestrates
│  └───────────────────┘  │
│  ┌───────────────────┐  │
│  │  Runtime / Infra  │  │  ← Tool dispatch, MCP, hooks, event loops
│  └───────────────────┘  │
└─────────────────────────┘
```

AgentFS instructions target the LLM core. The runtime layer is
outside AgentFS's scope (agent-agnostic constraint).

### Collaboration Patterns

Using classic BPM terminology, **collaboration** encompasses both
orchestration and choreography:

| Scope | Pattern | Why |
|---|---|---|
| **Intra-controller** | **Orchestration** | Single LLM core sequences tool calls, evaluates results, decides next step. All flows through the central reasoner. |
| **Inter-controller** | **Choreography** | No single agent owns the end-to-end flow. Each controller reacts to shared events/artifacts and acts autonomously on its own scope. |

**Design principle:** Orchestrate in small/close scope. Choreograph
for larger scale.

The Agentic Controller's activation mode determines its collaboration
role:

| Mode | Activation | Controller Role |
|---|---|---|
| **Passive** | Receives command from external orchestrator | Subordinate — reacts to imperative |
| **Active** | Monitors/watches for events, acts autonomously | Independent — reacts to declarative signals |

AgentFS implements inter-controller choreography through shared
artifacts: multiple agents (Goose, Claude Code) operate on the same
`.agents/` structure without a central coordinator. Cross-agent
discovery (Rule 3) is a choreography convention — translating
external agent artifacts into AgentFS-native rules.

## Design Constraints

- **Agent-agnostic.** No dependency on Goose-specific features (hooks,
  built-in extensions). Must work for any LLM-based agent that reads
  AGENTS.md. Goose-specific capabilities (KGM) are managed via
  dedicated Goose skills, not embedded in core AgentFS.
- **Graceful degradation.** All optional components (KG Memory) fall
  back to existing mechanisms when unavailable.
- **OKF-primary.** OKF index chain is the required knowledge discovery
  mechanism. KGM is a derived accelerator, not a replacement.
- **Single source of truth.** KG is a derived index, not a replacement
  for OKF bundles. AGENTS.md is the authoritative guardrail source.
- **Skill principles preserved.** Externalized workflows follow
  existing skill creation principles (non-interactive scripts,
  agent-as-orchestrator, five quality principles).

## Content Coverage Audit

87 items checked between v4.x and v5 flat version:

- **Intentional removals:** 3 skill-routed signals (redundant with
  skill description fields)
- **Delegated to skills:** 11 items (8 to new `agentfs-git-push`
  skill, 3 to existing `agentfs-setup` scripts)
- **True content loss:** Zero

## Documentation

This strategy document and the subsequent action plan will be
incorporated into the `agentfs-setup` skill as reference documentation
for future AgentFS evolution and maintenance.

## Prerequisites for Implementation

1. Create `agentfs-git-push` skill (absorbs Git Push Safety workflow)
2. Verify `agentfs-setup` skill covers all delegated filesystem
   integrity details
3. Create `goose-kgm` skill (lifecycle management for KG Memory
   extension — disabled by default)
4. Add conditional KGM reindex to `agentfs-setup` sync workflow
5. Archive this strategy doc and action plan into `agentfs-setup`
   skill reference docs
