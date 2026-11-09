---
title: "Skill QOO Qualification Plan — Full Portfolio"
parent: agentfs-engineering-evolution
created: 2026-11-04
updated: 2026-11-04
tags: [qoo, qualification, model-tier, skill, portfolio, plan]
---

# Skill QOO Qualification Plan — Full Portfolio

- **Type:** Convention
- **Status:** 🟡 IN PROGRESS — Phases A+B complete
- **Predecessor:** Implementation Plan Phases 0-6 (all complete)
- **Source:** Session analysis — tiered model classification and
  portfolio-wide QOO qualification strategy

## Context

Phases 0-6 built the QOO infrastructure and validated it on two
skills (agentfs-readme-audit, crc-status). Both are now qoo-qualified.
This plan extends qualification to all 59 skills in the portfolio.

**Key insight:** Not all skills are designed for the same model class.
A skill that requires generative output, multi-mode dispatch, and
compositional judgment (e.g., skill-gen) will never be reliably
operable on a 14B model — and forcing it would degrade the skill's
value. QOO qualification must be tier-aware.

## Design Principles

> QOO measures skill quality relative to its intended model class.
> A T3 skill scoring 55 on Quality is acceptable — the prose
> complexity is a feature, not a defect. A T1 skill scoring 55
> is a problem — there's no reason a mechanical skill should be
> unclear.

> **No skill left behind.** Every skill must either qualify at its
> tier or be reclassified until it does. Two levers exist before
> declaring a skill unqualified:
>
> 1. **Re-engineer the skill** — fix structural gaps (add scripts,
>    steps, output contracts) so it meets its current tier's thresholds.
> 2. **Reclassify the tier** — if the skill's cognitive demand was
>    underestimated, move it to the correct tier (e.g., T2→T3 or
>    T3→T4) where its complexity is a feature, not a defect.
>
> Only skills that are genuinely not workflow skills (stubs,
> pointers, config snippets) may be exempted as `model-tier: n/a`.

## Model Tier Classification

### Tier Definitions

| Tier | Model Class | Min. Capability | Characteristics |
|------|------------|-----------------|-----------------|
| **T1** | Any model (8B+) | Basic instruction following | Script-driven, ≤3 steps, no judgment. Model is a shell invoker. |
| **T2** | Mid-range (14B+) | Structured reasoning | Scripts do heavy lifting, model follows a recipe. Conditionals are simple if/else. Some multi-mode dispatch. |
| **T3** | Strong (30B+) | Moderate judgment | Conditional workflows with interpretation, domain context, diagnostic reasoning. May require multi-hop inference. |
| **T4** | Frontier only | Creative/analytical | Multi-mode dispatch, generative output, evaluation/judgment-heavy, complex compositional reasoning. |

### Classification Axes

Four axes determine a skill's tier:

1. **Cognitive Load** — Steps × conditionals × judgment indicators.
   More steps with more branching = higher model demand.
2. **Generative Demand** — Does it create novel content (not just
   run scripts and report output)?
3. **Domain Expertise** — Does it require specialized knowledge
   (OpenShift, networking, LLM serving) beyond what's in SKILL.md?
4. **Script Coverage** — How much is automated vs. prose-orchestrated?
   High script coverage *reduces* tier (scripts absorb complexity).

### Per-Tier QOO Qualification Targets

| Tier | Quality | Observable | Build | Runtime (CECX) | Rationale |
|------|:-------:|:----------:|:-----:|:--------------:|-----------|
| **T1** | ≥75 Tunable | ≥75 Tunable | ≥75 Tunable | Exempt | Mostly scripts — should be clear and portable |
| **T2** | ≥75 Tunable | ≥75 Tunable | ≥75 Tunable | Exempt | Achievable with good CNL + Output Contracts |
| **T3** | ≥50 Re-engineer | ≥50 Re-engineer | ≥75 Tunable | Exempt | Accept lower Q+O — judgment steps inherently score lower |
| **T4** | Informational | Informational | ≥75 Tunable | Exempt | Measure but don't gate — frontier-dependent by design |

**qoo-qualified formula (tier-aware):**
```
T1/T2: quality.band ∈ {Tunable, Operable}
       AND observable.band ∈ {Tunable, Operable}
       AND operable.build.band ∈ {Tunable, Operable}

T3:    quality.band ∈ {Re-engineer, Tunable, Operable}
       AND observable.band ∈ {Re-engineer, Tunable, Operable}
       AND operable.build.band ∈ {Tunable, Operable}

T4:    operable.build.band ∈ {Tunable, Operable}
       (quality and observable are informational — scored but not gated)
```

