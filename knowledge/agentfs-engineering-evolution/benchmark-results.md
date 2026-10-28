# Stochastic Benchmark Results — 2026-10-27

## Test Configuration

| Parameter | Value |
|-----------|-------|
| Tests | T1 (canary), T2 (dispatch), T3 (single script), T5 (prose analysis) |
| Runs per test | 3 per round, 2 rounds = 6 total per test |
| CWD (T1-T3) | Project repo with AGENTS.md (context-eng) |
| CWD (T5) | ~/.agents |
| Safety level | Read-only suite only |

## Results: Frontier (Sonnet 4.6 via RedHat LiteLLM — port 4000)

| Test | Run 1 | Run 2 | Run 3 | Rate |
|------|:-----:|:-----:|:-----:|:----:|
| T1 canary | ✅ | ✅ | ✅ | 3/3 |
| T2 dispatch | ✅ | ✅ | ✅ | 3/3 |
| T3 script | ✅ | ✅ | ✅ | 3/3 |
| T5 prose | ✅ | ✅ | ✅ | 3/3 |
| **Total** | | | | **12/12 = 100%** |

## Results: 14B (Qwen3-14B-FP8 via Skupper) — Two Rounds

### Round 1

| Test | Run 1 | Run 2 | Run 3 | Rate |
|------|:-----:|:-----:|:-----:|:----:|
| T1 canary | ❌ | ✅ | ✅ | 2/3 |
| T2 dispatch | ✅ | ✅ | ✅ | 3/3 |
| T3 script | ✅ | ✅ | ✅ | 3/3 |
| T5 prose | ✅ | ✅ | ✅ | 3/3 |
| **Total** | | | | **11/12 = 91%** |

### Round 2

| Test | Run 1 | Run 2 | Run 3 | Rate |
|------|:-----:|:-----:|:-----:|:----:|
| T1 canary | ✅ | ❌ | ❌ | 1/3 |
| T2 dispatch | ✅ | ✅ | ✅ | 3/3 |
| T3 script | ✅ | ❌ | ❌ | 1/3 |
| T5 prose | ✅ | ✅ | ✅ | 3/3 |
| **Total** | | | | **8/12 = 66%** |

### Combined (6 runs per test)

| Test | Pass | Fail | Rate | Failure Mode |
|------|:----:|:----:|:----:|-------------|
| T1 canary | 3 | 3 | **50%** | AGENTS.md rules not loaded — generic greeting |
| T2 dispatch | 6 | 0 | **100%** | — |
| T3 script | 4 | 2 | **67%** | search_nodes works, but model runs `crc status` directly instead of `load_skill` |
| T5 prose | 6 | 0 | **100%** | — |
| **Total** | **19** | **5** | **79%** | — |

## Analysis

### 79% combined rate — below 90% target

The single-round 91% was optimistic. With 6 runs the true stochastic
rate is closer to **79%**, driven by two distinct failure modes:

### Failure Mode 1: Context Loading (T1 — 50%)

The 14B model sometimes doesn't process AGENTS.md system prompt rules.
When this happens, it responds with a generic greeting — no canary,
no identity, no rules applied. This is upstream of skill architecture.

- **MCACS classification:** Not attributable. Model-level context
  processing variance.
- **Potential mitigation:** Shorter/simpler AGENTS.md, or prompt
  engineering to front-load the canary rule.

### Failure Mode 2: Skill Bypass (T3 — 67%)

The model correctly calls `search_nodes` (dispatch works) but then
bypasses `load_skill` and runs the command directly. In T3 runs 2-3
of round 2, it called `crc status` immediately after search_nodes
returned the crc-status skill — producing a correct result but
skipping the skill entirely.

- **MCACS classification:** Coupling (model_portability). The model
  has built-in knowledge of `crc status` and takes the shortest path.
  The dispatch rule says "load the skill" but the model's instinct
  to act directly overrides the rule.
- **Potential mitigation:** Stronger CNL in AGENTS.md dispatch rule:
  "You MUST call load_skill. Do NOT run commands directly." Or:
  make load_skill the only way to know what to do (remove obvious
  command names from skill descriptions in KGM index).

### Reliable Patterns

| Pattern | Test | 6-run Rate | Why Reliable |
|---------|------|:----------:|-------------|
| Signal dispatch | T2 | 100% | `hey` keyword triggers search_nodes deterministically |
| Prose analysis | T5 | 100% | Skill produces structured output, model follows format |

