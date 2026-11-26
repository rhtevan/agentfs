---
name: agentfs-eval
description: >
  eval agentfs, eval agentfs workspace, eval agentfs template,
  agentfs health, agentfs status, agentfs score,
  maturity check, check violations, self audit
metadata:
  version: "2.13.0"
  model-tier: T4
  tags: [agentfs, eval, maturity, guardrails, audit]
user-invocable: true
---

# AgentFS Eval

Assess the health and maturity of an AgentFS workspace through
four stages of progressively deeper verification (S0–S3)
plus runtime compliance from the compliance profile.

## Rules

Do NOT fabricate evaluation scores, maturity ratings, or violation
counts. Every metric MUST come from script output or verifiable
filesystem state. If a check cannot be performed, report N/A —
do not estimate.

## Quick Dispatch

| User says                                          | Run                                                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| "agentfs score", "agentfs status"                  | Stage S0 only. Run `template-check.sh "$PROJECT"`. Stop after reporting score.                      |
| "eval agentfs workspace", "maturity check"         | Workspace mode. Full Eval Sequence Steps 1, 3, 4, 5, then Step 9 (S1–S3 + maturity). Report only: writes nothing. Budget ≤ 2 min. |
| "eval agentfs template"                            | Template mode. Full Eval Sequence Steps 1, 2, 6, 7, 8, then Step 9 (S0 + compliance status + runtime dimensions + static record status). Writes the compliance profile only if the user asks for a campaign. Budget ≤ 1 min without a campaign. |
| "eval agentfs", "agentfs health"                   | Full eval. Execute ALL steps in the Full Eval Sequence below (template mode, then workspace mode, one report). Do NOT skip steps. |
| "check violations", "self audit"                   | Session audit mode. Follow the Session Audit Mode section below. Diagnostic only — no scores persisted. |

Match the most specific row first ("eval agentfs workspace" before
"eval agentfs").

**ROUTING STOP: Find your match above, then jump to that section.
Do NOT read past the matched section. Do NOT run the Full Eval
Sequence unless the match says "Full eval" or names its steps.**

## Session Audit Mode

When the user says "check violations" or "self audit", review the
current session's conversation history against AGENTS.md rules and
SOUL.md principles. This is diagnostic only — no scores are persisted.
Do NOT run any scripts. Do NOT run the Full Eval Sequence.

### Step 1 — Gather Audit Baseline

Read the current project's AGENTS.md rules and SOUL.md principles.
Count the numbered rules and named principles.

### Step 2 — Review Session History

For each rule and principle, scan the conversation history for
compliance or violations. Cite specific turns where violations occurred.

### Step 3 — Produce Report

| # | Rule | Status | Detail |
|---|------|--------|--------|
| 1 | Signal Dispatch | 🟢 / 🟡 / 🔴 | Specific turn or "clean" |

Classify findings as 🔴 violation, 🟡 borderline, 🟢 clean.
Include actionable remediation for each violation.

**END OF SESSION AUDIT MODE. Stop here.**

---

## Full Eval Sequence

Execute ALL steps in order. Do NOT skip steps. Do NOT jump to a
later step because it seems more relevant to the conversation.
The scripts in Steps 2–8 are independent and read-only: you may run
them in parallel. Report results in step order.

### Step 1 — Determine Target

Use the user-provided path. Default to the current working directory.
Verify `.agents/` exists. If absent, report L0 and stop.

### Step 2 — Stage S0: Template Quality Check

```bash
bash ~/.agents/skills/agentfs-eval/scripts/template-check.sh "$TARGET"
```

Report the score. Continue to Step 3.

### Step 3 — Stage S1: Structural Assertions

```bash
bash ~/.agents/skills/agentfs-eval/scripts/agentfs-check.sh "$TARGET"
```

Report pass/fail per assertion. Continue to Step 4.

### Step 4 — Stage S2: Behavioral Assertions

```bash
bash ~/.agents/skills/agentfs-eval/scripts/agentfs-behavior.sh "$TARGET"
```

Report pass/warn/N/A per assertion. Continue to Step 5.

### Step 5 — Stage S3: Semantic Assertions (L4 qualification)

For each rubric YAML file in the skill's `rubrics/` directory
(`memory-classification.yaml`, `reference-verification.yaml`,
`sycophancy-detection.yaml`):

1. Read the rubric file.
2. Read the target content specified by the rubric:
   - R1: each entry in `$TARGET/.agents/memories/MEMORY.md`
   - R2: each entry in `$TARGET/.agents/memories/MEMORY.md` that
     contains artifact references
   - R3: each action entry in `$TARGET/.agents/log.md` cross-referenced
     against guardrails in `$TARGET/AGENTS.md`
