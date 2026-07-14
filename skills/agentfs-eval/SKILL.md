---
name: agentfs-eval
description: >-
  Assess the maturity of an AgentFS workspace through three layers of
  verification: structural assertions (deterministic), behavioral
  assertions (forensic), and semantic assertions (constrained LLM
  classification). Produces a maturity report with levels L0–L5.
metadata:
  version: "1.0"
  tags: [agentfs, eval, maturity, guardrails, audit]
---

# AgentFS Eval

Assess the health and maturity of an AgentFS workspace through
three layers of progressively deeper verification.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0 |
| **Trigger** | Explicit only — user asks to run eval |
| **Scope** | Evaluates a PROJECT-scoped `.agents/` directory |
| **Dependencies** | `bash`, `find`, `grep`, `stat`, `git` (optional but recommended) |
| **LLM required** | Layer 3 only (semantic rubrics) |

## Recommended Usage

For the most reliable evaluation, run this skill in a **fresh session**
against the target project directory. This eliminates conversational
bias from prior work in the same session.

Example prompts:

> "Run agentfs eval"
> "Run agentfs eval against /home/user/projects/my-project"

The skill works against any directory containing `.agents/` — it does
NOT need to be the current working directory. If no path is provided,
it defaults to the current working directory.

### Why a Fresh Session?

- **Eliminates self-evaluation bias** — the agent that did the work
  should not be the one evaluating it
- **Removes conversational context** — no memory of what the user
  "wanted," just cold assessment of filesystem state
- **Reduces sycophancy pressure** — no incentive to report good
  results to please the user who just watched it work
- **More capable models** give stronger classification accuracy
  for Layer 3 semantic rubrics

## Maturity Levels

| Level | Name | Requirements |
|-------|------|--------------|
| **L0** | Absent | No `.agents/` directory exists |
| **L1** | Scaffolded | `.agents/` exists with valid structure |
| **L2** | Structurally Sound | All Layer 1 assertions pass |
| **L3** | Behaviorally Safe | Layer 1 + Layer 2 assertions pass |
| **L4** | Semantically Accurate | Layer 1 + Layer 2 + Layer 3 assertions pass |
| **L5** | Self-Correcting | Agent can run eval, detect violations, and fix them |

## Execution Steps

When a user asks to run eval, follow these steps:

### Step 1: Determine Target

If the user provides a path, use it. Otherwise use the current
working directory.

```bash
TARGET="${user_provided_path:-.}"
```

Verify `.agents/` exists at the target:

```bash
if [ ! -d "$TARGET/.agents" ]; then
  echo "L0 — Absent: No .agents/ directory at $TARGET"
  # Stop here — nothing to evaluate
fi
```

If `.agents/` does not exist, report **L0 (Absent)** and stop.

### Step 2: Run Layer 1 — Structural Assertions

Run the structural check script:

```bash
bash <skill-dir>/scripts/agentfs-check.sh "$TARGET"
```

This produces a pass/fail report for 7 structural assertions.
No LLM involvement — pure shell.

### Step 3: Run Layer 2 — Behavioral Assertions

Run the behavioral check script:

```bash
bash <skill-dir>/scripts/agentfs-behavior.sh "$TARGET"
```

This checks for accumulated evidence (git history, log.md entries,
MEMORY.md content) and runs behavioral assertions against what it
finds. Assertions without sufficient evidence report `N/A`.

No LLM involvement — pure shell.

### Step 4: Run Layer 3 — Semantic Assertions

For each rubric YAML file in `<skill-dir>/rubrics/`:

1. Read the rubric file
2. Read the target content specified by the rubric
3. If target content is empty or absent → report `N/A` for this rubric
4. For each entry/item in the target content:
   a. Apply the `prompt_template` from the rubric, substituting the
      entry content into the `{entry}` placeholder
   b. Answer the closed-ended question — select ONLY from the
      enumerated choices
   c. Record the answer
   d. Repeat `vote_count` times if specified (take majority vote)