### Unreliable Patterns

| Pattern | Test | 6-run Rate | Why Unreliable |
|---------|------|:----------:|---------------|
| Rule compliance | T1 | 50% | Dense system prompt, model skips rules stochastically |
| Scripted skill | T3 | 67% | Model has domain knowledge, bypasses skill loading |

### Implications for Architecture

1. **Single-round benchmarks are insufficient.** 91% in round 1,
   66% in round 2 — variance is high. Need ≥6 runs minimum.
2. **T2 and T5 are the reliable foundation.** Signal dispatch and
   structured prose analysis work deterministically on 14B.
3. **T1 canary is a system prompt problem, not a skill problem.**
   Fixing this requires AGENTS.md optimization, not skill redesign.
4. **T3 skill bypass is a real skill architecture issue.** The model
   needs stronger guardrails to use `load_skill` instead of acting
   on its own knowledge. This is where Phase 3.4 evolution applies.

## Raw Outputs

- Round 1: `/tmp/benchmark-14b-multi/`
- Round 2: `/tmp/benchmark-14b-multi-v2/`
- Frontier: `/tmp/benchmark-redhat-multi/`

---

## v2 Harness Results (2026-10-27)

**Changes from v1:** T2 prompt fixed (`hey headroom status`), T9 added
(`hey check readme`), all dispatch checkers require full chain
(search → load → execute), KGM preflight gate added.

### Frontier Validation: 5/5 = 100%

Provider: custom_redhat / claude-sonnet-4-6. Single run.

### 14B Measurement: 5 runs × 5 tests

Provider: custom_skupper / Qwen3-14B-FP8.

| Test | R1 | R2 | R3 | R4 | R5 | Rate |
|------|:--:|:--:|:--:|:--:|:--:|:----:|
| T1 canary | ✅ | ✅ | ❌ | ❌ | ✅ | 60% |
| T2 headroom status | ✅ | ✅ | ✅ | ✅ | ✅ | **100%** |
| T3 crc status | ❌ | ✅ | ❌ | ❌ | ✅ | 40% |
| T5 check violations | ✅ | ✅ | ✅ | ✅ | ❌ | 80% |
| T9 check readme | ✅ | ✅ | ❌ | ✅ | ✅ | 80% |

### Scores

- **Skill operability** (T2+T3+T5+T9): **15/20 = 75%** (target: ≥90%)
- **System prompt compliance** (T1): 3/5 = 60% (reported separately)
- **Overall:** 18/25 = 72%

### v2 vs v1 Comparison (T2 specifically)

| Harness | T2 Prompt | T2 KGM Query | T2 Pass Rate |
|---------|-----------|:------------:|:------------:|
| v1 | `hey check headroom status` | `check headroom status` (❌ KGM miss) | variable |
| v2 | `hey headroom status` | `headroom status` (✅ KGM hit) | **100%** |

Fixing the test prompt from a non-registered signal to a registered
signal eliminated all T2 failures. The v1 T2 failures were test
infrastructure bugs, not model operability issues.

### Failure Mode Taxonomy (v2)

| # | Pattern | Count | Tests | Root Cause |
|:-:|---------|:-----:|-------|-----------|
| FM1 | Model rephrases signal → KGM miss | 2 | T3R3, T3R4 | Model sends `check crc status` instead of `crc status` |
| FM2 | Fabrication after skill load | 1 | T3R1 | Model generates plausible output without running script |
| FM3 | Explanation instead of execution | 1 | T9R3 | Model describes steps, asks "would you like me to..." |
| FM4 | Shell command instead of skill flow | 1 | T5R5 | Model treats skill name as CLI command |
| FM5 | System prompt not processed | 2 | T1R3, T1R4 | Dense AGENTS.md not applied on turn 1 |

### MCACS Attribution

| FM | MCACS Principle | Mitigation Direction |
|:--:|----------------|---------------------|
| FM1 | Abstraction | Strengthen dispatch rule CNL: "Use keywords literally" |
| FM2 | Separation of Concerns | Stronger CNL in skill: "Run the script. Do not generate output." |
| FM3 | Cohesion | Stronger imperative in skill: "Execute immediately. Do not explain." |
| FM4 | Abstraction | Model education — skill names are not shell commands |
| FM5 | (Not attributable) | Model-level system prompt processing |