**Runtime CECX is exempt from all tiers.** CECX requires execution
traces which are model-dependent and environment-dependent. CECX
scores are valuable diagnostics but not a qualification gate.

### Why the Bar Differs by Tier

The qualification bar is strict for T1/T2 precisely because those
skills should be crystal clear if they're truly that mechanical.
A T1 skill has no excuse for being unclear — it's "run this script,
report the output." If a small model can't follow it, the skill's
prose is the problem.

A T3 skill that requires OpenShift domain reasoning will inherently
score lower on Quality dimensions like `step_clarity` and
`inference_hop_count` because the steps genuinely require judgment.
Penalizing that would force dumbing down the skill.

T4 goes further — Quality and Observable are purely informational
because skills like "generate bash completions" or "clean up orphaned
sessions" require creative/analytical work that can't be reduced to
CNL checklists. Only the build infrastructure (scripts exist, have
logic, have validation) is gated.

**The tier classifies the skill's cognitive demand, not the skill's
importance.** A T1 skill isn't less valuable — it's just easier for
a model to execute correctly.

### Per-Skill Tier Rationale

**T4 — Frontier only (build gate)**

| Skill | Rationale |
|-------|-----------|
| bash-completion-gen | Generative — model must author bash completion scripts from scratch based on CLI analysis |
| goose-desktop-env-fix | Diagnostic + generative — 468L, model must detect env issues across shells/DEs, generate fixes contextually |
| goose-recipe-session-cleanup | Analytical — 500L, model must identify orphaned sessions, evaluate what's safe to remove, handle multiple session types |
| goose-nextai-drawio | Generative — model orchestrates Draw.io extension setup with contextual configuration |
| ocp-containerfile | Generative — model must audit/generate Containerfiles applying OpenShift best practices |
| skill-gen | Generative — model creates new skills from scratch, scoring and iterating on quality |
| skill-eval | Analytical — model evaluates skill quality across multiple dimensions, produces structured scores |
| agentfs-eval | Analytical — model audits AgentFS health, checks violations, produces maturity scores |

**T3 — Strong model (relaxed Q/O)**

| Skill | Rationale |
|-------|-----------|
| crc-ctl | Domain expertise (CRC lifecycle), conditional workflows (start/stop/clean differ), disk cleanup requires judgment |
| crc-aap-demo-config | Domain expertise (AAP on OpenShift), multi-step operator install with interpretation of cluster state |
| crc-cmd | Conditional (install crcstart vs crcstop), domain knowledge of CRC wrapper behavior |
| crc-ovn-frr-metallb-config | Heavy domain (OVN + FRR + MetalLB + BGP), 357L, multi-component networking setup requiring understanding of interactions |
| crc-coo-config | Domain expertise (Cluster Observability on OpenShift), operator lifecycle with prerequisite checking |
| crc-noo-config | Domain expertise (Network Observability), FlowCollector CR with eBPF feature configuration |
| crc-nmstate-config | Domain expertise (NMState operator), multi-resource creation with CSV wait logic |
| crc-nad-dynamic-plugin-config | Domain expertise (NAD console plugin), Helm-based deploy with console plugin verification |
| crc-post-setup-config | Domain expertise (CRC tuning), multi-part setup (monitoring + kubelet + alerts) requiring sequencing |
| dsh-litellm-provider | Multi-mode (configure/verify/troubleshoot), LiteLLM domain knowledge, provider-specific config interpretation |
| fedora-nm-boot-slow | Diagnostic — model must analyze boot logs, identify NM-wait-online causes, select from multiple fix strategies |
| goose-headroom-provider | 392L, multi-mode provider config, model interprets proxy topology and upstream routing |
| hermes-desktop-fixes | Diagnostic — model identifies electron/desktop issues, selects appropriate fix from multiple patterns |
| okf-bundle-gen | 714L, multi-step knowledge generation with schema interpretation, domain judgment on concept extraction |
| okf-bundle-harvest | 517L, model must evaluate conversation history, identify graduation candidates, make quality judgments |
| agentfs-ctx-chk | 295L, context audit requires interpreting skill/knowledge structure, identifying anomalies — analytical work |
| goose-agentfs-setup | 465L, multi-mode dispatch (configure/sync/activate profile), conditional logic across scopes |
| okf-bundle-index | 324L, index repair requires structural analysis of knowledge bundles and cross-reference validation |
| spec-kit-setup | Multi-step install with version detection, comparison logic, and conditional upgrade paths |

