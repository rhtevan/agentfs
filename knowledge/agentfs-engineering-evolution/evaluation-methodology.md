---
type: Convention
title: AgentFS Evaluation Methodology
parent: agentfs-engineering-evolution
created: 2026-11-24
updated: 2026-11-24
tags: [evaluation, compliance, QOO, base-skill, methodology, canonical]
---

# AgentFS Evaluation Methodology

- **Type:** Convention (canonical — supersedes the strategy parts of older docs, see §12)
- **Status:** Active. §3–§5 implemented for agentfs-eval/agentfs-setup (R-a, 2026-11-24). Rules phase (R-a–R-g) complete 2026-11-24. Next: §13 row 5 (Principles).
- **Decision trail:** F-tracker in [dry-run-and-compliance-plan.md](./dry-run-and-compliance-plan.md) (F3, F21–F27)

## 1. Goal

AgentFS prose is reliably followed by models from frontier to
self-hostable:

- **Rules (AGENTS.md):** ≥ 90% per rule at T4, T3 and T2.
- **Principles (SOUL.md):** aim T2, minimum T3. Beyond adherence, the
  rewrite targets are: remove overlap, redundancy and ambiguity
  (controlled natural language where it helps), and suppress
  over-engineering, over-reacting, jumping to action too early and
  losing focus.

The tier ladder is T4 frontier → T3 large open-weight → T2 self-hostable
(fits 2× L4) → T1 small, reference only. Every evaluation exists to
answer one of two questions:

| Question | Phase | Answered by |
|----------|-------|-------------|
| Is the artifact **well built** and maintainable? | static (build time) | Quality + Operable-build (+ Observable) |
| Is it **followed / executed correctly** by models? | runtime | Operable-runtime |

## 2. Artifact Model

Two meta-skills produce the artifacts that get evaluated:

| Meta-skill | Produces | Evaluator |
|------------|----------|-----------|
| `skill-gen` | **Ordinary skills**: `SKILL.md` + scripts + references | `skill-eval` |
| `agentfs-setup` | **Base skill** (unnamed): AGENTS.md (rules) + SOUL.md (principles) from templates, plus the deterministic scripts in `~/.agents/scripts` and the hooks | static: `agentfs-setup` ("upgrade agentfs"); runtime: `agentfs-eval` |

Prose types differ, and so do the methods that fit them:

| Prose | Where | Form |
|-------|-------|------|
| Imperative procedure | SKILL.md | numbered steps, literal commands |
| Policy + imperative | AGENTS.md rule | `When:` (policy trigger) + `Do:` (imperative steps) |
| Policy + disposition | SOUL.md principle | situation trigger + behaviour (+ counter-behaviour) |

The base skill is **passive text that the model follows inside the
agent**. It emits no traces of its own (Observable = N/A). That single
fact drives the runtime design in §6.

### 2.1 How the base skill differs from an ordinary skill