5. Score: compare answers against `pass_answers` and `fail_answers`
6. Report pass/fail per entry with the `fail_routing` message if failed

**Critical: The LLM acts as a CLASSIFIER, not a judge.** Answer only
the specific question asked. Do not provide open-ended commentary
on content quality.

### Step 5: Produce Report

Use the template at `<skill-dir>/templates/report.md` to structure
the output. Include:

- Target path and date
- Git status (tracked? how many commits?)
- Per-layer results with pass/fail/N/A per assertion
- Details for any failures or warnings
- Overall maturity level (lowest layer with all-pass determines level)
- Recommendations for reaching the next level

### Maturity Level Calculation

```
If .agents/ does not exist           → L0 (Absent)
Else if .agents/ exists              → L1 (Scaffolded)
  If ALL Layer 1 assertions pass     → L2 (Structurally Sound)
    If ALL Layer 2 assertions pass   → L3 (Behaviorally Safe)
      If ALL Layer 3 assertions pass → L4 (Semantically Accurate)
```

Assertions reporting `N/A` (insufficient evidence) are **excluded**
from the pass/fail calculation — they do not block advancement but
are noted in the report.

L5 (Self-Correcting) is assessed by a human observing whether the
agent can run eval, detect violations, and fix them in the same
session. It is not automatically scored.

## Layer 1: Structural Assertions

Pure shell. Always runnable. Script: `scripts/agentfs-check.sh`

| ID | Assertion | Method |
|----|-----------|--------|
| S1 | **Link Integrity** | Parse `[text](path)` links from all `.md` files under `.agents/`, resolve each path relative to the file, report broken ones |
| S2 | **Log Monotonicity** | Parse `## YYYY-MM-DD HH:MM` headings from `log.md`, verify strictly descending order |
| S3 | **Index Completeness** | For every `SKILL.md` under `skills/`, verify a matching row in `skills/index.md`. For every profile dir under `profiles/`, verify a matching row in `profiles/index.md` |
| S4 | **Frontmatter Validity** | Every `SKILL.md` has YAML frontmatter with `metadata.tags` present and non-empty |
| S5 | **Scope Correctness** | No `memories/` or `profiles/` under `~/.agents/`. No `knowledge/` under `./.agents/` |
| S6 | **Changelog Monotonicity** | Files containing a `Changelog` section have timestamps in descending order |
| S7 | **Orphan Detection** | Files under `.agents/` (excluding `log.md`, `index.md`, `.session-marker`, `.checkpoint`) not linked from any `index.md` |

## Layer 2: Behavioral Assertions

Pure shell. Requires accumulated evidence. Script: `scripts/agentfs-behavior.sh`

| ID | Assertion | Evidence Needed | Method |
|----|-----------|----------------|--------|
| B1 | **Action-Log Correlation** | `log.md` with >1 entry + git history | Compare `git log -- .agents/` against `log.md` entries. Every git-recorded file change should have a corresponding log entry |
| B2 | **Log-Git Timestamp Alignment** | `log.md` + git history | For each `log.md` entry, check if a git commit touching the mentioned file exists within ±10 minutes |
| B3 | **Scope Leakage** | Git history in both scopes | Check for commits that modified both `~/.agents/` and `./.agents/` simultaneously |
| B4 | **Idempotency Spot-Check** | At least one skill with executable scripts | `md5sum` state, re-run a skill's setup steps, `md5sum` again, diff |
| B5 | **Rule-in-Memory Heuristic** | `MEMORY.md` with entries | `grep` for imperative language ("always", "never", "must", "shall", "enforce") in `MEMORY.md` — warn if found |

### Evidence Accumulation

| Project State | Assessable Checks |
|---------------|-------------------|
| Fresh scaffold (just ran `agentfs-setup`) | None — all report N/A |
| After a few sessions (memories, skills created) | B1, B2, B5 |
| Mature project (rich history, multiple skills) | B1, B2, B3, B4, B5 |

