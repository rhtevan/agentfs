# AgentFS Eval — Design Decisions

This document captures the rationale behind the `agentfs-eval` skill's
design, distilled from the design session on 2026-07-13.

## Context

AgentFS provides a model-agnostic and agent-agnostic filesystem
convention giving AI agents a persistent workspace. As the design
matured, a gap emerged: guardrails in `AGENTS.md` are **prescriptive**
(they tell the agent what to do) but not **assertive** (they don't
verify the agent actually did it).

This is equivalent to having coding standards without a linter.
The guardrails rely entirely on the agent's willingness and ability
to follow instructions — which is exactly what hallucination,
stochasticity, and sycophancy undermine.

## Guiding Principles

Three non-negotiable principles drive the design:

### 1. Safe Agent Actions

| Property | Requirement |
|----------|-------------|
| **Idempotency** | Actions can be retried without catastrophic consequences |
| **Resumability / Revertibility** | A series of actions can be resumed or reverted after agent interruptions |
| **Auditability** | An audit trail exists for all actions |

### 2. AI Flaw Mitigation

| Flaw | Definition | Risk to AgentFS |
|------|-----------|------------------|
| **Hallucination** | Generating content not grounded in reality | Agent invents files, references, or observations that don't exist |
| **Stochasticity** | Producing different outputs for the same input | Same skill produces inconsistent workspace structures across runs |
| **Sycophancy** | Agreeing with the user even when wrong | Agent silently complies with requests that violate guardrails |

## Decision 1: Three-Layer Verification Architecture

**Decision:** Separate eval into three layers with fundamentally
different verification paradigms.

**Rationale:** A single approach can't cover all assertion types.
Deterministic checks catch structural violations cheaply. Forensic
correlation catches behavioral problems without an LLM. Only semantic
content analysis requires LLM involvement — and even then, it's
constrained to classification, not open-ended judgment.

| Layer | Paradigm | LLM? | What It Verifies |
|-------|----------|:----:|------------------|
| L1: Structural | Filesystem assertions | No | Physical state of `.agents/` tree |
| L2: Behavioral | Forensic evidence correlation | No | Whether agent actions were safe and logged |
| L3: Semantic | Constrained LLM classification | Yes | Whether content is correctly classified and accurate |

## Decision 2: No Golden Test Cases

**Decision:** Do not maintain a set of golden test cases or synthetic
test scenarios.

**Rationale:**

| Golden Test Cases | Rubric-Based Eval (chosen) |
|-------------------|---------------------------|
| Tests synthetic examples | Tests **real workspace content** |
| Becomes stale as guardrails change | Rubrics reference guardrails — auto-relevant |
| Pass/fail on exact match | Pass/fail on classification — tolerates variation |
| Fixed set, can be memorized by LLM | Applied to every entry — can't be gamed |
| Human maintains test data | Human maintains rubric questions (smaller surface) |

The eval tests **what actually happened**, not what might happen in
a hypothetical scenario.

## Decision 3: Constrained LLM Classification (Layer 3)

**Decision:** Use the LLM as a **classifier** with closed-ended
questions, not as an open-ended judge.

**Rationale:** An LLM evaluating free-form content with free-form
judgment is subject to the same flaws (hallucination, sycophancy,
stochasticity) we're trying to detect. Constraining to multiple-choice
classification:

- **Hallucination resistance**: LLM classifies presented content,
  not recalled content — nothing to fabricate
- **Stochasticity resistance**: Fixed answer choices bound variance;
  majority vote (`vote_count: 3`) further reduces noise
- **Sycophancy resistance**: Classification task with no user
  preference to agree with — there's no social pressure toward
  any particular answer

## Decision 4: Explicit Trigger Only

**Decision:** The eval runs only when a human explicitly asks for it.
No hooks, no cron, no session boundary automation.

**Rationale:** Simplicity first. Automated triggers (git hooks,
session boundaries, scheduled jobs) were considered and rejected
for v1.0 because:

- They add complexity before the core eval is proven
- Session-boundary triggers rely on agent cooperation (circular —
  the agent must follow the instruction to evaluate itself)
- Git hooks and cron are agent-external and valuable, but they're
  a v2.0 optimization, not a v1.0 requirement

The trigger model can evolve later. The eval logic itself is
trigger-agnostic.