3. If target content is empty or absent → report `N/A` for this rubric.
4. For each entry/item in the target content:
   a. Apply the `prompt_template` from the rubric, substituting the
      entry content into the `{entry}` placeholder.
   b. Answer the closed-ended question — select ONLY from the
      enumerated choices.
   c. Record the answer.
   d. Use the rubric's `vote_count` (1 since 2026-11-18: repeated votes in one
      session context are correlated and add no independence).
5. Score: compare answers against `pass_answers` and `fail_answers`.
6. Report pass/fail per entry with the `fail_routing` message if failed.

**Critical: The LLM acts as a CLASSIFIER, not a judge.** Answer only
the specific question asked. Do not provide open-ended commentary
on content quality.

Report pass/fail/N/A per rubric. Continue to Step 6.

### Step 6 — Runtime Compliance: Status

If the user says "skip runtime compliance" (legacy: "skip tier 3 qoo",
"skip benchmarks"), skip Steps 6–7 and continue to Step 8.

```bash
bash ~/.agents/scripts/update-compliance.sh --check
```

Report each tier's record (model, overall, version, date) and the
rules-template changes listed since the records. If changes are listed,
read the diff, propose a class — `none` (cosmetic), `smoke` (wording,
intent unchanged), `partial` (functional, some rules), `full` (release
or several rules) — and ask the user to confirm. Do NOT run a benchmark
unless the user explicitly asks; re-measuring is
`run-parallel.sh smoke|real [--tiers …]`. Never record with
`update-compliance.sh --tests …` into the real profile: it replaces the
whole tier entry (other rules become `not_tested`).

### Step 7 — Runtime Compliance: Dimensions

```bash
bash ~/.agents/skills/agentfs-eval/scripts/runtime-compliance.sh
```

Computes the CECX runtime dimensions deterministically from
`compliance-profile.yaml`, per target tier (T3, T2) against the
frontier tier (T4): `rule_pass_rate`, `frontier_target_delta`,
`per_rule_comprehension`, `stochastic_variance`. `no_fabrication` is
enforced by the benchmark graders (full tool chain required per run).
Report every ❌ with the rule names. Do NOT re-score these with SDM.

### Step 8 — Static Record Status (report only)