---

## T3 Before/After — crc-status QOO Conversion (2026-10-27)

### Before (v1.1.0 — unevolved)
- 0 scripts, 111 lines, prose narrative, no anti-fabrication rule
- **T3 rate: 2/5 = 40%**
- Failure modes: fabrication (1), signal rephrasing (2)

### After (v2.0.0 — QOO converted)
- 1 script (check-status.sh), 78 lines, CNL muscle, anti-fabrication rule
- **T3 rate: 4/5 = 80%**
- Remaining failure: FM1 signal rephrasing (1) — model sent `check crc status`

### Improvement: 40% → 80% (+40 percentage points)

The QOO conversion eliminated fabrication entirely (FM2 gone) and
reduced the failure surface to a single upstream issue (FM1 — model
rephrases signal before KGM search). FM1 is not a skill issue — it's
a dispatch rule compliance issue in the AGENTS.md system prompt.

### Updated Skill Operability (all QOO-qualified tests)

| Test | Before QOO | After QOO | Rate |
|------|:----------:|:---------:|:----:|
| T2 headroom status | (already 100%) | — | **100%** |
| T3 crc status | 40% | 80% | **80%** |
| T5 check violations | — | 80% | **80%** |
| T9 check readme | — | 80% | **80%** |
| **Skill operability** | 75% (15/20) | **85% (17/20)** | +10pp |

Note: T5 (violation-chk) has not been QOO-converted yet. Its 80% rate
is from v1 skill structure. After conversion, expected to improve.

---

## v3 — AGENTS.md R1 Dispatch Rule Evolution (2026-10-27)

### Changes Applied (EP1+EP2+EP3+EP6)

| EP | Change | Before | After |
|:--:|--------|--------|-------|
| EP1 | Separate keyword extraction from search | Mixed in steps 1-2 | Step 1 = extract, Step 2 = search |
| EP2 | Replace misleading example | `hey check headroom status` | `hey crc status` → `crc status` |
| EP3 | Add KGM search behavior note | Not stated | "KGM search matches exact words, not fuzzy" |
| EP6 | Add anti-bypass instruction | Not stated | "MUST call load_skill. Do NOT skip it." |

### Frontier Validation: 5/5 = 100% ✅

### 14B Results: 5 runs × 5 tests

| Test | R1 | R2 | R3 | R4 | R5 | Rate |
|------|:--:|:--:|:--:|:--:|:--:|:----:|
| T1 canary | ✅ | ❌ | ❌ | ✅ | ✅ | 60% |
| T2 headroom status | ✅ | ✅ | ✅ | ✅ | ✅ | **100%** |
| T3 crc status | ✅ | ✅ | ✅ | ✅ | ✅ | **100%** |
| T5 check violations | ✅ | ✅ | ✅ | ✅ | ✅ | **100%** |
| T9 check readme | ✅ | ✅ | ✅ | ✅ | ✅ | **100%** |

### Scores

- **Skill operability: 20/20 = 100%** ✅ (target: ≥90%)
- **System prompt compliance: 3/5 = 60%** (T1 canary, reported separately)
- **Overall: 23/25 = 92%** ✅ (exceeds 90% target)

### Evolution Journey (T3 crc-status)

| Version | What Changed | T3 Rate |
|---------|-------------|:-------:|
| v1 harness + v1.1.0 skill | Broken test prompt + unevolved skill | 40% |
| v2 harness + v1.1.0 skill | Fixed test prompt, still unevolved skill | 40% |
| v2 harness + v2.0.0 skill | QOO-converted skill (scripts, CNL, anti-fabrication) | 80% |
| v2 harness + v2.0.0 skill + R1 CNL fix | AGENTS.md dispatch rule evolved | **100%** |

### Evolution Journey (Skill Operability Overall)

| Stage | Score | Delta |
|-------|:-----:|:-----:|
| v1 harness (broken test infra) | 79% (19/24) | — |
| v2 harness (fixed prompts, tighter checkers) | 75% (15/20) | baseline |
| + crc-status QOO conversion | 85% (17/20) | +10pp |
| + AGENTS.md R1 dispatch CNL fix | **100% (20/20)** | **+25pp** |

### Key Finding

Three independent improvements each contributed to the result:
1. **Test infrastructure** — fix prompts to use KGM-registered signals
2. **Skill quality** — QOO conversion with scripts and anti-fabrication
3. **System prompt quality** — CNL optimization of dispatch rule