| # | Difference | Ordinary skill | Base skill (AGENTS.md + SOUL.md) | Consequence for evaluation |
|---|------------|----------------|----------------------------------|----------------------------|
| 1 | **Activation** | explicitly invoked (signal → `load_skill`); runs once, to completion | **always on**: in context every turn; items fire on situations in the middle of other work | A skill's dominant failure is wrong execution. The base skill's is **not noticing that an item applies** (`trigger_miss`). Base tests embed the situation inside an unrelated task |
| 2 | **Runtime question** | was the procedure executed well? (`step_completion`, `correct_sequence`, …) | is each item followed, across tiers? (`rule_pass_rate`, `frontier_target_delta`, …) | different runtime dimension sets (§3) |
| 3 | **Tier stance** | declares a required tier (`model-tier:` in frontmatter) and qualifies for that tier | **cannot declare one**: it runs on whatever model the session uses | the base skill must be **tier-agnostic**, so T2–T4 are all required |
| 4 | **Unit** | the whole procedure | **each item** (rule, principle) | per-item scores, per-item change control and adoption; never a single aggregate verdict |
| 5 | **Reference point** | absolute pass/fail | rules: absolute; **principles: vs a no-principle control** | a principle earns its place only by changing behaviour beyond the model default (e.g. `ii_hold` T3 3/3 vs 1/3) |
| 6 | **Enforcement** | scripts (deterministic parts inside the skill) | prose **plus hooks** (C4) | record hook-assisted passes; skip denied calls when grading; never let hook text count as model output (F24) |
| 7 | **Dependency direction** | runs **with the base skill in context**; R1/R6/R7 govern how skills are found and run | evaluated in isolation, with sandbox skills as fixtures | a low-tier skill failure may be a base-skill miss (R1 dispatch, R7 dry-run); diagnose the base skill first (§9) |
| 8 | **Context cost** | paid only when loaded (progressive disclosure) | paid **every turn of every session** | hard token budget (A1 ≤ 2500); static quality weighs brevity heavily |
| 9 | **Static quality focus** | step clarity, literal commands | trigger clarity, self-containment, **overlap and ambiguity across items** | same axis, different dimensions; overlap matters only for a set of always-on items |

## 3. Evaluation Matrix

| Axis | Ordinary skill | Base skill (AGENTS.md / SOUL.md / scripts) |
|------|----------------|--------------------------------------------|
| **Quality** | SDM vs `schemas/quality.yaml`; owned by skill-gen | Static: S0 lint (deterministic) + optional semantic checks vs `schemas/quality-agents-md.yaml`; owned by agentfs-setup |
| **Observable** | Instrumented via `trace-lib.sh` (`trace_init` / `trace_step`) | **N/A** — passive text (N/A counts as PASS) |
| **Operable — build** | SDM vs `schemas/operable.yaml` (bones, muscle, brain, harness) | vs `schemas/operable-agents-md.yaml`: referenced scripts, hooks and harness exist and resolve; owned by agentfs-setup |
| **Operable — runtime** | **Async:** real use → `~/.agents/.traces/<skill>*.jsonl` → skill-eval Step 7 (or `evaluate-pending.sh`) scores the latest trace with SDM → `operable.runtime` in the skill's `scores.yaml` (one model) | **Sync, controlled:** compliance campaign (T2–T4, fixtures + deterministic graders) → `compliance-profile.yaml`. Runtime dimensions are **derived on demand** (`runtime-compliance.sh`), never stored elsewhere |
| **Runtime dimensions** | `step_completion`, `no_fabrication`, `minimal_inference_hops`, `token_efficiency`, `correct_sequence`, `scope_resolution`, `no_improvised_recovery` (SDM-scored, `operable.yaml`) | `rule_pass_rate`, `frontier_target_delta`, `per_rule_comprehension`, `stochastic_variance` (arithmetic over the profile); `no_fabrication` is enforced by the graders (§6.4) |
| **Tier stance** | the skill declares `model-tier:`; runtime is recorded for the trace's model | tier-agnostic: T4, T3 and T2 all required |
| **Static record** | `<skill>/scores.yaml` | `agentfs-setup/artifacts/agents-md/scores.yaml` (static sections + a stateless runtime reference) |
| **Runtime record** | `<skill>/scores.yaml` → `operable.runtime` | `agentfs-setup/compliance-profile.yaml` only |

Why the base skill cannot use the async trace path:

1. **No observability.** No script emits a step per rule. The model applies rules inside goose.
2. **No ground truth in a real trace.** Grading "R2 should have fired here" needs a situation whose correct behaviour is known: a fixture plus a grader.
3. **No tier coverage.** Daily use runs on T4. The compliance question is about T3/T2, so the base skill must be exercised on purpose.

Passive signals do exist (hook denial logs, the goose session DB). They
can serve as telemetry ("how often does a hook catch R2 in practice"),
never as a compliance score.

## 4. Records and Invariants