## Layer 3: Semantic Assertions

Constrained LLM classification. Rubrics in `rubrics/` directory.

| ID | Rubric File | Target Content | Question |
|----|-------------|---------------|----------|
| R1 | `memory-classification.yaml` | Each entry in `MEMORY.md` | "Is this an experience (A), a rule (B), or a preference (C)?" |
| R2 | `reference-verification.yaml` | `MEMORY.md` entries mentioning files/functions | LLM extracts references → script checks if they exist |
| R3 | `sycophancy-detection.yaml` | `log.md` entries + `AGENTS.md` guardrails | "Does this logged action contradict any guardrail?" |
| R4 | `skill-accuracy.yaml` | `SKILL.md` files with shell code blocks | `shellcheck` + `which` on commands, then LLM checks logical flow |

### Anti-Bias Design

- **Hallucination resistance**: LLM classifies presented content,
  not recalled content — nothing to hallucinate
- **Stochasticity resistance**: Fixed answer choices bound variance;
  majority vote (`vote_count: 3`) reduces noise
- **Sycophancy resistance**: Classification task with no user
  preference to agree with

### L3 → L2 Graduation

Over time, patterns observed in Layer 3 results can be graduated
to Layer 2 deterministic checks. **This is NOT automatic.** It is
a human-driven skill update:

1. Human runs eval several times, reads reports
2. Human notices a recurring L3 pattern (e.g., "entries with 'Always'
   are always classified as rules")
3. Human asks to add a grep heuristic to the L2 script
4. Skill maintainer updates `agentfs-behavior.sh`
5. Next eval: L2 catches easy cases cheaply, L3 still catches subtle ones

The rubric YAML files never change automatically. The L2 script
grows over time through human observation of L3 results.

## Design Principles

This skill is designed to enforce three non-negotiable principles:

### Safe Agent Actions
- **Idempotency**: Eval verifies skills can be re-run safely (B4)
- **Resumability**: Eval checks for checkpoint discipline (future)
- **Auditability**: Eval cross-references log.md against actual changes (B1, B2)

### AI Flaw Mitigation
- **Hallucination**: Structural checks catch invented files/links (S1, S7);
  reference verification catches invented references (R2)
- **Stochasticity**: Structured formats reduce output variance (S4);
  majority vote reduces classification noise (R1–R4)
- **Sycophancy**: Anti-sycophancy detection catches guardrail violations (R3);
  rule-in-memory heuristic catches mis-routed content (B5, R1)

## Supporting Files

- `scripts/agentfs-check.sh` → `load_skill(name: "agentfs-eval/scripts/agentfs-check.sh")`
- `scripts/agentfs-behavior.sh` → `load_skill(name: "agentfs-eval/scripts/agentfs-behavior.sh")`
- `rubrics/memory-classification.yaml` → `load_skill(name: "agentfs-eval/rubrics/memory-classification.yaml")`
- `rubrics/reference-verification.yaml` → `load_skill(name: "agentfs-eval/rubrics/reference-verification.yaml")`
- `rubrics/sycophancy-detection.yaml` → `load_skill(name: "agentfs-eval/rubrics/sycophancy-detection.yaml")`
- `rubrics/skill-accuracy.yaml` → `load_skill(name: "agentfs-eval/rubrics/skill-accuracy.yaml")`
- `templates/report.md` → `load_skill(name: "agentfs-eval/templates/report.md")`
- `references/design-decisions.md` → `load_skill(name: "agentfs-eval/references/design-decisions.md")`

## Companion Skills

- **`agentfs-setup`** — Scaffolds the `.agents/` directory that eval assesses
- **`agentfs-profile`** — Creates profiles whose structure eval verifies
- **`skill-index`** — Maintains the `skills/index.md` that eval checks

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-13 15:38 | v1.0 — Initial design: three-layer eval (structural, behavioral, semantic), maturity levels L0–L5, explicit trigger only, fresh session recommendation |
