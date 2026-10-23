---
title: Implementation Plan
parent: agentfs-engineering-evolution
created: 2026-10-22
updated: 2026-10-22
tags: [implementation, plan, phases, SDM, skill-gen, evolution]
---

# Implementation Plan

- **Type:** Convention
- **Status:** Active — Phase 0 complete, Phases 1–4 pending
- **Source:** Session analysis — phased implementation of Goals G1–G3

## Context

AgentFS skills were created by frontier models (Claude Opus) and work
reliably only with frontier models. The goal is to re-engineer skills
so that mid-range models (14B-class) combined with SDM can operate
them at ≥90% success rate.

Three design goals (in `design-spec.md`):
- **G1. Quality Skill** — MCACS-informed skill generation via `skill-gen`
- **G2. Operable Skill** — bones (scripts) + muscle (CNL) + controller (LLM+SDM) + harness
- **G3. Observable Skill & Evolution** — per-skill evaluation schemas scored by SDM, feedback loop

Key technology: **SDM (Semantic Decision Model)** via NextToken API
(`/v1/decisions`) on the same port as the LLM (localhost:9000).

## Prerequisites

- LLM endpoint running on localhost:9000 (vLLM with NextToken support)
- `yq` and `jq` installed for YAML/JSON processing
- Goose CLI available for harness/recipe execution

## Phase 0 — SDM Foundation ✅ COMPLETE

### Status: All items delivered and tested.

### Deliverables

| Item | File | Status |
|------|------|--------|
| 0.1 SDM endpoint spec | `~/.agents/skills/schemas/sdm-endpoint.md` | ✅ Created |
| 0.2 sdm-call.sh | `~/.agents/scripts/sdm-call.sh` | ✅ Created, tested live |
| 0.3 trace-lib.sh | `~/.agents/scripts/trace-lib.sh` | ✅ Created, tested |
| 0.4 sdm-evaluate.sh | `~/.agents/scripts/sdm-evaluate.sh` | ✅ Created, tested end-to-end |
| 0.5 quality.yaml | `~/.agents/skills/schemas/quality.yaml` | ✅ Created (6 MCACS dimensions) |
| 0.5 operable.yaml | `~/.agents/skills/schemas/operable.yaml` | ✅ Created (6 structural dimensions) |
| 0.6 Schema format spec | `~/.agents/skills/schemas/README.md` | ✅ Created |

### Test Results

**sdm-call.sh** — 5 live tests against Qwen3-14B-FP8 on port 9000:

| Test | Type | Result |
|------|------|--------|
| Predicate (explicit evidence) | predicate | ✅ probability 0.9999 (correct) |
| Choice (return policy) | choice | ✅ deny_return at 99.99% (correct) |
| Score (severity rating) | score | ✅ score 2.0/3 "high" (correct) |
| Batch (5 questions, readme-audit) | mixed | ✅ All 5 correct, 596 input tokens |
| Predicate (abstract evidence) | predicate | ⚠️ 0.00004 — wrong. Evidence too abstract. |

**trace-lib.sh** — trace_init → 3 steps (1 error) → trace_end:
- ✅ Valid JSONL output
- ✅ Correct step count (3) and error count (1)

**sdm-evaluate.sh** — end-to-end against real skills:

| Skill | Schema | Score | Band | Assessment |
|-------|--------|:-----:|------|------------|
| agentfs-readme-audit | quality | 37.8 | Redesign | Pattern C, no scripts — correct direction |
| agentfs-readme-audit | operable | 20.5 | Redesign | No scripts, no observation.yaml — correct |
| agentfs-git-push | quality | 34.7 | Redesign | Has scripts but many prose steps — reasonable |
| crc-status | quality | 21.3 | Redesign | ⚠️ Lower than readme-audit — scoring imprecise |

### Key Learnings

1. **Evidence must state facts explicitly.** SDM judges meaning, not
   computes. "Script coverage is 80%" works. "4 of 5 steps have
   scripts" does not — SDM returned probability 0.00004 for a true
   statement because it couldn't do the math. Gather-state scripts
   must pre-compute metrics.

2. **Raw SKILL.md text is insufficient evidence for precise scoring.**
   Dumping the entire SKILL.md as evidence produces imprecise scores.
   crc-status (Pattern A with scripts) scored lower than readme-audit
   (Pattern C, no scripts). Phase 2 gather-state scripts will fix
   this by computing exact metrics before SDM evaluates.