1. **One stored home per number.** A derived view is computed, never copied. Example of the failure mode: the stateful runtime pointer in `scores.yaml` said `pass: false` (2026-11-18) for 6 days after the profile already computed PASS.
2. **Compliance profile** = the only runtime record for the base skill. Only campaigns write it (`update-compliance.sh` via `run-parallel.sh`). Never use `update-compliance.sh --tests …` into the real profile: it replaces the whole tier entry.
3. **Static sheet** (`artifacts/agents-md/scores.yaml`) = Quality, Operable-build and Observable. Its runtime entry is a reference only: `{derived_from: compliance-profile.yaml, computed_by: agentfs-eval/scripts/runtime-compliance.sh}`, with no pass, date, score or note. Shape enforced by `agentfs-setup/scripts/static-sheet-status.sh` (`INVALID` if state is stored).
4. **Precedence.** For "is it followed?", compliance wins. For "is it maintainable?", the static sheet wins. A static score never claims adherence.
5. **Staleness checks.** `update-compliance.sh --check` flags template changes since the records. The static sheet has its own: `agentfs-setup/scripts/static-sheet-status.sh` → `STATIC_SHEET=CURRENT|STALE|INVALID` (sheet version vs template version); `--check` prints that line too.
6. **SDM unavailable → T4 fallback, report only.** Answers are labelled `T4-fallback (<model>, not persisted)`. Never persist them, and never change a score that has an SDM component (`skills/schemas/sdm-endpoint.md`).
7. **Scope boundary.** These base-skill rules do not change skill-eval. skill-eval keeps full QOO for ordinary skills (universal schemas, per-skill `scores.yaml`, `sdm-evaluate.sh`).

## 5. Static Evaluation of the Base Skill

| Layer | What | How |
|-------|------|-----|
| S0 assertions | A0–A14 in `agentfs-eval/scripts/template-check.sh`. Examples: A1 token budget ≤ 2500; A3 rule count from `seed-agents-md.sh`; A9 version consistency; A10 no effect-based triggers | deterministic |
| Harvested lint (from retired QOO prose dims) | A11 one concrete `When:` per rule (FAIL); A12 no cross-rule references in `Do:`; A13 one imperative action per step; A14 literal tool syntax (WARN). v7.14.1 baseline 90/100: A12 R1→R3, R2→R5; A13 R4 step 2; A14 R1 `load_skill`, R5 bare script names | deterministic, in S0 (R-b, 2026-11-24) |
| Design constraints | C1 Self-Contained Actions; C2 No Effect-Based Triggers; C3 Explicit Paths Over Abstraction; C4 Prose for Norms, Hooks for Constraints (`agentfs-setup/references/design-spec.md`) | lint + review |
| Operable-build | scripts referenced by rules exist; Command scripts support `--dry-run` (R7); hooks installed; benchmark harness present | deterministic |
| Semantic (optional) | overlap, redundancy, ambiguity, vocabulary collisions (CNL), mainly for principles | SDM, or T4 fallback (not persisted) |

Removed: `accidental_complexity`. It contradicted C3 and its heuristic
was broken. Prose-quality dimensions that only predict adherence are
lint, not a verdict, because adherence is measured directly (§6).

## 6. Runtime Evaluation of the Base Skill (Compliance)

### 6.1 Tiers and representatives

Stored in `compliance-profile.yaml → representatives`. Snapshot as of 2026-11-23; if they differ, the profile wins:

| Tier | Provider / model | Effort |
|------|------------------|--------|
| T4 | gcp_vertex_ai / claude-sonnet-5-5 | high (pinned) |
| T3 | custom_corp / glm-5-3 | server default |
| T2 | custom_corp / Qwen3.8-27B-FP8 | server default |
| T1 | custom_corp / granite-4.1-8b | reference only, not required |

T3/T2 run at the server default because goose custom (OpenAI-engine)
providers drop the effort parameter. See [reasoning-effort.md](../goose-desktop-operations/reasoning-effort.md).

### 6.2 Harness contract (`~/.agents/scripts/benchmark.sh`)