**T2 — Mid-range model (strict bar)**

| Skill | Rationale |
|-------|-----------|
| agentfs-profile | Recipe-following — 127L, 2 scripts, 4 steps. Model creates agent profiles by following a template. Simple conditionals. |
| agentfs-git-push | Recipe with safety checks — 217L, 1 script. Model runs pre-push scan, reviews output, confirms push. |
| agentfs-readme-audit | Script-driven audit — model runs script, reports findings. Structured output interpretation. |
| hermes-agentfs-setup | Recipe — 4 steps to configure Hermes skill directories. Simple file operations. |
| goose-kgm | Multi-mode dispatch but each mode is a single script call. Simple conditionals. |
| skupper-model-provider | Multi-mode dispatch — 8 operations, but each is a single script call with clear output. |
| dsh-setup | Multi-mode (install/update/teardown/status) — each mode delegates to a script. |

**T1 — Mechanical (strict bar)**

| Skill | Rationale |
|-------|-----------|
| All T1 skills | Script-driven, ≤3 steps, no judgment. Model is a shell invoker. Examples: fedora-window-list (toggle script), goose-cli-fix (repair script), crc-status (status check). |

## Full Skill Classification (59 skills)

### T1 — Mechanical (14 skills)

Target: Quality ≥75, Observable ≥75, Build ≥75.

| Skill | Lines | Scripts | Steps | Status | Notes |
|-------|:-----:|:-------:|:-----:|:------:|-------|
| agentflow-fuseki | 116 | 4 | 4 | 🔲 | High script coverage — should score well |
| crc-nad-dynamic-plugin-config | 170 | 0 | 0 | 🔲 | Needs step structure |
| crc-nmstate-config | 171 | 0 | 0 | 🔲 | Needs step structure |
| crc-noo-config | 190 | 0 | 0 | 🔲 | Needs step structure |
| crc-post-setup-config | 124 | 0 | 3 | 🔲 | Needs scripts |
| crc-status | 103 | 1 | 2 | ✅ QUALIFIED | Quality 76.5 Tunable |
| fedora-desktop-wmclass-fix | 176 | 1 | 0 | 🔲 | Has script, needs step structure |
| fedora-obsidian-fix | 141 | 2 | 0 | 🔲 | Has scripts, needs step structure |
| fedora-window-list | 61 | 0 | 3 | 🔲 | Simple prose, small |
| goose-cli-fix | 73 | 0 | 0 | 🔲 | Tiny diagnostic |
| goose-kgm | 162 | 8 | 6 | 🔲 | 8 scripts — should score well |
| hermes-headroom-provider | 22 | 0 | 0 | 🔲 | Stub — may need expansion |
| skill-index | 62 | 0 | 0 | 🔲 | Utility |
| skill-merge | 113 | 0 | 0 | 🔲 | Utility |

### T2 — Structured (26 skills)

Target: Quality ≥75, Observable ≥75, Build ≥75.