## Decision 5: Fresh Session Recommendation

**Decision:** Recommend (but don't require) running eval in a fresh
session, ideally with a capable model.

**Rationale:**

- **Eliminates self-evaluation bias** — the agent that did the work
  should not evaluate it
- **Removes conversational context** — no memory of what the user
  "wanted," just cold assessment of filesystem state
- **Reduces sycophancy pressure** — no incentive to report good
  results to the user who watched the work happen
- **More capable models** give stronger L3 classification accuracy

This is a recommendation in the SKILL.md prose, not a mechanism.
The skill works in any session — fresh or not.

## Decision 6: Git as Default in PROJECT Mode

**Decision:** `agentfs-setup` initializes a git repository in the
project directory (parent of `.agents/`) by default in PROJECT mode.

**Rationale:** Git provides the forensic evidence that Layer 2
behavioral checks depend on:

- `git log -- .agents/` shows what actually changed, when, by whom
- `git diff` provides content-level diffing for action-log correlation
- `git checkout` provides free checkpoint/revert capability
- Git history is tamper-resistant — `log.md` can be edited by a rogue
  agent, but git history can't (without force-push)

Without git, L2 degrades to timestamp-only correlation against `log.md`
claims. The script detects git availability and adapts.

## Decision 7: Memories NOT Excluded from Git

**Decision:** Remove `.agents/memories/` from `.gitignore`. Track
everything under `.agents/` including memories.

**Rationale:**

The original exclusion was motivated by privacy (USER.md contains
personal information about the user). However:

- Privacy is the user's decision at **push time**, not gitignore time
- Local git tracking provides audit evidence without any sharing risk
- L2 behavioral checks on MEMORY.md need content-level diffing
- The user controls what they push to remote repositories

The guardrail system itself (proposed #12 Anti-Sycophancy) provides
warnings about sensitive content at commit time.

## Decision 8: L3 → L2 Graduation Is Human-Driven

**Decision:** Patterns discovered by Layer 3 semantic checks are
NOT automatically promoted to Layer 2 deterministic checks. A human
observes patterns in eval reports and asks for the upgrade.

**Rationale:**

1. **A grep heuristic needs human judgment.** "Always" in "I always
   see this error" is an experience, not a rule. Only a human decides
   what's safe to grep for.
2. **Automatic graduation would itself be subject to AI flaws.** An
   LLM deciding "I should write a grep rule" could hallucinate a bad
   regex or over-generalize.
3. **Eval must be read-only.** If running eval mutates the eval skill
   itself, running it twice could produce different checks the second
   time — violating idempotency.

The lifecycle:

```
Run eval v1.0 → human reads reports → notices pattern
→ human asks to add L2 heuristic → skill updated to v1.1
→ run eval v1.1 → L2 catches easy cases, L3 catches subtle ones
```

## Decision 9: Graceful Degradation

**Decision:** Eval reports `N/A` for checks without sufficient
evidence rather than failing or skipping silently.

**Rationale:** A fresh project has no behavioral or semantic
evidence to evaluate. Rather than:

- **Failing** (incorrect — no evidence ≠ bad evidence)
- **Passing** (incorrect — no evidence ≠ good evidence)
- **Skipping silently** (loses information about what's assessable)

The eval reports `N/A (reason)` which honestly communicates:
"I cannot assess this yet because [specific evidence is missing]."
The maturity level calculation excludes N/A results — they don't
block advancement but are noted in the report.

## Maturity Model

| Level | Name | What Must Pass |
|-------|------|--------------|
| L0 | Absent | Nothing — no `.agents/` exists |
| L1 | Scaffolded | `.agents/` exists with basic structure |
| L2 | Structurally Sound | All Layer 1 assertions pass |
| L3 | Behaviorally Safe | All Layer 1 + Layer 2 assertions pass |
| L4 | Semantically Accurate | All Layer 1 + Layer 2 + Layer 3 assertions pass |
| L5 | Self-Correcting | Human-assessed: agent runs eval, detects violations, fixes them |

L5 is intentionally not auto-scored. It requires observing the agent
in action — can it find a problem and fix it without being told how?
This is the highest bar and represents genuine agent maturity.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-13 15:43 | v1.0 — Initial design decisions captured from design session |