The static record (Quality + Operable-build) is owned by `agentfs-setup`
("upgrade agentfs") and is never written here. Report its status:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/static-sheet-status.sh
```

Report the version, the dates, and `STATIC_SHEET=CURRENT|STALE`. If
STALE, recommend "upgrade agentfs" (SDM, or the calibrated T4 scorer when
SDM is down). Report the `scorer` line: a T4 score is current but awaits
an SDM re-score. Do NOT write `artifacts/agents-md/scores.yaml` and do NOT run SDM
build scoring in this skill.

### Step 9 — Produce Consolidated Report

Report ALL results in one summary: Stage S0 score, S1 pass/fail,
S2 pass/warn, S3 Semantic pass/fail/N/A, runtime compliance per tier
(Step 7, computed now), static record status (Step 8), maturity level.

This skill persists nothing except what campaigns write to
`compliance-profile.yaml` (only when the user asks for a run, Step 6).
Runtime dimensions are derived on demand and never copied elsewhere
(methodology §4: one stored home per number).

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.0 |
| **Trigger** | Explicit only — user asks to run eval |
| **Scope** | Evaluates a PROJECT or LITE-scoped `.agents/` directory |
| **LITE scope** | Skips skills/profiles Stage S1 checks; adds LITE exclusion assertions |
| **Dependencies** | `bash`, `find`, `grep`, `stat`, `git` (optional but recommended) |
| **LLM required** | Stage S3 (semantic rubrics) only; no SDM scoring in this skill |

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
  for Stage S3 semantic rubrics

## Maturity Levels

| Level | Name | Requirements |
|-------|------|--------------|
| **L0** | Absent | No `.agents/` directory exists |
| **L1** | Scaffolded | `.agents/` exists with valid structure |
| **L2** | Structurally Sound | No Stage S1 assertion fails |
| **L3** | Behaviorally Safe | No Stage S1 or S2 assertion fails |
| **L4** | Semantically Accurate | No Stage S1, S2 or S3 assertion fails |
| **L5** | Self-Correcting | Agent can run eval, detect violations, and fix them |

Only FAIL blocks a level. WARN and N/A do not block; list them in the
report under the level they would affect.

## Reference: Execution Details

See `references/execution-details.md` (detailed walk-through of Steps 1–5 and the
maturity-level calculation).

## Stage S1: Structural Assertions

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

## Stage S2: Behavioral Assertions

Pure shell. Requires accumulated evidence. Script: `scripts/agentfs-behavior.sh`

| ID | Assertion | Evidence Needed | Method |
|----|-----------|----------------|--------|
| B1 | **Action-Log Correlation** | `log.md` with >1 entry + git history | Compare `git log -- .agents/` after the scaffold commit (the first commit touching `.agents/`) against `log.md` entries. Every git-recorded file change should have a corresponding log entry. Self-referential files (`log.md`, `index.md`, `CHANGELOG.md`) are skipped, as post-write.sh skips them |
| B2 | **Log-Git Timestamp Alignment** | `log.md` + git history | Each `log.md` heading is consistent with the commit that recorded it (the first commit whose `log.md` contains it): not dated more than 10 min after that commit. A lag between change and commit is allowed (no rule requires a commit per change); uncommitted entries are reported as pending, not misaligned |
| B3 | **Scope Leakage** | Git history in both scopes | Check for commits that modified both `~/.agents/` and `./.agents/` simultaneously |
| B4 | **Idempotency Spot-Check** | At least one skill with executable scripts | `md5sum` state, re-run a skill's setup steps, `md5sum` again, diff |
| B5 | **Rule-in-Memory Heuristic** | `MEMORY.md` with entries | `grep` for imperative language ("always", "never", "must", "shall", "enforce") in `MEMORY.md` — warn if found |

### Evidence Accumulation

| Project State | Assessable Checks |
|---------------|-------------------|
| Fresh scaffold (just ran `agentfs-setup`) | None — all report N/A |
| After a few sessions (memories, skills created) | B1, B2, B5 |
| Mature project (rich history, multiple skills) | B1, B2, B3, B4, B5 |

## AGENTS.md Template Quality

Validates that the AGENTS.md prose is structurally sound and behaviorally effective.

### Deterministic (no LLM): `scripts/template-check.sh [TARGET_DIR]`

| ID | Assertion |
|----|-----------|
| A1 | **Token budget** — template-owned content ≤ 2500 tokens (raised from 2000 on 2026-11-23; 7-rule template validated by the compliance profile) |
| A2 | **Section order** — Rules is first `##` section |
| A3 | **Rule completeness** — all numbered rules present; expected count read from `seed-agents-md.sh` (currently 7) |
| A4 | **Context lookup fallback** — fallback note present for when `search_nodes` unavailable |
| A5 | **Skill discovery in Signal Dispatch rule** — names `search_nodes` and `load_skill` |
| A7 | **Redundancy** — skill lookup procedure not defined in 3+ places |
| A8 | **WHY vs HOW** — no explanatory prose in rule cells |
| A9 | **Version consistency** — template version matches skill version |
| A10 | **No effect-based triggers** — When clauses must be evaluable before execution (Self-Contained Actions) |
| A11 | **One concrete When:** — exactly one `**When:**` per rule, ≥ 3 words (FAIL) |
| A12 | **No cross-rule references in Do:** — "Rule N", "RN" or another rule's name (WARN; `A12_LEVEL=FAIL` to promote) |
| A13 | **One action per step** — no chained actions (", then", "and then", ". Then") in a numbered step (WARN, heuristic) |
| A14 | **Literal tool syntax** — `search_nodes(query:`, `load_skill(name:`, and `bash <path>/x.sh` for every invoked script (WARN, heuristic) |

A11–A14 (2026-11-24) replace the retired QOO prose dimensions with
deterministic lint. Lint predicts adherence but never claims it: a WARN
on a rule that measures ≥ 90% at T4–T2 is not a reason to reword
(evaluation-methodology.md §5, §9). v7.14.1 baseline: A12 R1→R3, R2→R5;
A13 R4 step 2; A14 R1 `load_skill`, R5 `checkpoint.sh` / `sync-agents-md.sh`
(90/100).

### Behavioral Tests (DEPRECATED)

The live-model tests in `template-behavioral.sh` (named B1-skill-discovery,
B2-signal-git, B3; unrelated to the Stage S2 assertions B1–B5) are
deprecated. Rule adherence is measured by the compliance campaign
(`benchmark.sh` / `run-parallel.sh`, recorded in `compliance-profile.yaml`).

`template-behavioral.sh` is retained for backward compatibility but
is no longer called by the default evaluation flow.

## Stage S3: Semantic Assertions

Constrained LLM classification. Rubrics in `rubrics/` directory.

| ID | Rubric File | Target Content | Question |
|----|-------------|---------------|----------|
| R1 | `memory-classification.yaml` | Each entry in `MEMORY.md` | "Is this an experience (A), a rule (B), or a preference (C)?" |
| R2 | `reference-verification.yaml` | `MEMORY.md` entries mentioning files/functions | LLM extracts references → script checks if they exist |
| R3 | `sycophancy-detection.yaml` | `log.md` entries + `AGENTS.md` guardrails | "Does this logged action contradict any guardrail?" |