| Skill | Lines | Scripts | Steps | Status | Notes |
|-------|:-----:|:-------:|:-----:|:------:|-------|
| agentfs-archify | 138 | 0 | 0 | ✅ exempt | Upstream copy (tt-a1i/Archify, MIT). Not subject to QOO modification. |
| agentfs-git-push | 217 | 1 | 10 | 🔲 | Well-structured, 1 script |
| agentfs-profile | 126 | 2 | 4 | 🔲 | Small, scripted |
| bash-completion-gen | 311 | 0 | 8 | 🔲 | No scripts — prose-heavy |
| crc-aap-demo-config | 249 | 0 | 6 | 🔲 | Domain-specific setup |
| crc-cmd | 281 | 0 | 4 | 🔲 | Conditional, no scripts |
| crc-coo-config | 109 | 0 | 0 | 🔲 | Operator install |
| crc-ctl | 265 | 1 | 10 | 🔲 | Lifecycle (start/stop/clean) |
| crc-ovn-frr-metallb-config | 356 | 0 | 10 | 🔲 | Complex networking, no scripts |
| dsh-litellm-provider | 163 | 2 | 4 | 🔲 | Multi-mode, scripted |
| dsh-setup | 179 | 6 | 4 | 🔲 | 6 scripts — should score well |
| fedora-dns-cache | 122 | 1 | 0 | 🔲 | Has script, needs steps |
| goose-agentfs-setup | 464 | 3 | 26 | 🔲 | Large but mostly recipe steps |
| goose-nextai-drawio | 200 | 1 | 4 | 🔲 | Scripted lifecycle |
| goose-setup | 123 | 0 | 4 | 🔲 | Config — small |
| goose-skupper-provider | 160 | 3 | 5 | 🔲 | Scripted lifecycle |
| headroom-litellm-proxy | 282 | 0 | 7 | 🔲 | All prose |
| headroom-proxy-status | 135 | 0 | 0 | 🔲 | Status check |
| hermes-agentfs-setup | 180 | 1 | 6 | 🔲 | Config + script |
| hermes-litellm-provider | 204 | 2 | 6 | 🔲 | Multi-mode, scripted |
| litellm-proxy-status | 81 | 0 | 0 | 🔲 | Status check |
| litellm-vertex-ai-proxy | 221 | 6 | 6 | 🔲 | 6 scripts — should score well |
| ocp-containerfile | 163 | 3 | 4 | 🔲 | Scripted |
| okf-bundle-index | 323 | 2 | 13 | 🔲 | Scripted index management |
| skupper-model-provider | 212 | 8 | 7 | 🔲 | 8 scripts — should score well |
| spec-kit-setup | 119 | 1 | 2 | 🔲 | Small, scripted |

### T3 — Interpretive (14 skills)

Target: Quality ≥50, Observable ≥50, Build ≥75.

| Skill | Lines | Scripts | Steps | Status | Notes |
|-------|:-----:|:-------:|:-----:|:------:|-------|
| agentfs-ctx-chk | 284 | 0 | 15 | 🔲 | Context audit — judgment-heavy |
| agentfs-readme-audit | 173 | 3 | 4 | ✅ QUALIFIED | Quality 90.3 Operable |
| agentfs-setup | 462 | 19 | 17 | 🔲 | Large but well-scripted |
| crc-ols | 556 | 3 | 13 | 🔲 | 10 dispatch modes |
| fedora-nm-boot-slow | 226 | 0 | 5 | 🔲 | Diagnostic — judgment-heavy |
| goose-desktop-env-fix | 457 | 0 | 13 | 🔲 | All prose, highly conditional |
| goose-headroom-provider | 381 | 0 | 12 | 🔲 | All prose |
| goose-litellm-provider | 273 | 2 | 8 | 🔲 | 7 dispatch modes |
| goose-recipe-session-cleanup | 489 | 0 | 4 | 🔲 | Highly conditional prose |
| hermes-desktop-fixes | 192 | 0 | 12 | 🔲 | Diagnostic, all prose |
| hosted-model-ctl | 209 | 10 | 17 | 🔲 | 10 scripts — well-scripted |
| okf-bundle-gen | 703 | 2 | 14 | 🔲 | Generative, large |
| okf-bundle-harvest | 506 | 2 | 12 | 🔲 | Generative, judgment |
| okf-bundle-setup | 508 | 3 | 12 | 🔲 | Conditional, multi-phase |

### T4 — Analytical (5 skills)

Target: Build ≥75 only. Quality + Observable are informational.

| Skill | Lines | Scripts | Steps | Status | Notes |
|-------|:-----:|:-------:|:-----:|:------:|-------|
| agentfs-eval | 558 | 6 | 29 | 🔲 | Meta-evaluation, 17 judgment indicators |
| goose-maas-provider | 522 | 0 | 22 | 🔲 | 9 dispatch modes, all prose |
| skill-eval | 570 | 1 | 39 | 🔲 | 29 judgment indicators, 5 modes |
| skill-gen | 1157 | 1 | 28 | 🔲 | 13 dispatch modes, generative, 27 judgment |
| skill-harvest | 525 | 1 | 12 | 🔲 | Generative, pattern extraction |

## Infrastructure Changes

### Infra 1 — SKILL.md Frontmatter: `model-tier` Field

**What:** Add `model-tier` to SKILL.md YAML frontmatter as the
source of truth for the skill's tier classification.