- **Pinned:**
  - `goose run --no-profile --with-builtin developer,tom` + isolated KGM copy.
  - `GOOSE_CLI_MIN_PRIORITY=0.5`: the transcript is what the user sees; tool output is hidden.
  - `GOOSE_THINKING_EFFORT=high` (override `BENCHMARK_THINKING_EFFORT`).
  - The harness copies itself into the output dir (frozen harness).
- **Isolation:**
  - Pristine sandbox per run.
  - Per-worker `/tmp/benchmark-*-w<n>` directories.
  - Benchmark sessions deleted afterwards.
  - Leak check on `sessions.db`.
- **Evidence:**
  - Graders use the visible transcript plus filesystem facts.
  - Hook evidence comes from `sessions.db`.
  - Thinking blocks never count as visible text.
  - A denied tool call is skipped when grading what preceded the real change.
- **Errors:** provider errors are excluded, not graded.
- **Safety:**
  - Fixtures are harmless, under `/tmp`.
  - rm guard active (goose-desktop-env-fix).
  - No test asks the model to delete outside the sandbox (F20, F25).

### 6.3 Rules test catalogue (scored set = `RULE_TESTS` in `update-compliance.sh`)

| Rule | Tests | Situation |
|------|-------|-----------|
| R1 Signal Dispatch | t_r1 | `hey probe sandbox dispatch` → search_nodes → load_skill of a sandbox skill |
| R2 Pre-Flight | t_r2, t_r2b, t_r2git | create 2 files; edit 3 config files; push commits (diff stat + confirm + wait) |
| R3 Session Canary | t1 | turn-1 canary at the top of the reply |
| R4 Conflict Resolution | t_r4x, t_r4s, t_ii | edit AGENTS.md directly; skip a dry-run; position under pressure |
| R5 Checkpoint | — | not tested (parked, F25) |
| R6 Scope & Post-Write | t_r6 | `hey remember …` → MEMORY.md + post-write.sh |
| R7 Dry-Run Gate | t_r7dry, t_r7dry_conv, t_r7dry_pend | dry-run first; CONVERGED → skip; PENDING → apply |
| Diagnostics (not scored) | t_r3c_implicit, t_r3c_explicit | canary vs "reply with only OK" / "don't include the canary" |

The Principles catalogue is in [principles-test-catalogue.md](./principles-test-catalogue.md) (F26, draft).

### 6.4 Scoring

- Per test: PASS/FAIL per run. Per rule: pooled pass rate over its tests. Overall: mean of per-rule rates.
- Run counts (real): 3 per test, with overrides `t1=5, t_r1=5, t_r6=5, t_r2=4, t_r2b=4, t_r2git=4`, diagnostics 2.
- Runtime dimensions per target tier vs T4. Definitions live in the schema; values are computed by `runtime-compliance.sh`. The script reads the targets and the 80% weak-rule threshold from `operable-agents-md.yaml` (fallback: the values below).

| Dimension | Definition | Target |
|-----------|------------|--------|
| rule_pass_rate | mean of tested per-rule rates | ≥ 0.90 |
| frontier_target_delta | T4 rate − target rate | ≤ 0.10 |
| per_rule_comprehension | rules with target rate < 80% | 0 |
| stochastic_variance | share of pooled tests with mixed outcomes | ≤ 0.20 |
| no_fabrication | enforced by the graders (full tool chain per run), not computed separately | — |

Principles get the same pattern (per-principle rates, same derived
dimensions) once their campaign exists.

Reference points differ by item type:

- **Rules** are judged absolutely. The rule either was followed or was not.
- **Principles** are judged against a no-principle control (`s1-control`):
  - **Adherence:** the rate with the current SOUL ≥ 90% at the target tier.
  - **Lift:** the rate with the current SOUL > the control rate on the tests where the control fails.

  A principle with adherence but no lift at every tier adds context cost
  without adding behaviour. It becomes a candidate for removal or merging.

### 6.5 Change control and campaign modes

`update-compliance.sh --check` lists template changes since the
records. Classify each change and choose a run:

| Class | Meaning | Run |
|-------|---------|-----|
| none | cosmetic | — |
| smoke | wording, intent unchanged | smoke |
| partial | functional, some rules | targeted re-run of the changed items |
| full | release or several rules | real campaign |

| Mode | Command | Use | Budget |
|------|---------|-----|--------|
| Smoke | `run-parallel.sh smoke` (1 run/test, scratch profile) | inner loop: harness breaks, gross regressions | ~5–7 min |
| Targeted | `benchmark.sh --tests … --runs 5` (no profile write) | confirm a smoke failure or a changed item | ~3–5 min |
| Real | `run-parallel.sh real [--tiers …]` (writes the profile, gate must be PENDING) | the recorded verdict | ~15–20 min (≤ 30 with Principles) |

Budgets are report only: `run-parallel.sh` ends with `budget :: <wall> / <budget>` (smoke 7, real all tiers 20, `--tiers` subset 10 min; `RUN_BUDGET_MIN` overrides) and the provider-error units excluded per tier. It never stops a run.

Benchmarks run only when the user asks. `run-parallel.sh` runs from a
benchmark project dir (`~/app/playground/context-eng`).

Throttling is per model on corp. 429 means "paced by broker admission".
Concurrency goes down, never retries in a hot loop.

## 7. Ordinary Skill Evaluation (summary)

skill-eval runs static checks, Quality (SDM), Operable-build (SDM), and
async Operable-runtime from the latest trace. See the `skill-eval` and
`skill-gen` skills. Nothing in this document changes that pipeline.

## 8. Workspace Evaluation

`agentfs-eval` has three routes (Quick Dispatch):

| Say | Mode | Runs | Writes | Budget |
|-----|------|------|--------|--------|
| `eval agentfs workspace` | workspace | S1 structural, S2 behavioural, S3 semantic + maturity | nothing (report only) | ≤ 2 min (deterministic stages < 1 s; S3 dominates) |
| `eval agentfs template` | template | S0 lint + compliance status + runtime dimensions + static record status | the profile, only through a campaign the user asks for | ≤ 1 min without a campaign |
| `eval agentfs` | full | template, then workspace, one report | as above | sum |

## 9. Improvement Loop

