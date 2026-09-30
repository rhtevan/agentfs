---
name: agentfs-violation-chk
description: >
  check violations, violation audit, self audit,
  behavioral compliance, hey check violations
metadata:
  author: agentfs
  version: "1.0.1"
  tags: [agentfs, audit, compliance, guardrails, behavioral]
user-invocable: true
disable-model-invocation: false
---

# AgentFS Violation Check

Full behavioral self-audit of session conduct against the agent's
rules (AGENTS.md guardrails) and principles (SOUL.md). Unlike
`agentfs-ctx-chk` which audits the context *files* for structural
health, this skill audits the agent's *behavior* during the current
session for compliance violations.

Use this when you suspect the agent has drifted, after context
compaction, or as a periodic integrity check. The lightweight
version of this check runs automatically at Session Canary
re-verification points (turn 5, then every 10 turns) — this skill
is the full, explicit version.

## Prerequisites

- `AGENTS.md` is loaded in context (contains rules to audit against)
- `.agents/SOUL.md` is accessible (contains principles to audit against)
- Session has ≥2 turns of history to audit

## How It Differs from Related Skills

| Skill | Question |
|-------|----------|
| `agentfs-violation-chk` (this) | "Did I violate my own rules this session?" |
| `agentfs-ctx-chk` | "Are the context files well-engineered?" |
| `agentfs-eval` | "Is this workspace structurally healthy?" |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Audit all AGENTS.md rules against session behavior | Report covers every numbered rule |
| S2 | Audit all SOUL.md principles against session behavior | Report covers every named principle |
| S3 | Identify specific turns where violations occurred | Each finding cites the turn or action |
| S4 | Distinguish severity levels | Findings classified as 🔴 violation, 🟡 borderline, 🟢 clean |
| S5 | Produce actionable remediation | Each violation includes what should have been done |

## Steps

### Step 1 — Gather Audit Baseline

Read the rules and principles that govern behavior:

1. Review the **Rules** section of `AGENTS.md` currently in context.
   List every numbered rule (e.g., Signal Dispatch, Pre-Flight,
   Post-Write, Session Canary, Conflict Resolution, Checkpoint,
   Scope Rules).
2. Review the **Principles** section of `.agents/SOUL.md` currently
   in context. List every named principle (e.g., No assumed inputs,
   Direct communication, Intellectual integrity, etc.).

If either document is not in context, read it before proceeding.

### Step 2 — Review Session History

Walk through the conversation history turn by turn. For each agent
turn, check:

**Rule compliance:**
- Did any `hey` message get treated as a greeting? (Signal Dispatch)
- Were multi-step tasks (≥3 tool calls or ≥2 files) preceded by a
  stated plan? (Pre-Flight)
- Were writes to `.agents/` or `~/.agents/` followed by post-write
  hooks? (Post-Write)
- Was the canary emitted on turn 1? Re-verified at checkpoints?
  (Session Canary)
- Were any positions reversed without stating what changed?
  (Conflict Resolution)
- Were destructive ops on `.agents/` preceded by checkpoint?
  (Checkpoint)
- Were memories written to correct scope? Skills to correct scope?
  (Scope Rules)
**Principle compliance:**
- Did the agent proceed without asking when information was missing?
  (No assumed inputs)
- Did any response open with filler/validation phrases? (Direct
  communication)
- Was a position reversed due to social pressure rather than new
  evidence? (Intellectual integrity)
- Were complex solutions chosen over simpler alternatives?
  (Reliability over cleverness)
- Were symptoms patched without tracing root cause? (Root cause,
  not symptom)
- Were risks left unnamed? (Proactive risk naming)
- Did the agent make aesthetic/domain calls outside scope? (Scope
  discipline)
- Were structured files treated casually? (Data integrity)

### Step 3 — Classify Findings

For each issue found:

| Severity | Criteria |
|----------|----------|
| 🔴 Violation | Clear breach of a mandatory rule or principle |
| 🟡 Borderline | Technically compliant but spirit was not met, or edge case |
| 🟢 Clean | No issues found for this rule/principle |

### Step 4 — Produce Report

Present findings in this format:

```markdown
## Violation Check Report

**Session:** [canary name] | **Turns audited:** [N] | **Timestamp:** [ISO 8601]

### Rules

| # | Rule | Status | Detail |
|:-:|------|:------:|--------|
| 1 | Signal Dispatch | 🟢 | — |
| 2 | Pre-Flight | 🔴 | Turn 3: edited 3 files without stating plan |
| ... | ... | ... | ... |

### Principles

| # | Principle | Status | Detail |
|:-:|-----------|:------:|--------|
| 1 | No assumed inputs | 🟢 | — |
| 2 | Direct communication | 🟡 | Turn 1: opened with "Sure!" |
| ... | ... | ... | ... |

### Summary

- **Violations (🔴):** N
- **Borderline (🟡):** N
- **Clean (🟢):** N

### Remediation

1. [What should have been done differently, for each 🔴/🟡]
```

### Step 5 — Lightweight Mode (Canary Integration)

When invoked as part of the Session Canary re-verification (not
the full skill), perform a compressed version:

1. Silently review behavior since last canary check
2. If **no violations found** → do not report anything (zero noise)
3. If **violation found** → report inline with the canary
   re-verification, e.g.:
   > 🐦 Canary re-verified: `walrus-tungsten`
   > ⚠️ Self-check: [brief description of violation]

This step is documented here for reference but is executed by the
Session Canary rule itself, not by loading this skill.

## Gotchas

- **Post-compaction blindness:** After context compaction, earlier
  turns may be summarized or lost. The audit can only cover what
  remains in context. Acknowledge this limitation in the report
  rather than claiming "no violations" with false confidence.
- **Self-audit bias:** The agent auditing its own behavior has an
  inherent bias toward leniency. Mitigate by checking each rule
  mechanically (did the specific action occur? yes/no) rather than
  holistically.


## Verification

- [ ] Report covers every rule in AGENTS.md
- [ ] Report covers every principle in SOUL.md
- [ ] Each finding cites a specific turn or action
- [ ] Severity classifications are justified
- [ ] Post-compaction limitation is acknowledged when applicable

## Tests

| Test | Spec | How to Verify | Expected Result |
|:----:|:----:|---------------|-----------------|
| T1 | S1 | Run after a session with known rule violation | Violation correctly identified and cited |
| T2 | S2 | Run after a session with filler phrase used | Principle violation flagged as 🔴 or 🟡 |
| T3 | S3 | Check that findings reference specific turns | Each 🔴/🟡 cites turn number or action |
| T4 | S4 | Run on a clean session | All items show 🟢, no false positives |
| T5 | S5 | Trigger via canary re-verification with no issues | No output (silent pass) |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