**Where:** Every SKILL.md `metadata:` block.

**Format:**
```yaml
metadata:
  author: agentfs
  version: "2.1.0"
  model-tier: T2
  tags: [...]
```

**Valid values:** `T1`, `T2`, `T3`, `T4`

**Who sets it:** Human decision, persisted by skill-gen during
creation or manually added to existing skills.

### Infra 2 — scores.yaml: Tier-Aware Qualification

**What:** Update the qoo-qualified computation to read `model-tier`
from SKILL.md frontmatter and apply the corresponding band thresholds.

**Where:** Scoring pipeline (skill-gen Score Skill mode, skill-eval
Assess mode) — wherever `qoo-qualified` is computed.

**Logic:**
```
model_tier = read from SKILL.md frontmatter metadata.model-tier
if model_tier in (T1, T2):
    qualified = Q>=75 AND O>=75 AND B>=75
elif model_tier == T3:
    qualified = Q>=50 AND O>=50 AND B>=75
elif model_tier == T4:
    qualified = B>=75
else:
    # No tier set — use strict T1/T2 thresholds as default
    qualified = Q>=75 AND O>=75 AND B>=75
```

**scores.yaml additions:**
```yaml
model_tier: T2              # copied from SKILL.md frontmatter
qualification_rule: T2      # which rule was applied
qoo-qualified: true
```

### Infra 3 — Batch Scoring Script: `score-all.sh`

**What:** New script that iterates all skills, runs
`gather-skill-state.sh` + `sdm-evaluate.sh` for Quality + Observable,
persists results to each skill's `scores.yaml`.

**Where:** `~/.agents/scripts/score-all.sh`

**Features:**
- Skip skills that already have `scores.yaml` (unless `--force`)
- Read `model-tier` from each SKILL.md frontmatter
- Compute tier-aware `qoo-qualified`
- Output portfolio summary at end
- `--tier T1` flag to score only one tier
- `--dry-run` to list what would be scored without SDM calls

**Estimated runtime:** ~20 seconds per skill × 57 = ~19 minutes.

### Infra 4 — Portfolio Report: `qoo-report.sh`

**What:** New script that reads all `scores.yaml` files and produces
a portfolio-level QOO dashboard.

**Where:** `~/.agents/scripts/qoo-report.sh`

**Output format:**
```
QOO Portfolio Report — 59 skills
═══════════════════════════════════════════════════

Tier Distribution:
  T1 (Any model):   14 skills
  T2 (Mid-range):   26 skills
  T3 (Strong):      14 skills
  T4 (Frontier):     5 skills

Qualification Status by Tier:
  T1:  12/14 qualified (86%)  ████████████████░░░░
  T2:  20/26 qualified (77%)  ████████████████░░░░
  T3:  10/14 qualified (71%)  ██████████████░░░░░░
  T4:   4/5  qualified (80%)  ████████████████░░░░
  ALL: 46/59 qualified (78%)

Unqualified Skills:
  T1: crc-post-setup-config (Q=45), hermes-headroom-provider (Q=30)
  T2: bash-completion-gen (Q=55), headroom-litellm-proxy (Q=60)
  ...

Top Improvement Opportunities (biggest single-dimension gaps):
  1. bash-completion-gen — interface_opacity=0 → fix prose refs
  2. crc-cmd — script_coverage=0 → extract scripts
  ...
```

### Infra 5 — `hey score all` / `hey assess all` Signals

**What:** Add batch signal phrases to skill-gen (score all) and
skill-eval (assess all) for portfolio-wide operations.

**Where:**
- `skill-gen/SKILL.md` — add `score all skills` to dispatch table
- `skill-eval/SKILL.md` — add `assess all skills` to dispatch table

**Behavior:** Load batch script, iterate, produce portfolio report.

### Infra 6 — gather-skill-state.sh: Extract model-tier

**What:** Add `model-tier` to the facts output so SDM evaluations
and scoring scripts can read it.

**Where:** `~/.agents/scripts/gather-skill-state.sh`

**Output line:** `Model tier: T2` (read from SKILL.md frontmatter)

## Execution Phases

### Phase A — Tier Classification (no scoring) ✅ COMPLETE

**Goal:** Set `model-tier` in every SKILL.md frontmatter. Pure metadata.