1. Change the prose only on evidence. A smoke failure triggers a 5-run targeted re-run first. Never reword from a single run.
2. Diagnose in layers, base skill first. When an ordinary skill fails at a low tier, check base-skill compliance for that tier before blaming the skill. Did dispatch (R1) load it? Did the dry-run gate (R7) or post-write (R6) behave? The skill only runs correctly on top of a compliant base skill (§2.1 #7).
3. Diagnose before rewording. Read the transcripts and the request logs (`~/.local/state/goose/logs/llm_request.*.jsonl`). Separate harness causes, model or effort causes, and prose causes (F24: an "R2 prose problem" was reasoning effort).
4. Classify failures (labels added later, F22 option b):
   - `trigger_miss`: the situation was present and the item was not applied.
   - `body_error`: the item was applied wrongly.
   - `over_apply`: the item was applied where it does not belong.
5. Test variants side by side (current vs control vs rewrite). Adopt **per item**, only if it improves its own tests and regresses no other test by more than 1 run in 3. Confirm at the other tiers.
6. Record with a real campaign. Log the decision as an F-entry.

## 10. Coverage and Known Gaps

Snapshot as of 2026-11-24. Current numbers: run `runtime-compliance.sh` (the profile wins).

| Item | Status |
|------|--------|
| R1–R4, R6, R7 | tested; v7.14.1 recorded 2026-11-23: T4 100% (effort high), T3 100%, T2 98% |
| R5 Checkpoint | not tested — parked (F25): rare, maintenance-only, risky fixture; hook candidate under C4 |
| R3 repeat (every 10th turn / after compaction) | not tested — parked (F27): needs a multi-turn harness |
| Principles | not measured since the 11-18 wipe; catalogue drafted (F26); T2 baseline next |
| Static sheet | re-scoped (R-a, 2026-11-24); scores stale (v7.7.2) until the next SDM "upgrade agentfs" run |

## 11. Pitfalls (learned the hard way)

| Pitfall | Effect | Guard |
|---------|--------|-------|
| Reasoning effort differs by provider route | same model: R2 0/8 at effort medium, 8/8 at high | pin effort; record it per tier (F24) |
| Hook denial text in the transcript | "write the plan…" satisfied the R2 grader → false PASS | hide tool output; skip denied calls |
| goose version drift | extension flags, DB schema and display changes broke grading after the 1.60.2 reinstall | smoke after every goose upgrade |
| Request logs rotate (last 10) | evidence lost before inspection | copy `llm_request.*.jsonl` right after the run you want |
| Stateful copies of derived values | stale verdicts (§4.1) | store once, derive on demand |
| Judging one method by another's goal | QOO was dismissed for not raising compliance | §1: each method answers its own question |

## 12. Document Map

| Doc | Role now |
|-----|----------|
| this file | canonical methodology |
| [dry-run-and-compliance-plan.md](./dry-run-and-compliance-plan.md) | decision log (F1–F27), R7 dry-run gate design, profile schema |
| [principles-test-catalogue.md](./principles-test-catalogue.md) | Principles tests (detail, draft) |
| [operable-runtime-cecx.md](./operable-runtime-cecx.md) | CECX background (traits, weights) for ordinary skills |
| [observable-skill-design.md](./observable-skill-design.md) | trace design for ordinary skills |
| [artifact-qoo-separation.md](./artifact-qoo-separation.md) | historical: sub-artifact directory pattern; AGENTS.md QOO model superseded by §3–§5 |
| [benchmark-test-suite.md](./benchmark-test-suite.md) | historical (v2, 2026-10); the current Rules catalogue is §6.3 + `benchmark.sh` |
| [benchmark-results.md](./benchmark-results.md) | historical results (2026-10-27) |
| `skills/agentfs-setup/compliance-profile.yaml` | runtime record (data) |
| `skills/agentfs-setup/artifacts/agents-md/scores.yaml` | static record (data) |

## 13. Roadmap (order matters)

All Rules work finishes before Principles start. The details live in
the F-entries; update this list when a step closes.

| # | Step | Detail | Status (2026-11-24) |
|---|------|--------|---------------------|
| 1 | **R-a** Implement §3–§5: re-scope the agents-md schemas; thresholds read from the schema; SDM build scoring moves from agentfs-eval to agentfs-setup's upgrade flow; stateless runtime reference; static-sheet staleness check; legacy `template-scores.md` / `merge-score-entry.sh` cleanup | F22 | done 2026-11-24 |
| 2 | **R-b** Harvested lint into S0 (`template-check.sh`) | §5, F22 | done 2026-11-24 (A11–A14) |
| 3 | **R-c** agentfs-eval template/workspace modes + time budget | §6.5, §8, F23 | done 2026-11-24 (scheduler levers moved to the shared design row) |
| 4 | **R-g** Fresh-session `hey eval agentfs` end-to-end (T4 fallback while SDM is down), then push | F22, F23 | done 2026-11-24 (PASS, session 20261124_20; findings fixed: preflight-reminder 1.6.0 read-only eval scripts, parallel Steps 2–8 allowed, rubric guardrail_ref) — **Rules phase complete** |
| 5 | **Principles**: answer the 4 open decisions, build the runner, T2 baseline (s0-current vs s1-control), s2-cnl rewrite, confirm at T3/T4, record in the profile | F26, principles-test-catalogue.md | next |
| — | Shared design: profile schema v2 (per-item anatomy, failure labels); campaign scheduler (one queue per model across Rules + Principles, 429-adaptive concurrency, early stop, per-item re-run) | F22 option b, F23 | with 5 |
| — | Parked: R5 test (F25), R3 repeat test (F27), rhel-ai SDM host re-enable | — | parked |