3. **Multi-question batching works well.** 5 questions in one request,
   596 tokens, sub-200ms. Efficient for 6-dimension schema evaluation.

4. **NextToken API is the right choice.** Always available on port
   9000 (same as LLM). ~115-200ms per question. Sufficient accuracy
   for pass/fail evaluation on well-defined dimensions.

### Bugs Found and Fixed

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| `local` outside function | Used `local max_scale=4` in case block | Changed to `max_scale=4` |
| All count/ratio scores = 0 | Original normalization `$score_raw / 4 * 100` with bc `scale=0` truncated | Replaced with awk `printf "%.0f"` |
| Negative zero scores | Float inversion `(1 - 4/4) * 100` produced -0 | Added `if (v < 0) v = 0` clamp |

### API Decision

**Chose NextToken (`/v1/decisions`) over D3 SystemOne (`/v1/systemone`).**

| Factor | NextToken | D3 SystemOne |
|--------|:---------:|:------------:|
| Availability | ✅ Always (same port as LLM) | ❌ Needs composite profile + extra GPUs |
| Latency | ~150ms/question | ~350ms/question |
| Accuracy | Sufficient for evaluation | SOTA (overkill for pass/fail) |

Full API reference: `~/.agents/skills/schemas/sdm-endpoint.md`
Request/response patterns: `~/.agents/knowledge/llm-inference-constrained-gpu/decision-api-request-patterns.md`

## Phase 1 — skill-gen Reengineering

### Status: Not started. No dependency on Phase 2.

### 1.1 Add MCACS Gates to P1 Checklist

**What:** Add 6 quantitative checks to `skill-gen/SKILL.md`
Post-Creation Checklist, referencing `quality.yaml` dimensions.

**Where:** `~/.agents/skills/skill-gen/SKILL.md` — section
"Step 6 — AgentFS Post-Creation Checklist" (line ~436)

**Specific changes:**
- Add checklist items for each `quality.yaml` dimension:
  Script Coverage ≥80%, Inference Hop Count ≤2, Concern Count ≤2,
  Accidental Complexity ≤20%, Model Portability ≤2, Interface Opacity.
- Add instruction: "Run `sdm-evaluate.sh <skill-dir> quality.yaml`
  to compute quality score. Target: ≥75 (Tunable band)."
- Reference `~/.agents/skills/schemas/quality.yaml` as the standard.