**Steps:**
1. For each of the 59 skills, add `model-tier: T1|T2|T3|T4` to the
   `metadata:` block in SKILL.md frontmatter.
2. Use the classification table above as the source.
3. Run post-write.sh for each modified skill.
4. Commit and push.

**Effort:** ~30 minutes (batch edit + post-write).

**Deliverable:** All 59 SKILL.md files have `model-tier` in frontmatter.

**Validation:** `grep -r 'model-tier' ~/.agents/skills/*/SKILL.md | wc -l` = 59.

### Phase B — Infrastructure Build ✅ COMPLETE

**Goal:** Build the batch scoring and reporting tools.

**Steps:**
1. Create `~/.agents/scripts/score-all.sh` (Infra 3).
2. Create `~/.agents/scripts/qoo-report.sh` (Infra 4).
3. Update `gather-skill-state.sh` to extract `model-tier` (Infra 6).
4. Update qualification computation in scoring pipeline to be
   tier-aware (Infra 2).
5. Add batch signals to skill-gen and skill-eval (Infra 5).
6. Test `score-all.sh --dry-run` and `qoo-report.sh` against the
   2 already-scored skills.

**Effort:** ~2-3 hours.

**Deliverable:** `score-all.sh`, `qoo-report.sh`, tier-aware
qualification, batch signals.

**Validation:**
- `score-all.sh --dry-run` lists 57 skills to score.
- `qoo-report.sh` shows 2/59 qualified (current state).
- `score-all.sh --tier T1 --force` scores the 14 T1 skills.

### Phase C — Batch Baseline Scoring

**Goal:** Score all 57 unscored skills. Establish the portfolio baseline.

**Steps:**
1. Run `score-all.sh` (or `hey score all skills`). ~19 min.
2. Run `qoo-report.sh` for the initial portfolio snapshot.
3. Review output. Identify:
   - Already-qualified skills (pass without changes)
   - Near-miss skills (1-2 dimensions away from passing)
   - Deep-rework skills (multiple dimensions failing)
4. Persist portfolio report to
   `~/.agents/knowledge/agentfs-engineering-evolution/qoo-portfolio-baseline.md`.
5. Commit and push.

**Effort:** ~30 minutes (mostly waiting for SDM + review).

**Deliverable:** All 59 skills have `scores.yaml`. Portfolio baseline documented.

**Validation:** `qoo-report.sh` shows scores for all 59 skills.

### Phase D — T1 Quick Wins

**Goal:** Qualify all T1 skills. These are the easiest wins.

**Priority order:** Score-descending (fix highest-scoring first).

**Common fix patterns for T1:**

| Pattern | Fix | Effort |
|---------|-----|:------:|
| No step structure | Add `### Step N` headings to Workflow section | 5 min |
| No Output Contract | Add Output Contract section (document script output) | 5 min |
| interface_opacity | Reframe prose to not reference script internals | 10 min |
| No anti-fabrication | Add "Do NOT fabricate" rule | 2 min |
| No trace_step() | Add `source trace-lib.sh` + `trace_step()` to scripts | 5 min |
| No scripts at all | Extract inline commands to `scripts/` | 15-30 min |

**Steps:**
1. Sort T1 skills by Quality score (highest first).
2. For each unqualified T1 skill:
   a. Read scores.yaml — identify failing dimensions.
   b. Apply the appropriate fix pattern from the table above.
   c. Re-score: `hey score skill <name>`.
   d. If Quality + Observable + Build all pass → qualified.
   e. If still failing after fixes → apply Reclassification Protocol
      (see below). Move to T2 if cognitive demand was underestimated.
   f. Bump version, commit.
3. For stub/utility skills too minimal for workflow evaluation,
   either expand to a proper skill or mark `model-tier: n/a` with
   documented justification.
4. Run `qoo-report.sh` after each batch of fixes.

**Effort:** ~2-3 hours total (14 skills, ~10-15 min each on average).

**Deliverable:** 14/14 T1 skills qualified or reclassified. ≤2 exempt as n/a.

### Phase E — T2 Systematic Fixes

**Goal:** Qualify T2 skills using the same fix patterns, plus
structural improvements for larger skills.

**Priority order:**
1. Scripted T2 skills first (dsh-setup, litellm-vertex-ai-proxy,
   skupper-model-provider — these have scripts and should score well).
