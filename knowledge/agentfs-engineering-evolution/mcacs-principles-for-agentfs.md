# MCACS Principles for AgentFS

- **Type:** Framework
- **Status:** Active
- **Source:** Session analysis grounded in David Farley's *Modern Software Engineering* (Chapters 9–13, Part III: "Optimize for Managing Complexity")

## Summary

Five interdependent engineering principles — Modularity, Cohesion, Abstraction,
Separation of Concerns, Coupling (MCACS) — applied as tools for evolving AgentFS
from a frontier-model-dependent system to one operable by mid-range (14B-class) models.

## The Five Principles Mapped to AgentFS

### 1. Modularity

Each skill component must be independently testable. A module boundary exists
(skill directories, scripts, SKILL.md) but some skills have no internal structure —
one monolithic prose block with no deterministic checkpoints.

**Gap:** Skills like `agentfs-readme-audit` have zero scripts. The agent must
parse prose, extract shell commands, execute them in sequence, collect outputs,
and reason about results — all in one undivided chain.

**Fix direction:** Extract deterministic operations into scripts. Each script
is a module with clear inputs, outputs, and testable behavior.

### 2. Cohesion

Things that change together belong together. Some skills mix three distinct
concerns in one prose block: data gathering, scope resolution, and semantic
analysis. These change for different reasons.

**Gap:** Data gathering (changes when filesystem layout changes), scope
resolution (changes when scopes change), and semantic analysis (changes when
audit dimensions change) are interleaved in single SKILL.md sections.

**Fix direction:** Group by reason for change. Data gathering and scope
resolution go into scripts. Semantic analysis stays in SKILL.md prose.

### 3. Separation of Concerns

Essential complexity (decisions, judgments — what the LLM is for) must be
separated from accidental complexity (counting files, resolving paths — what
scripts are for).

**Gap:** SKILL.md prose mixes "run these shell commands" with "compare and
judge the results." A frontier model handles both. A 14B model conflates them
or fabricates the accidental parts.

**Fix direction:** Scripts handle all accidental complexity. SKILL.md prose
handles only essential complexity. The agent's job becomes: run script → read
structured output → apply judgment → report.

### 4. Abstraction

The interface a skill presents to the agent should hide implementation. The
consumer (agent) should not need to know internals to operate the skill.

**Gap:** Some skills expose raw shell commands in markdown code blocks that the
agent must extract and execute. The interface is "read this document and figure
out what to do." That's a leaky abstraction — the consumer must know the
implementation.

**Fix direction:** Wrapper scripts hide implementation. The agent calls one
script and reads structured output. Farley's printer driver analogy: the
application says "print this," the driver handles the details.

### 5. Coupling

AgentFS skills are tightly coupled to model capability. Multi-hop reasoning
chains, inline code block extraction, and implicit scope resolution all assume
frontier-class reasoning.

**Gap:** The system has semantic, functional, and operational coupling to the
operator's capability level. If the operator is not a frontier model, the
system fails.

**Fix direction:** Reduce operator-capability coupling by moving reasoning-
intensive steps into deterministic scripts or Semantic Decision Model (SDM)
calls. The agent orchestrates — it does not perform accidental complexity.

## Discovered Anti-Pattern: Frontier Model Implicit Assumptions

**Found in:** Phase 2.5 validation of readme-audit v3.0.0

The authoring model (frontier) wrote `gather-state.sh` assuming CWD
is always inside a git repo. This assumption was never stated, never
tested, and invisible to the author. When the 14B operating model
ran the script from a Goose session with a different CWD, the script
failed. The frontier model then misattributed the failure to the 14B
model's "behavioral gap" — compounding the error.

**MCACS classification:** Abstraction failure. The script's interface
leaked an internal assumption. A well-abstracted script accepts
explicit inputs (`--scope user`) and does not depend on implicit
execution context.

**Mitigation for skill-gen (Phase 1):**
- Test scripts from non-obvious CWDs (`/tmp`, `~`, non-git dirs)
- Record `implicit_assumptions` in `qoo-profile.yaml`
- Checklist: "Does this script work without any CWD assumptions?"
- Accept that the authoring model's assumptions are invisible to
  itself — only cross-model execution or explicit testing exposes them

## Key Insight

These are not independent rules. They are interdependent lenses:
- Testability drives modularity
- Modularity requires cohesion
- Separation of concerns enables both
- Abstraction manages coupling
- Coupling reduction enables independent operation

The tension between these forces is the core design challenge, not a problem
to be eliminated.

## Source

David Farley, *Modern Software Engineering: Doing What Works to Build Better
Software Faster* (Addison-Wesley, 2021), Part III: Chapters 9–13.