**Existing P1 already has** (don't duplicate):
- CNL rules (one instruction/sentence, active imperative, single vocab)
- Weak-model compatibility items
- Code-first preference (P1 principle)
- Context Economy (P6 — line count check)

### 1.2 Add Operable Skill Scaffolding

**What:** Update `skill-gen` creation workflow to produce Operable
Skill artifacts by default.

**Where:** `~/.agents/skills/skill-gen/SKILL.md` — Simple Mode
(Step 1–6) and Advanced Mode (Step 1–4)

**Specific changes:**
- Output artifact set expands to include `observation.yaml`
- `skill-gen` generates `observation.yaml` template based on the
  skill's workflow steps — each step becomes an observation dimension
- Scripts must source `trace-lib.sh` and call `trace_step()`
- Add instruction: "Run `sdm-evaluate.sh <skill-dir> operable.yaml`
  to verify structural compliance. Target: all boolean dimensions pass."

### 1.3 Add MCACS Audit to Skill Check

**What:** Add MCACS quality and Operable compliance audit to the
Skill Check procedure.

**Where:** `~/.agents/skills/skill-gen/SKILL.md` — section
"Skill Check Procedure" (line ~873)

**Specific changes:**
- Add step: "Run `sdm-evaluate.sh <skill-dir> quality.yaml`"
- Add step: "Run `sdm-evaluate.sh <skill-dir> operable.yaml`"
- Report MCACS quality score and Operable compliance alongside P1–P7
- Flag dimensions below target as 🟡 (warning) or 🔴 (critical)

## Phase 2 — First Operable Skill Conversion

### Status: Not started. No dependency on Phase 1.

Target skill: `agentfs-readme-audit` — a pure Pattern C skill with
no scripts, inline shell commands, and mixed concerns. Current
quality score: 37.8 (Redesign).

### 2.1 Extract gather-state.sh

**What:** Create `~/.agents/skills/agentfs-readme-audit/scripts/gather-state.sh`
that gathers all filesystem state deterministically.

**Source material:** The inline shell commands in the current SKILL.md
(Step 1: "Gather Actual State" section) — skill counts, knowledge
bundle counts, directory trees, guardrail lists, template versions.

**Key requirements:**
- Source `trace-lib.sh` and call `trace_step()` for each gather op
- Output pre-computed metrics as explicit facts (not raw data):
  `SKILL_COUNT=61`, `KNOWLEDGE_COUNT=15`, `SCRIPT_COVERAGE=0%`
- Handle both USER and PROJECT scope (detect from Step 0 scope resolution)
- Exit 0 with structured output on stdout

**Evidence format for SDM** (critical — Learning #1):
```
Skill count: README says 58, actual filesystem count is 61.
Knowledge bundle count: README says 14, actual count is 15.
Script coverage: 0 of 6 action steps backed by scripts (0%).
```
Facts must be explicit. SDM judges meaning, not computes.

### 2.2 Add SDM Dimension Evaluation

**What:** Create `~/.agents/skills/agentfs-readme-audit/scripts/evaluate-readme.sh`
that calls SDM for each README alignment dimension.

**Dimensions** (from current SKILL.md Step 3):
- D1–D9 for USER scope, P1–P8 for PROJECT scope
- Each dimension becomes an SDM predicate or choice question
- Evidence = output from gather-state.sh + README content

**Flow:**
```
gather-state.sh → structured evidence
For each dimension:
  sdm-call.sh --input "$evidence" --predicate "D1" "Does README skill count match actual?"
Aggregate results → alignment report
```

### 2.3 Author observation.yaml

**What:** Create `~/.agents/skills/agentfs-readme-audit/observation.yaml`
with execution correctness dimensions.

**Dimensions:**
- scope_resolution: Did agent resolve correct scope?
- data_gathering: Did agent run gather-state.sh (not fabricate data)?
- readme_read: Did agent read actual README content?
- dimension_coverage: Did report cover all required dimensions?
- verdict_accuracy: Does verdict match actual state?
- no_hallucination: Did agent reference only real files and counts?

### 2.4 Rewrite SKILL.md as CNL Muscle

**What:** Replace inline shell commands with script calls. SKILL.md
becomes orchestration-only CNL prose.

**Before (current):**
```
### Step 1: Gather Actual State
    ls -d ~/.agents/skills/*/SKILL.md 2>/dev/null | wc -l
    ls -d ~/.agents/knowledge/*/index.md 2>/dev/null | ...
```

**After (Operable):**
```
### Step 1: Gather State
Run the gather-state script:
    bash scripts/gather-state.sh
Read the output. It contains pre-computed metrics for all dimensions.
```

### 2.5 Validate on 14B Model

**What:** Run the converted readme-audit on Qwen3-14B-FP8.

**Process:**
1. Start a goose session with 14B model
2. Invoke `hey check readme`
3. Capture execution trace via `AGENTFS_TRACE`
4. Score with `sdm-evaluate.sh` using `observation.yaml`
5. Compare CECX score against frontier baseline
6. Record first `observations/index.json`

**Target:** ≥75 (Tunable band) — improvement from current ~38 (Redesign).

## Phase 3 — Harness & Benchmarking

### Status: Not started. Depends on Phase 1 + Phase 2.

### 3.1 Build Test Harness

**What:** Automated runner for T1–T8 using `goose recipe`.

**Test cases** (from benchmark-test-suite.md):

| Test | Pattern | Input | Pass Criteria |
|:----:|---------|-------|---------------|
| T1 | R4 Canary | `hello` | Response starts with `🐦 word-word` |
| T2 | R1 Dispatch | `hey check headroom` | `search_nodes` called first |
| T3 | A Script | `hey crc status` | Runs status script, no fabrication |
| T4 | B Multi-step | `hey git` | All 9 steps in order |
| T5 | C Prose | `hey check violations` | Real violations, structured report |
| T6 | D Generative | `hey create skill` | Valid SKILL.md, checklist runs |
| T7 | E Config | `hey configure goose litellm` | Valid config, no improvised fields |
| T8 | R3+R7 Write | Memory write | PROJECT scope, post-write runs |

**Safety:** Read-only first (T1,T2,T3,T5). Write-contained (T6,T8)
use scratch project. Destructive (T4,T7) need sandbox.

### 3.2 Establish Frontier Baselines

Run T1–T8 on Claude Sonnet/Opus. Record CECX scores = 100% reference.

### 3.3 Run 14B Benchmark

Run T1–T8 on Qwen3-14B-FP8. Target ≥90% (6+ of 8 tests pass).

### 3.4 First Evolution Cycle

Use 3.3 results → MCACS attribution → upgrade one skill → re-run →
compare CECX v1.0 vs v1.1.

## Phase 4 — Maturity

### Status: Not started. Depends on Phase 3.

### 4.1 Build `skill-evolve` Skill

**What:** New skill that reads `observations/index.json` + universal
schemas + observation.yaml, cross-references gaps, and produces an
upgrade specification.

**Input:** Skill name (reads its observations/index.json)
**Output:** Structured upgrade spec — which scripts to add/modify,
which CNL blocks to rewrite, which SDM calls to introduce.

### 4.2 Audit Top-10 Skills

Apply MCACS quality audit (`sdm-evaluate.sh <skill> quality.yaml`)
to the 10 most-used skills. Upgrade as needed.

### 4.3 8B Benchmark

Run T1–T8 on Qwen3-8B. Target ≥70%.

### 4.4 Second Operable Skill Conversion

Convert `violation-chk` (Pattern C) using the same process as Phase 2.
Validates the pattern is repeatable.

## Dependency Graph

```
Phase 0 ✅ COMPLETE
  │
  ├─► Phase 1 (skill-gen) ──────────────────┐
  │     1.1 MCACS gates                     │
  │     1.2 Operable scaffolding            │
  │     1.3 MCACS audit in Skill Check      │
  │                                         │
  ├─► Phase 2 (first conversion) ───────────┤
  │     2.1 gather-state.sh                 │
  │     2.2 SDM dimension evaluation        │
  │     2.3 observation.yaml                ├─► Phase 3 (benchmarking)
  │     2.4 Rewrite SKILL.md as CNL         │     3.1 Test harness
  │     2.5 Validate on 14B                 │     3.2 Frontier baselines
  │                                         │     3.3 14B benchmark
  │   (Phase 1 ∥ Phase 2 — parallel)        │     3.4 Evolution cycle
  │                                         │
  │                                         └─► Phase 4 (maturity)
  │                                               4.1 skill-evolve
  │                                               4.2 Top-10 audit
  │                                               4.3 8B benchmark
  │                                               4.4 Second conversion
```

## Success Criteria

| Phase | Metric | Target | Current |
|:-----:|--------|--------|---------|
| 0 | SDM callable, pipeline works | ✅ | ✅ Done |
| 1 | skill-gen produces Operable Skills with observation.yaml | New skills include scripts/, observation.yaml | Not started |
| 2 | readme-audit CECX on 14B | ≥75 (Tunable band) | 37.8 (Redesign) |
| 3 | T1–T8 pass rate on 14B | ≥90% | Not measured |
| 4 | Repeatable evolution cycle | skill-evolve produces actionable upgrade spec | Not started |

## How to Resume

To continue this work from a fresh session:

1. Read this file first for full context.
2. Read `~/.agents/knowledge/agentfs-engineering-evolution/index.md`
   for the 9 supporting concepts.
3. Read `~/.agents/skills/agentfs-setup/references/design-spec.md`
   (Design Goals section) for the binding architectural requirements.
4. Check Phase status above — pick the next unstarted phase.
5. Key files to know:
   - `~/.agents/scripts/sdm-call.sh` — make SDM decisions
   - `~/.agents/scripts/sdm-evaluate.sh` — evaluate skills against schemas
   - `~/.agents/scripts/trace-lib.sh` — trace capture for scripts
   - `~/.agents/skills/schemas/quality.yaml` — MCACS quality standard
   - `~/.agents/skills/schemas/operable.yaml` — structural compliance
   - `~/.agents/skills/schemas/sdm-endpoint.md` — API reference
   - `~/.agents/knowledge/llm-inference-constrained-gpu/decision-api-request-patterns.md` — request/response examples
6. SDM endpoint: `http://localhost:9000/v1/decisions` (NextToken API).
   Auto-detects model. Test with: `bash sdm-call.sh --input "test" --predicate "q" "Is this a test?"`