2. Prose T2 skills second (headroom-litellm-proxy, crc-ovn-frr-metallb-config).

**Additional fix patterns for T2:**

| Pattern | Fix | Effort |
|---------|-----|:------:|
| Multi-mode dispatch without clear routing | Add Quick Dispatch table | 10 min |
| Long prose workflows | Extract to scripts where mechanical | 30-60 min |
| Missing Specification table | Add S1-SN capability table | 10 min |

**Steps:**
1. Sort T2 skills by Quality score (highest first).
2. Batch 1: Fix scripted T2 skills (expect 10-15 to pass quickly).
3. Batch 2: Fix prose T2 skills (expect some to need script extraction).
4. For skills still failing after fixes → apply Reclassification
   Protocol. Move to T3 or T4 if cognitive demand was underestimated.
5. Re-score after each batch. Push.

**Effort:** ~4-6 hours across 2-3 sessions.

**Deliverable:** 26/26 T2 skills qualified or reclassified.

### Phase F — T3 Targeted Improvements

**Goal:** Qualify T3 skills against the relaxed threshold (Q≥50, O≥50, B≥75).

**Strategy:** T3 skills have legitimate prose complexity. Focus on:
- Build dimension (≥75) — ensure scripts exist and are structured.
- Observable baseline — add trace/CNL/anti-fab where missing.
- Quality — accept scores in Re-engineer band (≥50).

**Steps:**
1. Score all T3 skills (done in Phase C).
2. For each T3 skill below threshold:
   a. Check Build first — does it have bones (scripts)?
   b. If Build fails, add scripts for the mechanical steps.
   c. If Quality < 50 (Redesign), identify the 1-2 worst dimensions
      and fix those. Don't try to fix everything.
   d. If still failing after fixes → apply Reclassification Protocol.
      Move to T4 if the skill genuinely requires frontier reasoning.
3. Re-score. Push.

**Effort:** ~2-3 hours.

**Deliverable:** 14/14 T3 skills qualified or reclassified.

### Phase G — T4 Build Verification

**Goal:** Ensure all T4 skills have Build ≥75 Tunable.

**Strategy:** T4 skills are frontier-only by design. Only the Build
dimension (bones, muscle, brain, harness) is gated. Quality and
Observable are scored for informational purposes.

**Steps:**
1. Score all T4 skills (done in Phase C).
2. Run `hey eval skill <name>` for BMBT on each T4 skill.
3. Fix any Build failures (missing scripts, missing harness).
4. Quality + Observable scores go into scores.yaml as informational
   but do not affect qoo-qualified.

**Effort:** ~1 hour.

**Deliverable:** 5/5 T4 skills build-qualified.

### Phase H — Portfolio Completion

**Goal:** Final audit, documentation, and portfolio report.

**Steps:**
1. Run `qoo-report.sh` for final portfolio snapshot.
2. Update this plan with final status on every skill.
3. Document any skills that remain unqualified with reasons
   (e.g., stub skill, deprecated, structural limitation).
4. Update `~/.agents/knowledge/agentfs-engineering-evolution/index.md`
   with this document.
5. Update `context-eng/.agents/memories/MEMORY.md` breadcrumb.
6. Commit and push both repos.

**Effort:** ~30 minutes.

**Deliverable:** Portfolio report, all skills classified and scored,
qualification status documented.

## Reclassification Protocol

When a skill fails qualification at its current tier after
re-engineering fixes have been applied, use this protocol:

1. **Confirm the failure is structural, not fixable.** The skill
   must have already gone through the fix patterns for its tier.
   Reclassification is not an escape hatch for skipping fixes.

2. **Assess cognitive demand.** Re-evaluate the four classification
   axes (cognitive load, generative demand, domain expertise, script
   coverage). If the skill genuinely demands a higher model class
   than its current tier, reclassification is correct.

3. **Reclassify.** Update `model-tier` in SKILL.md frontmatter to
   the next tier. Update the classification table in this plan.

4. **Re-score.** Run QOO evaluation against the new tier's thresholds.

5. **Document.** Add a note in the skill's scores.yaml:
   ```yaml
   reclassified_from: T2
   reclassification_reason: "Deep networking domain expertise + 10 conditional branches require T3 judgment"
   ```

**Reclassification direction:** Only upward (T1→T2, T2→T3, T3→T4).
Downward reclassification means the skill was over-engineered —
simplify it instead.