All three are necessary. No single fix alone would reach 100%.

---

## v4 — AGENTS.md EP4+EP5+EP7 (2026-10-27)

### Changes
- EP4: R2 Pre-Flight compressed (211→141 words, Tier 2 from 20→5 lines)
- EP5: R4 Canary reordered (write canary is step 1, read USER.md is step 2)
- EP7: post-write-enforce plugin created (AfterFileEdit + PreToolUse hooks)

### Frontier: 5/5 = 100% ✅

### 14B: 5 runs × 5 tests

| Test | R1 | R2 | R3 | R4 | R5 | Rate |
|------|:--:|:--:|:--:|:--:|:--:|:----:|
| T1 canary | ✅ | ✅ | ❌ | ❌ | ❌ | 40% |
| T2 headroom | ❌ | ❌ | ✅ | ❌ | ✅ | 40% |
| T3 crc status | ✅ | ✅ | ✅ | ❌ | ✅ | 80% |
| T5 violations | ✅ | ✅ | ✅ | ✅ | ✅ | 100% |
| T9 readme | ✅ | ✅ | ✅ | ✅ | ✅ | 100% |

- **Skill operability: 16/20 = 80%**
- **T1 canary: 2/5 = 40%** (EP5 did not improve — model-level)
- **Overall: 18/25 = 72%**

### Analysis

T2 dropped from 100% (v3) to 40%. Root cause: headroom-proxy-status
is an unevolved v1 skill. Model loaded it correctly (search→load) but
fabricated output instead of running shell commands. Same FM2 pattern
that crc-status had before QOO conversion.

T3 had 1 fabrication (run 4) despite QOO conversion — the anti-
fabrication rule reduces but doesn't eliminate FM2 on a 14B model.

T5 and T9 remain 100% — consistent across all benchmark rounds.

EP4/EP5 changes to AGENTS.md did NOT cause the regression. The v3
100% skill operability was stochastic luck. True rate with current
skill mix is 80-100% depending on the run — T2's unevolved skill
is the primary source of variance.

### Key Principle Reconfirmed

Test targets must be QOO-qualified. T2 (headroom-proxy-status) is
still a v1 skill. Its failures measure skill maturity, not the
AGENTS.md improvements.

---

## v6 — Full AGENTS.md Rule Coverage (2026-10-27)

### Test Suite (auto-discovered + rule tests)

| Test | Rule | Type | Safety |
|------|:----:|------|:------:|
| t1 | R4 | Session canary | read-only |
| qoo_crc_status | R1 | Dispatch → QOO skill | read-only |
| qoo_agentfs_readme_audit | R1 | Dispatch → QOO skill | read-only |
| t_r2 | R2 | Pre-flight plan | write-contained |
| t_r3 | R3 | Post-write after .agents/ write | write-contained |
| t_r7 | R7 | Memory scope compliance | write-contained |

### Results

| Rule | Test | Frontier | 14B (5 runs) |
|:----:|:----:|:--------:|:------------:|
| R1 | QOO skills | 100% | **100%** (10/10) |
| R2 | t_r2 | 100% | **100%** (5/5) |
| R3 | t_r3 | **0%** | **0%** (0/5) |
| R4 | t1 | 100% | **60%** (3/5) |
| R5 | — | not testable | not testable |
| R6 | — | not testable | not testable |
| R7 | t_r7 | 100% | **40%** (2/5) |

### Findings

**R3 (Post-Write) — 0% on both models.** The `hey remember` prompt
triggers Signal Dispatch → memory write → response. The model writes
to `.agents/memories/MEMORY.md` then responds without running
`post-write.sh`. The EP7 harness hook (`PreToolUse` block) cannot
prevent this because there is no subsequent tool call after the write —
the model's response is the final action. This is a platform limitation:
goose has no `PreResponse` hook to block the response itself.

**R7 (Scope Rules) — 40% on 14B.** The 14B model inconsistently
writes memories to the sandbox project scope. In 3/5 runs, no memory
write was detected in the output at all — the model may have responded
without writing, or written to the wrong path.

**R5, R6 — Not testable.** R5 (Conflict Resolution) requires multi-turn
adversarial prompting. R6 (Checkpoint) requires destructive operations
on real `.agents/` state. Both need test infrastructure beyond
`goose run --text` single-turn.