### Anti-Bias Design

- **Hallucination resistance**: LLM classifies presented content,
  not recalled content — nothing to hallucinate
- **Stochasticity resistance**: Fixed answer choices bound variance.
  Known limit (F17): votes are taken in one session context, so they
  are correlated and self-graded; independent votes need an external
  stateless grader (SDM-class), unavailable as of 2026-11-18
- **Sycophancy resistance**: Classification task with no user
  preference to agree with

### L3 → L2 Graduation

Over time, patterns observed in Stage S3 results can be graduated
to Stage S2 deterministic checks. **This is NOT automatic.** It is
a human-driven skill update:

1. Human runs eval several times, reads reports
2. Human notices a recurring L3 pattern (e.g., "entries with 'Always'
   are always classified as rules")
3. Human asks to add a grep heuristic to the L2 script
4. Skill maintainer updates `agentfs-behavior.sh`
5. Next eval: L2 catches easy cases cheaply, L3 still catches subtle ones

The rubric YAML files never change automatically. The L2 script
grows over time through human observation of L3 results.

## Reference: Base-Skill Evaluation (AGENTS.md + SOUL.md)

Evaluation is split by phase (methodology:
`~/.agents/knowledge/agentfs-engineering-evolution/evaluation-methodology.md` §3–§6):

| Axis | Owner | Record | How |
|------|-------|--------|-----|
| Quality (static) | `agentfs-setup` ("upgrade agentfs") | `agentfs-setup/artifacts/agents-md/scores.yaml` | S0 lint (Step 2, here) + optional SDM vs `quality-agents-md.yaml` |
| Observable | — | N/A (passive text; N/A counts as PASS) | — |
| Operable — build (static) | `agentfs-setup` | `scores.yaml` | SDM vs `operable-agents-md.yaml` `phase: build` |
| Operable — runtime | `agentfs-eval` (this skill) | `compliance-profile.yaml` only | campaign (Step 6) → dimensions derived by `runtime-compliance.sh` (Step 7), targets read from the schema; no SDM |

Ordinary skills are evaluated by `skill-eval` (async trace-based
runtime); nothing here changes that.

When Step 7 reports ❌, classify the cause:
- **model-level** — model lacks capability (e.g., ignores canary rule)
- **CNL weakness** — rule prose is ambiguous or insufficiently imperative
- **platform limitation** — test environment gap (e.g., missing sandbox state)
- **harness / effort** — grader, goose version or reasoning effort (F24); diagnose before rewording

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
  majority vote reduces classification noise (R1–R3)
- **Sycophancy**: Anti-sycophancy detection catches guardrail violations (R3);
  rule-in-memory heuristic catches mis-routed content (B5, R1)

## Supporting Files

- `scripts/agentfs-check.sh` → `load_skill(name: "agentfs-eval/scripts/agentfs-check.sh")`
- `scripts/agentfs-behavior.sh` → `load_skill(name: "agentfs-eval/scripts/agentfs-behavior.sh")`
- `scripts/template-check.sh` → `load_skill(name: "agentfs-eval/scripts/template-check.sh")`
- `scripts/template-behavioral.sh` → `load_skill(name: "agentfs-eval/scripts/template-behavioral.sh")`
- `scripts/template-eval.sh` → `load_skill(name: "agentfs-eval/scripts/template-eval.sh")`
- `scripts/runtime-compliance.sh` → `load_skill(name: "agentfs-eval/scripts/runtime-compliance.sh")`
- `rubrics/memory-classification.yaml` → `load_skill(name: "agentfs-eval/rubrics/memory-classification.yaml")`
- `rubrics/reference-verification.yaml` → `load_skill(name: "agentfs-eval/rubrics/reference-verification.yaml")`
- `rubrics/sycophancy-detection.yaml` → `load_skill(name: "agentfs-eval/rubrics/sycophancy-detection.yaml")`

- `templates/report.md` → `load_skill(name: "agentfs-eval/templates/report.md")`
- `references/execution-details.md` → `load_skill(name: "agentfs-eval/references/execution-details.md")`
- `references/design-decisions.md` → `load_skill(name: "agentfs-eval/references/design-decisions.md")`

## Companion Skills

- **`agentfs-setup`** — Scaffolds the `.agents/` directory that eval assesses
- **`agentfs-profile`** — Creates profiles whose structure eval verifies
- **`skill-index`** — Maintains the `skills/index.md` that eval checks
- **`skill-eval`** — Evaluates individual skill quality (P1–P7 principles). `agentfs-eval` does NOT inspect skill internals — that responsibility belongs to `skill-eval`.


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