**Exempt classification (`model-tier: n/a`):** Reserved for skills
that are not workflow skills — stubs, config pointers, utility
fragments — or upstream copies that must not be modified for QOO
compliance. Must have documented justification. Target: ≤5 across
the entire portfolio.

**Current exemptions (3):**
1. **hermes-headroom-provider** — 23-line stub, not a workflow skill
2. **skill-index** — delegator/utility, not a workflow skill
3. **agentfs-archify** — upstream copy (tt-a1i/Archify, MIT licensed)

## Dependency Graph

```
Phase A (tier classification)
  ↓
Phase B (infrastructure — score-all.sh, qoo-report.sh, tier-aware qualification)
  ↓
Phase C (batch baseline scoring — all 59 scored)
  ↓
  ├──► Phase D (T1 quick wins — 14 skills)
  ├──► Phase E (T2 systematic — 26 skills)
  ├──► Phase F (T3 targeted — 14 skills)
  └──► Phase G (T4 build only — 5 skills)
       ↓
     Phase H (portfolio completion — audit + documentation)
```

Phases D-G are independent and can be done in any order.
Phase C must complete before D-G start (need baselines).
Phase A and B can be done in parallel.

## Estimated Total Effort

| Phase | Effort | Skills Affected | Expected Qualified |
|:-----:|:------:|:---------------:|:------------------:|
| A | 30 min | 59 (metadata only) | — |
| B | 2-3 hours | infrastructure | — |
| C | 30 min | 57 (scoring) | ~5-10 pass as-is |
| D | 2-3 hours | 14 T1 | 14 (qualified or reclassified, ≤2 n/a) |
| E | 4-6 hours | 26 T2 | 26 (qualified or reclassified) |
| F | 2-3 hours | 14 T3 | 14 (qualified or reclassified) |
| G | 1 hour | 5 T4 | 5 (build-qualified) |
| H | 30 min | documentation | — |
| **Total** | **~13-17 hours** | **59 skills** | **≥56/59 (95%)** |

Across 4-6 sessions. Not a sprint — a sustainable pace.
≤3 skills may be exempt as `model-tier: n/a` (stubs/utilities).

## Success Criteria

| Criterion | Target |
|-----------|--------|
| All skills have `model-tier` in frontmatter | 59/59 |
| All skills have `scores.yaml` | 59/59 |
| T1 qualification rate | 100% (14/14 qualified + reclassified, ≤2 exempt as n/a) |
| T2 qualification rate | 100% (26/26 qualified + reclassified) |
| T3 qualification rate | 100% (14/14 qualified + reclassified) |
| T4 build-qualification rate | 100% (5/5) |
| Portfolio-wide qualification | ≥95% (≥56/59, ≤3 exempt as n/a) |
| Portfolio report script exists | `qoo-report.sh` working |
| Batch scoring script exists | `score-all.sh` working |

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|:----------:|:------:|------------|
| SDM variance inflates/deflates scores | High | Medium | Multi-run averaging or confidence gating |
| Stub skills too minimal for workflow evaluation | Medium | Low | Expand to proper skill or exempt as `model-tier: n/a` (≤3 total) |
| Script extraction for prose-only skills is more work than estimated | Medium | Medium | Reclassify tier upward if cognitive demand was underestimated |
| `score-all.sh` SDM endpoint saturation | Low | Medium | Add rate limiting (sleep between skills) |
| Tier misclassification | Medium | Low | Expected and handled — Reclassification Protocol formalizes upward reclassification after fix attempts |

## How to Resume

1. Read this file first for full context and current status.
2. Check Phase status above — each skill row has a status marker.
3. Key files:
   - This plan: `~/.agents/knowledge/agentfs-engineering-evolution/skill-qoo-qualification-plan.md`
   - Previous implementation plan: `~/.agents/knowledge/agentfs-engineering-evolution/implementation-plan.md`
   - Scoring scripts: `~/.agents/scripts/{score-all,qoo-report,gather-skill-state,sdm-evaluate}.sh`
   - QOO schemas: `~/.agents/skills/schemas/{quality,observable,operable}.yaml`
4. To check current state: `qoo-report.sh` (once built in Phase B).
5. To score a single skill: `hey score skill <name>` or `hey assess skill <name>`.
6. SDM endpoint: `http://localhost:9000/v1/decisions` (NextToken API).
