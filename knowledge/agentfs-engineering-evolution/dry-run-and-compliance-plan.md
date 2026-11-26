---
type: Convention
title: Dry-Run Pattern Adoption & AgentFS Compliance Profile
parent: agentfs-engineering-evolution
created: 2026-11-09
updated: 2026-11-16
tags: [dry-run, cqs, compliance, benchmark, agentfs, action-plan]
---

# Dry-Run Pattern Adoption & AgentFS Compliance Profile

- **Type:** Action Plan
- **Status:** STABLE PAUSE — Obj 1 Phases 1+2+3A+3B(partial) complete, Obj 2 B.1 was NOT built (status corrected 2026-11-16) — now complete. 30/66 Command scripts have --dry-run (45%). Remaining 36 are low-priority (internal tooling or rarely agent-invoked). Resume on-demand when individual scripts are next touched.
- **Update 2026-11-16:** Phase D.2 triggered by Rule 7 fail-closed change. B.1 delivered as `t_r7dry`; Corp tier baselines recorded (T4 100%, T3 76%, T2 60% — below ≥90% target). See benchmark-results.md v5 and Follow-ups below.
- **Update 2026-11-17:** D.2 staleness works end to end (7.12.0/7.12.1 rule changes flagged every tier STALE). Uniform parallel campaign at rules 7.12.1: T4 claude-sonnet-5.5 100%, T3 glm-5-3 96%, T2 Qwen3.8-27B-FP8 87% (below ≥90%: R2 25%). Gate now tracks harness_sha + writer_sha + hooks_sha. Next: JIT-Reminder R2 hook (F1). See benchmark-results.md "v7.12.1 Campaign".
- **Update 2026-11-17 (7.13.0):** R4 step 2 wording ("the request itself is not approval. Then stop…") + preflight-reminder hook. Campaign 20261117_180330: T4/T3/T2 all 100% on every scored rule, gate CONVERGED. Scores are system compliance (AGENTS.md + hooks), graded by effect. Ceiling reached: harder tests needed for tier discrimination. Open follow-ups: none for R7 (F9 declined: 27/27 without a hook). F10 cleanup leak fixed (WAL lock contention). Final parallel re-record 20261117_210655 (11m42s): T4 100 / T3 100 / T2 98, all CONVERGED (F11–F13).
- **Depends on:** QOO qualification (complete), benchmark harness v2 (active)
- **Risk constraint:** No degradation of current AGENTS.md compliance
  profile (Frontier 100%, Qwen3-14B 93%)

---

## Objective 1: Dry-Run Pattern Adoption

### Problem Statement

AgentFS skill scripts follow CQS (Command-Query Separation)
implicitly but not formally. Of 66 Command scripts (state-mutating),
only 9 have `--check` mode — an inconsistent half-step toward
dry-run. The `--check` pattern has three deficiencies:

1. **No structured output signal.** The agent must parse English
   prose to decide whether to proceed.
2. **Exit code ambiguity.** Some scripts exit with error count,
   which `set -e` and CI pipelines treat as failure.
3. **Inconsistent naming.** `--check` in some, nothing in most.

### Design: The `--dry-run` Contract

Every Command script MUST support `--dry-run` following this contract:

#### Output Signals

| Mode | Output Line | Meaning |
|------|------------|---------|
| `--dry-run` | `DRY_RUN_RESULT=CONVERGED` | System already in desired state |
| `--dry-run` | `DRY_RUN_RESULT=PENDING` | N change(s) would be applied |
| Apply (no flag) | `APPLY_RESULT=OK` | All steps succeeded |
| Apply (no flag) | `APPLY_RESULT=PARTIAL` | Some steps failed |

#### Exit Codes

| Exit Code | Meaning |
|:---------:|---------|
| **0** | Script completed successfully (both `--dry-run` and apply) |
| **1** | Actual error — precondition failed, cannot proceed |

`--dry-run` ALWAYS exits 0 on success — `DRY_RUN_RESULT=PENDING` is
not an error. This is safe for `set -euo pipefail`, CI pipelines,
and agent consumers that treat non-zero as failure.

#### Per-Step Output Format

```
[dry-run] Step 1: WOULD CREATE /path/to/file
[dry-run] Step 2: NO CHANGE — already exists
[dry-run] Step 3: WOULD UPDATE config.yaml (provider entry missing)
```

#### Implementation Pattern

```bash
DRY_RUN=false
CHANGES=0

for arg in "$@"; do
  case "$arg" in --dry-run) DRY_RUN=true ;; esac
done

apply() {
  local description="$1"; shift
  if $DRY_RUN; then
    echo "[dry-run] WOULD: $description"
    CHANGES=$((CHANGES + 1))
  else
    "$@"
    echo "✓ $description"
  fi
}

# Summary
if $DRY_RUN; then
  [[ $CHANGES -eq 0 ]] && echo "DRY_RUN_RESULT=CONVERGED" \
                        || echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi
```

#### Query Scripts

Query scripts (read-only: `check-status.sh`, `audit.sh`, `list.sh`,
`scan.sh`, `verify.sh`, `probe-*.sh`, `detect-*.sh`, `test-*.sh`)
do NOT need `--dry-run`. They are inherently side-effect-free.

### Scope

| Category | Count | Action |
|----------|:-----:|--------|
| Command scripts needing `--dry-run` | 57 | Retrofit |
| Command scripts with `--check` | 9 | Migrate `--check` → `--dry-run` + output signals |
| Query scripts | 73 | No change |
| **Total scripts** | **139** | |

### AGENTS.md Prose Glue — Rule 7: Dry-Run Gate

A new rule is added to AGENTS.md so the agent knows how to use
`--dry-run`. This rule must NOT increase cognitive demand beyond
what Qwen3-14B already handles (T2 compliance).

#### Proposed Rule Text

```markdown
### 7. Dry-Run Gate

**When:** A skill step runs a Command script (creates, modifies,
or deletes files, services, or configuration).

**Do:**
1. If the script supports `--dry-run`, run it with `--dry-run` first.
2. Parse stdout for the result:
   - `DRY_RUN_RESULT=CONVERGED` → report "already configured", skip apply.
   - `DRY_RUN_RESULT=PENDING` → proceed to apply (run without `--dry-run`).
3. Exit code 0 from `--dry-run` means the dry-run succeeded,
   NOT that no changes are needed. Read the output signal.
4. Do NOT treat `DRY_RUN_RESULT=PENDING` as a failure.
```

#### Compliance Risk Assessment

| Dimension | Risk | Rationale |
|-----------|:----:|-----------|
| Token budget | Low | ~80 tokens. Current AGENTS.md is ~1,909 tokens, well under context limits |
| Conditional depth | Low | Single-level if/else on stdout string — simpler than Signal Dispatch |
| T2 compatibility | Low | String match on `grep`-able output — Qwen3-14B handles this at 100% (same pattern as existing rules) |
| Regression risk | Low | Rule is additive — no existing rule is modified |

#### Verification Gate

After adding Rule 7, re-run the benchmark harness v2:
- Frontier must remain 100%
- Qwen3-14B must remain ≥90% (current: 93%)
- Add new test T10: dry-run interpretation (run a `--dry-run` skill,
  verify agent reads `DRY_RUN_RESULT` and acts correctly)

### Phases

#### Phase 1 — Foundation (AGENTS.md + convention doc)

| Step | Action | Deliverable |
|:----:|--------|-------------|
| 1.1 | Add Rule 7 (Dry-Run Gate) to AGENTS.md template | `seed-agents-md.sh` updated |
| 1.2 | Sync AGENTS.md to all projects | `sync-agents-md.sh` run |
| 1.3 | Benchmark: frontier validation (must pass 100%) | Benchmark log |
| 1.4 | Benchmark: Qwen3-14B validation (must pass ≥90%) | Benchmark log |
| 1.5 | If benchmark regresses → revert Rule 7, diagnose | Rollback + analysis |

**Gate:** Phase 2 does not start until Phase 1 benchmarks pass.

#### Phase 2 — Migrate existing `--check` scripts (9 scripts)

| Step | Action | Deliverable |
|:----:|--------|-------------|
| 2.1 | Rename `--check` → `--dry-run` in all 9 scripts | Scripts updated |
| 2.2 | Add `apply()` helper + structured output signals | Output contract met |
| 2.3 | Standardize exit codes (0 for success, 1 for error) | No `exit $ERRORS` |
| 2.4 | Update SKILL.md CNL steps (`--check` → `--dry-run`) | Skills updated |
| 2.5 | Run `--dry-run` on each migrated script to verify | All exit 0 |
| 2.6 | Rescore affected skills (QOO scores may change) | `scores.yaml` updated |

**Backward compatibility:** Add `--check` as deprecated alias for
`--dry-run` in each script for one release cycle:

```bash
--check) echo "WARN: --check is deprecated, use --dry-run" >&2; DRY_RUN=true ;;
```

Scripts to migrate:

| # | Script | Skill |
|:-:|--------|-------|
| 1 | `setup.sh` | goose-headroom-provider |
| 2 | `setup.sh` | goose-desktop-env-fix |
| 3 | `setup.sh` | hermes-desktop-fixes |
| 4 | `install.sh` | crc-cmd |
| 5 | `audit.sh` | agentfs-ctx-chk |
| 6 | `diagnose.sh` | fedora-nm-boot-slow |
| 7 | `setup.sh` | crc-ovn-frr-metallb-config |
| 8 | `setup.sh` | crc-aap-demo-config |
| 9 | `validate-and-install.sh` | bash-completion-gen |

#### Phase 3 — Retrofit remaining Command scripts (57 scripts)

Batch by priority tier:

| Batch | Criteria | Script Count | Priority |
|:-----:|----------|:------------:|:--------:|
| 3A | T1/T2 skills (highest model reach) | ~8 | High |
| 3B | T3 skills with existing `scripts/` | ~35 | Medium |
| 3C | T4 skills + complex multi-script | ~14 | Low |

Per-script retrofit:
1. Identify all mutation points (file writes, service changes, API calls)
2. Wrap each in `apply()` helper
3. Add `DRY_RUN` flag parsing
4. Add summary output block with `DRY_RUN_RESULT` / `APPLY_RESULT`
5. Test `--dry-run` exits 0
6. Test apply mode still works

#### Phase 4 — SKILL.md CNL Alignment

Update all skill SKILL.md files that reference `--check` to use the
two-step `--dry-run` → apply workflow pattern:

```markdown
### Step 1 — Pre-flight
The agent MUST run:
bash scripts/setup.sh --dry-run

Parse the output:
- `DRY_RUN_RESULT=CONVERGED` → report "already configured" and stop.
- `DRY_RUN_RESULT=PENDING` → proceed to Step 2.

### Step 2 — Apply
The agent MUST run:
bash scripts/setup.sh
```

#### Phase 5 — Portfolio Verification

| Step | Action |
|:----:|--------|
| 5.1 | Run `score-all.sh` to rescore affected skills |
| 5.2 | Fix SDM Build false negatives (manual corrections) |
| 5.3 | Verify 100% qualification rate maintained |
| 5.4 | Final benchmark run (frontier + 14B) |
| 5.5 | Update this plan status → COMPLETE |

### Effort Estimate

| Phase | Scripts | Estimated Effort |
|:-----:|:-------:|:----------------:|
| 1 | 0 (AGENTS.md only) | 1 session |
| 2 | 9 | 1 session |
| 3 | 57 | 4-6 sessions |
| 4 | ~30 SKILL.md files | 1-2 sessions |
| 5 | 0 (verification) | 1 session |
| **Total** | **66 scripts + 30 skills** | **8-11 sessions** |

---

## Objective 2: AgentFS Compliance Profile

### Problem Statement

AGENTS.md is the most critical document in the AgentFS architecture —
every agent, every turn, every task depends on it. Yet it has no
formal qualification artifact. Skills have `scores.yaml` with QOO
scores and tier labels. AGENTS.md has benchmark results scattered
across `benchmark-results.md` with no structured metadata.

### Design: Compliance Profile

The compliance profile measures AGENTS.md operability per rule, per
model tier. Unlike skill QOO (Q/O/B scores), the compliance profile
is **empirical** — it comes from benchmark runs, not SDM evaluation.

#### Schema: `compliance-profile.yaml`

```yaml
# ~/.agents/skills/agentfs-setup/compliance-profile.yaml
schema_version: "1.0"
agents_md_version: "7.6.0"
compliance_target: "≥90%"

validated_tiers:
  T4:
    model: "claude-sonnet-4.6"
    provider: "custom_redhat"
    date: "2026-10-29"
    overall: "100%"
    per_rule:
      R1_signal_dispatch: "100%"
      R2_pre_flight: "100%"
      R3_session_canary: "100%"
      R4_conflict_resolution: "not_testable"
      R5_checkpoint: "100%"
      R6_scope_post_write: "100%"
    runs: 5
    pass: 5
    harness_version: "v7.6.0"

  T2:
    model: "Qwen3-14B-FP8"
    provider: "custom_skupper"
    date: "2026-10-29"
    overall: "93%"
    per_rule:
      R1_signal_dispatch: "100%"
      R2_pre_flight: "100%"
      R3_session_canary: "80%"
      R4_conflict_resolution: "not_testable"
      R5_checkpoint: "100%"
      R6_scope_post_write: "100%"
    runs: 30
    pass: 28
    harness_version: "v7.6.0"
    failure_modes:
      - id: FM5
        rule: R3
        rate: "20%"
        description: "Model-level attention failure on turn 1 — no canary generated"
        attributable: false
        mitigation: "Model-level. Shorter/simpler canary rule may help."
      - id: FM_chain
        rule: R1
        rate: "7%"
        description: "Dispatch succeeds but shell execution skipped on skill load"
        attributable: false
        mitigation: "Stochastic. No structural fix identified."

minimum_tier: T2
minimum_tier_rate: "93%"
```

#### Update Protocol

The compliance profile MUST be updated whenever:

1. AGENTS.md template (`seed-agents-md.sh`) is modified
2. A new rule is added or an existing rule is changed
3. A new model tier is benchmarked for the first time

Update procedure:
1. Run benchmark harness v2 against frontier model (validation)
2. Run benchmark harness v2 against target model (5+ runs)
3. Update `compliance-profile.yaml` with results
4. If overall rate drops below target → revert the change, diagnose

#### Relationship to Skill QOO

| Aspect | Skill QOO (`scores.yaml`) | AGENTS.md Compliance (`compliance-profile.yaml`) |
|--------|:-------------------------:|:------------------------------------------------:|
| What's measured | Skill prose quality + structure | Rule compliance rate per model |
| How measured | SDM evaluation (automated) | Benchmark harness (empirical) |
| Scoring dimensions | Q (quality), O (observable), B (build) | Per-rule pass rate |
| Tier meaning | "Can model X execute this skill?" | "Can model X follow these rules?" |
| Update trigger | Skill SKILL.md change | AGENTS.md template change |
| Location | Per-skill `scores.yaml` | Single `compliance-profile.yaml` in agentfs-setup |

### Phases

#### Phase A — Baseline Profile

| Step | Action | Deliverable |
|:----:|--------|-------------|
| A.1 | Create `compliance-profile.yaml` schema | Schema file |
| A.2 | Populate with existing benchmark data (v7.6.0 results) | Baseline profile |
| A.3 | Add to agentfs-setup skill directory | File committed |
| A.4 | Register in knowledge index | Discoverable via KGM |

#### Phase B — Benchmark Harness Enhancement

| Step | Action | Deliverable |
|:----:|--------|-------------|
| B.1 | ✅ (2026-11-16) Add T10 test for `--dry-run` interpretation — delivered as `t_r7dry` in benchmark.sh | Test script |
| B.2 | Add `--output-yaml` mode to benchmark.sh | Machine-readable output |
| B.3 | ✅ Create `update-compliance.sh` that runs harness → updates YAML (2026-11-16: fixed — it previously wrote no tier data) | Automation script |
| B.4 | Document minimum run count per tier (≥5 for stochastic models) | Convention doc |

#### ~~Phase C — T1 Benchmark~~ (REMOVED)

T1 compliance is not a goal for AGENTS.md. The rules inherently
require T2+ cognitive ability (conditional dispatch, cross-turn state,
multi-step reasoning). Benchmarking T1 would only confirm what is
architecturally known.

#### Phase D (renumbered from C) — Continuous Compliance

| Step | Action | Deliverable |
|:----:|--------|-------------|
| D.1 | Add compliance check to agentfs-setup sync workflow | Pre-sync gate |
| D.2 | When `seed-agents-md.sh` changes → flag "compliance profile stale" | Warning in log.md — ✅ working (2026-11-17); `update-compliance.sh --dry-run` also PENDING on harness/writer/hooks change |
| D.3 | Document in agentfs-setup SKILL.md: "re-benchmark after template changes" | Convention |

### Effort Estimate

| Phase | Estimated Effort |
|:-----:|:----------------:|
| A (baseline) | 0.5 sessions |
| B (harness) | 1-2 sessions |
| C (T1 benchmark) | 1 session |
| D (continuous) | 1 session |
| **Total** | **3-5 sessions** |

---

## Combined Timeline

| Session | Objective 1 (Dry-Run) | Objective 2 (Compliance) |
|:-------:|:---------------------:|:------------------------:|
| 1 | Phase 1 — AGENTS.md Rule 7 | Phase A — Baseline profile |
| 2 | Phase 1 — Benchmark validation | Phase B.1 — T10 test |
| 3 | Phase 2 — Migrate 9 `--check` scripts | — |
| 4-6 | Phase 3A — T1/T2 Command retrofits | — |
| 7-8 | Phase 3B — T3 Command retrofits | Phase C — T1 benchmark |
| 9-10 | Phase 3C — T4 + Phase 4 CNL alignment | Phase B.2-B.3 — Harness automation |
| 11 | Phase 5 — Portfolio verification | Phase D — Continuous compliance |

**Total estimated effort: 11-16 sessions**

---

## Success Criteria

| Criterion | Target | Measured By |
|-----------|--------|-------------|
| All Command scripts have `--dry-run` | 66/66 | `grep --dry-run` across portfolio |
| AGENTS.md Rule 7 passes frontier | 100% | Benchmark T10 |
| AGENTS.md Rule 7 passes Qwen3-14B | ≥90% | Benchmark T10 |
| Overall AGENTS.md compliance unchanged | Frontier 100%, 14B ≥93% | Full benchmark run |
| Compliance profile exists and is current | YAML matches latest benchmark | File audit |
| No QOO qualification regression | 59/59 qualified or exempt | `qoo-report.sh` |
| `--check` fully deprecated | 0 scripts using `--check` only | `grep --check` |

---

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Rule 7 degrades 14B compliance | Blocks all downstream work | Phase 1 Gate: benchmark before proceeding |
| `--check` → `--dry-run` rename breaks existing SKILL.md references | Skills reference stale flag | Phase 2.4: update all SKILL.md simultaneously |
| 57-script retrofit is too large for session budget | Partial completion | Batch by priority tier (3A/3B/3C) |
| SDM rescoring clobbers manual Build corrections | QOO regression | Re-apply corrections after each rescore (known pattern) |
| T1 model benchmark reveals AGENTS.md is T2+ only | No T1 compatibility | Acceptable — documents the real boundary |
| Deprecated `--check` alias confusion | Agent calls `--check` from memory | One release cycle, then remove |

---

## Follow-ups (2026-11-16)

| # | Item | Why |
|:-:|------|-----|
| F1 | **R2 Pre-Flight rule wording** — propose a CNL fix (e.g. explicit "creating ≥2 files counts") and re-benchmark **✅ Closed 2026-11-24 (user decision): no prose change.** v7.14.1 campaign: R2 100% at T4 (effort high) and T3, 90% at T2 (the one miss, t_r2git 3/4, pushed without confirmation — not a missing plan). The T4 failure was reasoning effort (F24), not wording. Kept on record: at low effort the plan can move into hidden thinking; "state the plan in your reply text" is the tested-first candidate if R2 regresses | Fails across all non-frontier tiers, non-monotonic with capability |
| F2 | ✅ **Resolved 2026-11-17** — T2 representative swapped to nemotron-3-nano-ga; official run 60% (screen 84%; pooled 72%). gpt-oss-20b baseline archived. **Superseded same day:** 14-model screen → T3 glm-5-3, T2 Qwen3.8-27B-FP8 (87% at 7.12.1); gemma-4-31b-it evaluated, rejected (78%) | Measures rules, not serving corruption |
| F3 | **Unify compliance pipelines** — ✅ 2026-11-18 (agentfs-eval 2.7.0): compliance-profile.yaml is the single runtime record. agentfs-eval Steps 6–7 = `update-compliance.sh --check` + `runtime-compliance.sh` (CECX runtime dims computed deterministically; SDM runtime retired — it read hand-transcribed numbers and quantized targets: ≥90%→≥80%, ≤10%→≤20%, ≤20%→≤40%). SDM kept for build dims (`--phase build`). scores.yaml operable.runtime is a pointer. Stage S0–S3 replaces Tier 0–3 / Layer 1–3 | Two records, divergent numbers |
| F4 | `goose-recipe-session-cleanup/delete.sh` leaves orphan rows in `thread_messages` / `session_tags` Found while implementing benchmark session cleanup. **✅ Fixed 2026-11-17 (goose-recipe-session-cleanup 3.2.1):** both delete paths now also delete `thread_messages` and `session_tags` (the schema's ON DELETE CASCADE never fires: `foreign_keys` is off). Tested on a copy of sessions.db: old script left 1+1 orphans, new leaves 0, only the target session removed | Done |
| F5 | Canary check accepts non-word canaries (`2953-9218`, `hello-world`); R5 Checkpoint has no test **✅ Closed 2026-11-17:** canary check now letters only (`🐦\s+\p{L}+-\p{L}+`, was `\w` which accepted `2953-9218`); no placeholder blocklist (`hello-world` is still two words). R5 stays untested by user decision. Recorded by regrading 20261117_210655 with the new check: verdicts identical on all 147 runs (all canaries were letter words), all tiers CONVERGED | Done |
| F6 | `sync-agents-md.sh` compliance staleness check runs only after a real sync — the script exits 0 at "already up to date" (lines 80/119) before the check (~line 232), so the warning fires once (on the first project synced after a template bump, which Rule 5 step 4 mandates) and is never repeated if ignored **✅ Fixed 2026-11-17 (agentfs-setup 7.13.1):** the check is now a `compliance_staleness_check` function called on all three exit paths (initial seed, already up to date, synced), so it warns on every sync while the profile is stale. Also fixed: the warning suggested sequential `update-compliance.sh --tier Tx --runs 5` (wrong run counts, ~57 min); it now suggests `run-parallel.sh real` and `--check`. Tested in a throwaway HOME: old script silent on an up-to-date project with a stale hash, new script warns (rc 0, AGENTS.md unchanged); seed path with no hash and an old version takes the version fallback (no set -u crash) | Done |
| F7 | **KGM name contract — Done (lean, 2026-11-17).** Probe finding: goose builds the MCP tool prefix from the extension's `name` field, not its config key (lowercase, strip whitespace, other chars outside `[a-z0-9_-]` → `_`; key `kgmkey` + name `Probe Name Field` → `probenamefield__search_nodes`). (1) `scripts/agentfs-contract.sh` defines `KGM_EXT_KEY`, `KGM_EXT_NAME` and derives `KGM_TOOL_PREFIX`/`KGM_SEARCH_TOOL`; sourced by both hooks, benchmark.sh, template-behavioral.sh and the 6 goose-kgm scripts; `scripts/agentfs-contract-lint.sh` forbids the literal elsewhere. (2) signal-dispatch 2.2.0: wrong-prefix `*__search_nodes` while dispatch is pending gets one block naming the fix, then clears; post-write-enforce 1.2.0 allows only the contract tool; both fail open if the contract is missing. (3) `kgm status` reports a name→prefix mismatch with the fix line. Cut: normalize, agentfs-eval/sync/SessionStart checks. Validation: V1 lint clean; V2 hook unit tests; V3 goose-kgm output unchanged; V4 mismatch reported; V5 regrade of 210655 identical (49/49 rows per tier); V6 real re-run 20261117_225629 T4 100 / T3 100 / T2 96, CONVERGED, 0 mismatch denials, 146/146 clean | A renamed KGM extension deadlocks every `hey` dispatch with no diagnostic |
| F8 | **JIT-Reminder R2 hook** — ✅ built + validated 2026-11-17: plugin `preflight-reminder` 1.0.0 (UserPromptSubmit arms per turn; PreToolUse denies the first *mutating* call — write/edit/non-read-only shell — plus the rest of its parallel batch (2 s window), with a reminder to plan then retry in the same turn; git push still waits). Rule text unchanged. R2 validation (12 runs each): Qwen 3/12 → 12/12, gemma 0/12 → 11/12, all edits completed. benchmark.sh grades the effect (hook-denied blocks dropped, verdict tagged `hook-assisted`). Recorded in the 7.13.0 campaign (all tiers 100%, CONVERGED) | R2 was the only rule below target at T2 |
| F9 | **R7 guard hook (proposed, not approved)** — PreToolUse deny on a Command-script apply with no prior `--dry-run` in the session, unless the prompt contains `[OVERRIDE]`. Targets gemma-class t_r4s failures (skip the dry-run on request). **Decision 2026-11-17: not building.** R7 is 27/27 without a hook (run 20261117_210655), gemma was rejected, and the hook would be fragile (deciding which scripts are Command scripts and support `--dry-run`), would make R4 `t_r4s` measure the hook instead of the model, and adds global per-session state. Revisit only if an accepted tier fails an R7 test, a candidate model shows the gemma pattern, or a safety net for the live environment is wanted | Declined (revisit on trigger) |
| F10 | **Session cleanup leak** — ✅ fixed 2026-11-17. Root cause: sessions.db is WAL with busy_timeout=0; T4's cleanup DELETE hit `database is locked` (T3/T2/gemma still writing), stderr was discarded and the session was counted as removed (not a rename issue — cleanup already diffs IDs). Fix in benchmark.sh: `.timeout 15000`, BEGIN IMMEDIATE, verify-after-delete, 3 retries, FAILED ids logged. Reproduced + unit-tested on a scratch DB | Done |
| F11 | **Sharded parallel campaign** — ✅ 2026-11-17: `benchmark.sh --queue` + `~/.agents/scripts/run-parallel.sh` (per-tier longest-first queue, per-worker project/sandbox/scratch, merge + completeness check + regrade + replay). 49 runs/tier in 12m48s (was 57 min), T4 100 / T3 98 / T2 100, CONVERGED. Provider rate limits cap useful workers (T2×4) | Target < 20 min met |
| F12 | **Test containment** — ✅ 2026-11-17: gemma staged the real `~/.agents` (`git add -A`, 4 runs) via the git-push skill default. Fix: agentfs-git-push 2.2.0 `AGENTFS_GIT_DEFAULT_TARGET` → sandbox, `pushInsteadOf` dead-URL for all network pushes, per-run real-repo index guard (`EVIDENCE real_repo`). t_ii provider-error retry added | Done |
| F13 | **Hook state leaks across reused goose session IDs** — ✅ 2026-11-17: goose session IDs (`YYYYMMDD_N`) are reused after deletions or a UTC-midnight reset, so per-session `/tmp` flag files leaked into later sessions. T4 t_r1 run2 (20261117_204553) was falsely blocked by a stale post-write-enforce flag. Fix: SessionStart (new sessions only, not `--resume`) clears this session's state in post-write-enforce 1.1.0, signal-dispatch 2.1.0 and preflight-reminder 1.1.0; detect-hey also resets on each hey prompt. Re-record 20261117_210655: 0 post-write-enforce denials in 161 run logs. | Done |
| F14 | **Stale rule numbers after the 7.x renumbering** — ✅ 2026-11-17: `post-write-enforce/plugin.json` said "Rule 3 (Post-Write)" (now Rule 6, description only, never shown to models) → 1.1.1; `test-agents-md-fidelity.sh` failed 9/70 (old rule numbers/names, 4 reworded behavioural phrases) → 70/70, negative test still fails on a renamed rule. Profile re-recorded by regrading 20261117_210655 (verdicts identical), all tiers CONVERGED. A repo-wide search found no other stale rule numbers | Done |
| F15 | **Dropped by user 2026-11-17:** preflight-reminder false blocks on read-only compound commands (`cd …; grep`, `VAR=$(find …)`, `sqlite3 SELECT`; costs one retry); seed-agents-md.sh logging "Created AGENTS.md" on sync; T2 t1 run3 no-canary transcript in 20261117_204553 (not reproduced in 210655) | Dropped |
| F16 | **Semantic change control** — ✅ 2026-11-18 (agentfs-setup 7.13.2): no hash/SHA staleness trigger. `update-compliance.sh --check` lists rules-template commits since the records; agent classifies none/smoke/partial/full, user confirms. Dry-run converges on model/provider/tests; `--remeasure` = explicit decision (run-parallel passes it). First use: 7.14.0 Tier→mode/Index Browse rename, class *wording*, smoke 20261118_144907 matched (T4/T3/T2 100%) | 15-min re-record on any rule edit |
| F17 | **Script Stage S3 Semantic** — ✅ closed lean 2026-11-18 (agentfs-eval 2.8.0): `vote_count` 3→1 in memory-classification + sycophancy-detection (in-session votes are correlated, repeats bought no independence); limitation documented in SKILL.md Anti-Bias Design. Independent stateless grading deferred until an SDM-class endpoint exists. Was: — rubric votes (`vote_count: 3`) are taken by the session agent in one context, so they are correlated and self-graded (~560 judgments here). Move to independent stateless calls (sdm-evaluate pattern); parallel by default | Closed |
| F18 | **skill-eval 'Tier 0' wording** — ✅ 2026-11-18 (skill-eval 2.6.0): Static Checks / Build QOO / Runtime CECX; Tier reserved for model T1–T4. Was: — same Tier overload as agentfs-eval (Tier = model T1–T4 only); rename to Stage | Closed |
| F19 | **T2 R4 below 80%** — ✅ closed 2026-11-18: noise. Re-measure t_r4s ×5 (scratch profile, compliance-T2-20261118_154444) = 5/5; pooled R4 = t_r4x 3/3 + t_ii 3/3 + t_r4s 6/8 = 12/14 (86%). No R4 rewording. Real profile entry unchanged (77%) until the next T2 re-record. Found: `update-compliance.sh --tests` REPLACES the whole tier entry — `--check` partial hint and agentfs-eval Step 6 now say run-parallel --tiers / scratch only. Was: — runtime-compliance.sh: Qwen3.8-27B-FP8 R4_conflict_resolution 77% (t_r4s 1/3) while T2 overall 96% and minimum_tier=T2. per_rule_comprehension fails | Closed |
| F20 | **Benchmark host safety after the 2026-11-18 home wipe** — Decision 2026-11-23: option (a) — keep running benchmarks on the host, protected by the goose rm guard (goose-desktop-env-fix 1.8.0, blocks `rm` of `/`, `$HOME` and key dirs after expansion) plus daily Deja Dup backup of `~/.agents` and `~/app`. Container isolation not adopted. Fixtures never contain live destructive commands. Commit and push `~/.agents` before each campaign | Root cause of the wipe: principles-lab `risk_1` fixture with live `rm -rf $BUILD_DIR/*`, run by T2 Qwen3.8 via unisolated `goose run` |
| F21 | **Principle evaluation joins agentfs-eval** — Decision 2026-11-23: SOUL principle evaluation and update become part of agentfs-eval (not a separate `principle-eval` skill), sharing tiers T1–T4, compliance profile and semantic change control with Rules. Rebuild from `~/app/playground/incident-2026-11-18-fedora-home-wipe/recovered/opus-session-summary.md` (harness design, gates G1–G3, 15 tests, T4/T3 baselines). Next: T2 baseline s0-current vs s1-control. Open — design not started | principles-lab (standalone, in context-eng) was lost in the wipe before graduation |
| F22 | **Evaluation split by phase for the base skill (revised 2026-11-24; was "Retire QOO for policy artifacts", 2026-11-23)** — Canonical: [evaluation-methodology.md](./evaluation-methodology.md) §3–§5. AGENTS.md + SOUL.md + `~/.agents/scripts` = the base skill produced by the meta-skill agentfs-setup. **Static QOO stays** (Quality + Operable-build; Observable N/A), owned by agentfs-setup, record `artifacts/agents-md/scores.yaml`, re-scoped: remove `accidental_complexity` (contradicted C3, broken); adherence-predicting prose dims → deterministic S0 lint (single concrete `When:`, no cross-rule refs in `Do:`, one imperative action per step, literal tool syntax); optional semantic checks for overlap/ambiguity. **Operable-runtime = compliance campaign** (no observability → no async trace path; needs ground truth + tier coverage): derived on demand from `compliance-profile.yaml` by `runtime-compliance.sh`; `scores.yaml` keeps only a stateless reference (the stateful pointer showed pass:false for 6 days after the profile computed PASS). Profile schema v2 (per-item anatomy; failure modes trigger_miss / body_error / over_apply, labels later = option b) unchanged. **Why revised:** the 11-23 decision judged QOO by whether it raised compliance — the wrong yardstick (QOO answers "well built?", compliance answers "followed?"). Scope: skill-eval's QOO for ordinary skills is unchanged. Nothing is deleted. Implementation (R-a): re-scope both schemas (runtime section → derived; thresholds read by runtime-compliance.sh), move agentfs-eval Step 8 (SDM build scoring) into agentfs-setup's upgrade flow, agentfs-eval reports both records and writes only the profile, add a staleness check for the static sheet. **R-a done 2026-11-24:** schemas v1.1 (accidental_complexity → item_overlap; runtime derived-only, threshold field); runtime-compliance.sh reads targets from the schema; SDM build scoring moved to agentfs-setup upgrade; agentfs-eval persists nothing but campaigns; scores.yaml runtime = stateless reference; static-sheet-status.sh (+ `--check` line); legacy template-scores.md / merge-score-entry.sh archived. Static scores stay stale until SDM returns. **R-b done 2026-11-24:** template-check.sh A11–A14 (A11 FAIL; A12–A14 WARN because v7.14.1's true hits sit on rules measured 100% at T4–T2 — lint, not a verdict; `A1x_LEVEL=FAIL` promotes). Baseline 90/100. **R-c done 2026-11-24** (see F23). **R-g done 2026-11-24:** fresh-session `hey eval agentfs` PASS (session 20261124_20, T4 claude-sonnet-5-5, no writes); findings fixed: preflight-reminder 1.6.0 (read-only eval scripts no longer held), agentfs-eval 2.12.1 (Steps 2–8 may run in parallel, report in order), rubric guardrail_ref updated. Rules phase complete; next = Principles (F26). Closed | Session 2026-11-23/24 QOO review |
| F23 | **agentfs-eval modes + campaign time budget** — Decision 2026-11-23. Split into `template` mode (S0 lint + compliance campaign → compliance profile, the only persisted verdict, per template version) and `workspace` mode (S1/S2/S3 + maturity → report only, no model calls). Budget: workspace ≤ 2 min, partial campaign ≤ 10 min, full campaign (Rules + Principles, T2–T4) ≤ 30 min; excluded units always reported. Levers: per-item change control (re-run only changed rules/principles), one queue per model across Rules + Principles with 429-adaptive concurrency (replaces fixed shards + linear 30/60/90 s backoff), early stop when a test can no longer reach the target, cheap gates first (S0 → smoke → real). Baseline: Rules campaign 11m42s–15m48s, T2 22–24 rate-limit retries, T4 0 (2026-11-17). Capacity probe 2026-11-23 (direct API, ~2.4k-token prompt, 24 req per phase, 90 s cool-downs): throttling is **per model** — Qwen3.8-27B-FP8 0/24 throttled alone (conc 8 and 4) and 0/24 while glm-5-3 was loaded at the same time; glm-5-3 3/24 alone at conc 8, 8/24 under co-load (small n, cannot exclude partial shared admission for glm). Qwen did throttle 20/24 when 48 requests landed within ~30 s → a rate window, not a concurrency cap (inference). No rate-limit headers; 429 body: `rate_limit_exceeded`, `subscription: personal`, "paced by broker admission (mirrors self-hosted MaaS)". Implications: Rules + Principles for one model share its budget (serialize per model, parallelize across models); concurrency must adapt on 429 (no headers to read). **Blocker: T4 claude-sonnet-5.5 returns 403 `model_not_entitled` on the current (post-wipe, personal) corp key** — also claude-sonnet-4.6, claude-haiku-5.5, gemini-3.1-pro-preview; glm-5-3 and Qwen3.8-27B-FP8 OK. T4 cannot be re-recorded on custom_corp until entitlement changes or the T4 representative moves provider. **Blocker resolved 2026-11-23:** T4 representative moved to gcp_vertex_ai claude-sonnet-5-5 (effort high, F24). **R-c done 2026-11-24:** agentfs-eval 2.12.0 modes (`eval agentfs workspace` report-only S1–S3 + maturity; `eval agentfs template` S0 + compliance + static status; `eval agentfs` full, unchanged); `run-parallel.sh` reports wall time vs budget (smoke 7 / real 20 / subset 10 min, report only) and excluded provider-error units. Scheduler levers (per-model queue across Rules + Principles, 429-adaptive concurrency, early stop, per-item re-run) moved to the shared Principles design (methodology §13). Open — scheduler | Session 2026-11-23 |
| F24 | **goose 1.60.2 harness drift + T4 R2 false passes** — 2026-11-23. After the post-wipe goose reinstall (1.60.2): (1) `--with-builtin skills` failed (skills is a platform extension, always loaded) and its warning became the first transcript line (t1/t_r3c false FAIL); (2) session cleanup aborted (`thread_messages` gone; 45 leaked sessions deleted); (3) tool OUTPUT printed flush-left was graded as assistant prose. Fixed in benchmark.sh: no `skills` builtin, discovered session_id tables, `GOOSE_CLI_MIN_PRIORITY=0.5` (transcript = what the user sees; aligns with principle "Show, don't reference"). Effect of (3): t1 false FAILs gone; t_r1 / t_r7dry_conv now require the model to report (script output no longer counts); **R2 t_r2/t_r2b for T4 were false PASSes** — on regrade the denied first call is skipped and the preflight-reminder denial text ("write the plan…") preceded the retry and satisfied r2_plan_in. Real campaign 20261123_224314 (v7.14.1, 13m15s, 0 leaked): T4 gcp_vertex_ai claude-sonnet-5-5 88% (R2 33%: t_r2 0/4, t_r2b 0/4 — retried the denied call with zero prose in 8/8 runs), T3 glm-5-3 100%, T2 Qwen3.8-27B-FP8 98% (R2 90%: t_r2git 3/4 pushed without confirmation; R4 100%, clears F19). Whether the 11-17 T4 R2 100% was inflated the same way is unverifiable (evidence lost). **Root cause of the T4 R2 failure (2026-11-23, confirmed): reasoning effort, not prose or provider.** Same model via custom_redhat (LiteLLM) passed t_r2+t_r2b 8/8. Both routes reach the same Vertex endpoint (`vertex_ai/claude-sonnet-5-5`, same project). goose's native gcp_vertex_ai provider sends `thinking: {type: adaptive}` + `output_config.effort` taken from `GOOSE_THINKING_EFFORT: medium` in `~/.config/goose/config.yaml`. The LiteLLM route sends neither (goose OpenAI engine omits them; LiteLLM `drop_params: true`), so the server default applies. Isolation on gcp, t_r2+t_r2b × 4: effort **medium 0/8**, effort **high 8/8**; `GOOSE_THINKING_EFFORT=none` maps to `off`, which still sends adaptive thinking + effort high (2/2 PASS). Mechanism (llm_request logs): at medium the model treats the 2-file task as trivial, emits no thinking and no plan, and bundles the change into its first tool call. After the hook denial it writes the plan **inside the hidden thinking block** ("I'll create the scratch directory with two empty test files…") and retries with zero visible text. The plan exists but the user never sees it. At high it reasons "touches ≥2 files → state a brief plan" and writes it as visible text. Inference (unverified): the server default when effort is omitted behaves like high. **Implications:** (a) campaign results depend on an unpinned user goose setting, so pin effort in benchmark.sh (like `GOOSE_CLI_MIN_PRIORITY`) and record provider+effort per representative in the profile; (b) the 20261123_224314 T4 score measured effort medium and is not comparable to the corp/LiteLLM routes; (c) R2 prose gets a real lead: a visible plan is required, so "state the plan **in your reply text** (thinking is not visible)" may help at low effort; test before rewording. **Resolution (user-approved 2026-11-23):** known goose bug: custom providers do not pass effort (server default). benchmark.sh pins `GOOSE_THINKING_EFFORT=high` (override `BENCHMARK_THINKING_EFFORT`). Profile representatives carry `effort:` (T4 high; T3/T2 server-default), and validated entries record `thinking_effort`. Gotcha documented in knowledge `goose-desktop-operations/reasoning-effort.md`. T4 re-recorded at high. Evidence: benchmarks/probe-T4gcp-r2-20261123_231335, probe-T4gcp-nothink-r2-*, probe-T4gcp-eff-{medium,high}-r2-*, probe-T4redhat-r2-*. Feeds F1. Open | Session 2026-11-23 smoke/real campaigns |
| F25 | **R5 Checkpoint test coverage — parked (user decision 2026-11-24).** Value does not justify cost now: R5 triggers only on AgentFS maintenance (destructive/≥3-file edits under `.agents/`, `seed-agents-md.sh`); `checkpoint` appears 6× in USER log.md; no skill workflow calls `checkpoint.sh`; it would not have prevented the 11-18 wipe (outside `.agents/`, covered by rm guard + backup); git history already gives rollback for `~/.agents`. A test would instruct models to delete/rename files (the incident behaviour class) for ~1–2 h build + ~4 runs/tier/campaign. Revisit when R5 is reworded or made a T2-workspace requirement (build the test first), or during AGENTS.md prose work: per C4 a checkpoint is a constraint → candidate PreToolUse hook; maintainer steps (version bump, sync) may move into agentfs-setup. Profile keeps `R5_checkpoint: not_tested`. Parked | Session 2026-11-24 |
| F26 | **Principles test catalogue → Principle Factory** — ✅ 2026-11-25 (agentfs-eval 2.13.0, agentfs-setup 7.15.0). Catalogue built 2026-11-24, then replaced by the goal-driven Principle Factory (FACTORY.md; goals → scenarios → anti-prose → NONE → candidates → compose → one validation). 585 runs at T2/T3/T4. SOUL Principles 8 → 6, each EFFECTIVE against NONE; set validated (one interaction found and fixed by refining Name risks). Results: [principles-test-catalogue.md §7](./principles-test-catalogue.md). Follow-ups: F32 | Session 2026-11-25 |
| F27 | **R3 Session Canary repeat coverage — parked (user decision 2026-11-24).** t1 tests the turn-1 canary only; the every-10th-turn and after-compaction repeat (same LOCKED canary + re-read MEMORY/USER) has no test. A test needs a ≥10-turn or forced-compaction session (long, costly, compaction is goose-controlled). Revisit when R3 is reworded or a multi-turn harness exists (F26 `distract` will need one). Parked | Session 2026-11-24 |
| F28 | **R-g re-test follow-ups (2026-11-24, session 20261124_21 PASS, 0 holds).** Three observations dug to root cause, plus what the dig found. (1) **B1 Action-Log Correlation false FAIL** (fixture 0/7): `agentfs-behavior.sh` documented "excluding initial commit" but never excluded it, and counted self-referential files post-write.sh never logs. Fixed: changes after the scaffold commit (first commit touching `.agents/`), skipping `log.md`/`index.md`/`CHANGELOG.md`; fixture → N/A; synthetic repo: unlogged FAIL, partial FAIL, logged PASS. (2) **Maturity WARN ambiguity** ("all S1 pass"): only FAIL blocks a level; WARN and N/A are listed, not blocking (SKILL.md, execution-details.md, design-decisions.md, README). Also reworded the "B1-B3 deprecated" sentence (it meant template-behavioral.sh's tests, not Stage S2). agentfs-eval 2.12.2. (3) **Hook holds `> /tmp` redirects**: redirects into `/tmp/<path>` are read-only (`..` stays mutating). **Found while digging — preflight-reminder bypasses (1.7.0):** a mere mention of `post-write.sh`/`checkpoint.sh` anywhere (comment, heredoc, echo) exempted the whole command (`rm -rf x; echo checkpoint.sh` passed; it let this session's own edit through unheld); command substitution in arguments or double quotes was unchecked (`echo $(rm -rf x)` passed). Fixed: exemption only when the script is run (incl. `bash $P`), balanced `$(..)`/`` `..` ``/`<(..)` bodies checked as segments, `IS_RO_DEBUG=1`, `tests/is-readonly-cases.sh` (58). Corpus check, 2,283 shell calls / 3 days: 84 newly held (all real changes or unlisted tools that only passed via the mention), 16 newly released (`/tmp` redirects, bookkeeping). **post-write-enforce 1.4.0:** the flag cleared on any command mentioning post-write.sh; now only when run (289/289 real runs still clear; 23 mentions no longer do); `tests/clear-flag-cases.sh`. **post-write-enforce 1.5.0 (user: fix):** shell writes under `.agents/` now set the flag — `scripts/detect-shell-write.py` on AfterShellExecution (redirect, tee, `sed -i`/`perl -i`, cp/mv/install/ln/touch/rm, git mv/rm, python3 write calls resolved to their target incl. `Path.home()/…`, `sys.argv`, reassigned variables; `cd`/`VAR=` tracked); exempt log/index/CHANGELOG, dot-paths, `/tmp`, `*.lock`/`*.tmp`/`*.bak*`, unresolved `$VAR`, git add/commit, commands that also run post-write.sh. `tests/detect-shell-write-cases.sh` (32). Corpus: 1,596 commands naming `.agents` → 86 flagged, spot-checked all real writes (incl. every python3 edit of this session, which had no reminder before). **Stale test plugin:** `/tmp/hooktest/.agents/plugins/always-block` stayed `enabled: true` in `~/.config/goose/config.yaml` for 4 days — the 11-20 test removed the directory, but goose had persisted the project plugin in the global config (backup timeline: absent 11-19 23:13, present 11-20 11:07:01). Entry removed (backup kept); teardown gotcha documented in goose-desktop-operations/plugin-registration-teardown.md. Closed | Session 2026-11-24 |
| F29 | **Open-items close-out (2026-11-24, before Principles).** User: "Fix and close those open items before moving on." (a) `git check-ignore` held as a change → git query subcommands check-ignore/check-attr/ls-tree/rev-list/merge-base/name-rev/count-objects/var read-only; while there, `git branch <name>` (creates), `reflog expire/delete` and `remote prune/update/set-head` now mutating. (b) sqlite3/awk keyword scan covered the WHOLE command → `inv_of` scans only the tool's own invocation (quoted args kept; heredoc → whole command, conservative); sqlite3 dot-commands (.shell/.output/.import/…) and attach/vacuum count as changes; awk `print > "f"` / `print \| "cmd"` / `\| getline` count (awk string literals masked first). (c) gsettings get/list-*, rpm -q*/-V*, secret-tool lookup/search, readelf/nm/objdump read-only. (g, found while fixing) an escaped `\"` inside double quotes shifted string boundaries (a plain grep was held). (h, found while fixing) **bypass**: a quote inside the other kind (`echo "it's"; rm -rf x; echo 'y'`) hid real operators → one-pass perl quote tokenizer; the $(..) scanner treats '..' inside $(..) as literal. preflight-reminder **1.8.0**, tests 58 → 88; corpus replay vs 1.7.0 (2,216 calls): 31 released (all hand-checked read-only), 1 newly held (`ldd`, unlisted, can execute the target — by design). (d) template-behavioral.sh dedup guard → archive/template-scores.md. (e) failed shell commands never set the post-write flag → PostToolUseFailure hook; that event also fires for denied calls, so only targets with evidence of a change are flagged (mtime < 10 min, or gone for a deletion). (i, found while fixing) `post-write.sh A` cleared the WHOLE flag (a pending B was lost; also a race when a write and another file's post-write share a parallel batch) → clear-flag removes only the files post-write.sh ran on (unresolved arg → clear all, as before); (j) `$PWD` resolved from the hook process, not the cd-tracked dir (8 corpus commands mis-resolved). post-write-enforce **1.6.0**, new tests/flag-lifecycle-cases.sh (13, real payloads); corpus: 1,575 shell-write commands identical to 1.5.0, 0 false flags from the per-file rule. (f) **by design, documented** (plugin.json, docstring, README): writes made inside a script a command runs (`bash some-script.sh`) are not detected — the script's own contract must call post-write.sh. **W4 benchmark fixture** (~/app/playground/context-eng): S7 USER.md orphan — root cause the scaffold index templates (project, lite) and the profiles/index.md row never linked memories/USER.md (old template reproduces the orphan, new one gives 0) → fixed in scaffold-dotagents.sh (agentfs-setup 7.14.1, template unchanged) and create-profile.sh (agentfs-profile 1.12.1); fixture linked + committed (535e82a). B2 warns — the fixture log was accurate (22:06 = real re-seed, file mtimes) but committed in batches; B2 assumed a commit per change, which no rule requires → B2 compares each heading with the commit that recorded it (lag allowed; dated after its commit = WARN; uncommitted = pending); fixture S1–S7 all ✅, B2 ✅ 4/4 (agentfs-eval **2.12.3**). (k, found while fixing) merge-log-entry.sh's mktemp+mv turned 13 log.md files mode 600 → keeps the log's mode; modes restored to 644. Benchmark impact: the fixture gained one index row + one log entry (visible to project-cwd tests t1/t_r2/t_ii; sandbox runs copy only AGENTS.md + SOUL.md). | Closed | Session 2026-11-24 |
| F30 | **Static record (Quality + Operable-build) while SDM is unavailable (W1) — option C.** Decided by the user 2026-11-24. Built: `scripts/t4-score-call.sh` (drop-in for sdm-call.sh; gemini-3.1-pro-preview on Vertex — Google family, the prose author is Claude; Corp Gemini not entitled, Corp non-Claude models are T3); `scripts/t4-static-score.sh` (median of 3, per-dimension agreement, `--calibrate`); sdm-evaluate.sh `SDM_CALL` override + `scorer` field, T4 runs never persist observations; static-sheet-status.sh prints the scorer, T4 without PASS calibration = INVALID; contract exception in schemas/sdm-endpoint.md; agentfs-setup Steps 3–4; agentfs-eval 2.12.4 Step 8; methodology §-rule 6. Calibration: the original SDM evidence was not kept (only /tmp), so evidence was re-extracted from the inputs SDM actually scored — template v7.6.0 (3b4c3d7) + schema fc8f328; data fix: the 95.8 record was labelled 7.7.2 but scored on v7.6.0. Result 96.7 vs 95.8 (Δ +0.9, ±3) PASS, 3/3 runs identical; per-dimension 4/6 agree (T4 fails concern_count, passes accidental_complexity — SDM the reverse). Persisted v7.14.1: quality **76.7 Tunable** (3/6: concern_count 80, cross_rule_dependency 40 — R1→R3 refs added after v7.6.0, item_overlap 40 — R4/Intellectual integrity, Name risks/Data integrity, verify/verify → Principles input); build 4/4. STATIC_SHEET=CURRENT (T4, SDM re-score pending). Backend root cause found in use: Gemini sometimes returns an empty completion (finishReason STOP) → 3-attempt retry, failures logged to /tmp/t4-score-call.log. Follow-ups (same day): evidence kept in artifacts/agents-md/evidence/ (7.14.1.txt, calibration-7.6.0.txt; missing referenced evidence = INVALID); scores.yaml template_hash {rules, soul} from new template-hash.sh (renders seed-agents-md.sh + seed-soul.sh; rules hash = compliance-profile rules-hash.sh) now decides staleness, so a version label advanced without a re-score is caught. Score-map fix (user-approved, applied 2026-11-24): sdm-evaluate.sh '>=' targets now score 100 at/above target and 100·raw/target below (the proposed mirror of '<=' was rejected in testing: a 0% has_bones scored 75); ratio threshold = bucket containing t, floor(t·5) (round(t·4) let 60–80% pass a 0.80 target; all '<=' targets unchanged); new records keep `raw`. Migration scripts/migrations/2026-11-24-ge-score-map.sh (dry-run default, raw recovered from stored scores, no re-grade): 33/63 files, 52 dimension changes (39 passing 67→100, 4 failing 33→50, base has_bones 25→100), 8 script_coverage pass→fail, 32 quality aggregates +7.1 mean, 7 band changes; QOO qualification unaffected (build boolean, cnl_compliance unchanged). Each file has a history entry type score-map. Not done: '<=' targets still use distance-from-target for failures. | Closed | Session 2026-11-24 |
| F31 | **Fresh-session live check (O2).** 'AgentFS evaluation3' (20261124_22): hey eval agentfs → 0 hook denials, nothing written, L4, S1–S7 ✅, B2 4/4, runtime T3/T2 PASS. Headless sessions (since removed) proved post-write-enforce 1.6.0 incl. the PostToolUseFailure path (write; exit 3 → next tool blocked). Found: (1) preflight-reminder re-held a fast model's honest retry (1 s after the hold, inside PREFLIGHT_BATCH_MS) as a batch sibling → 1.9.0: the flag stores the held tool_call_id; if sessions.db already holds its response (goose saves a batch's responses as one message after the batch) the call is a retry; the time window is only the fallback. (2) goose-recipe-session-cleanup delete.sh crashed on the current schema (no thread_messages table) → 3.2.2: child tables discovered from the schema. (3) `goose session remove` returns 'not connected' outside a running goose server (external; use delete.sh). (4) Found while pushing the score-map fix: pre-push-scan.sh reported intermittent false 'Post-write coverage' GAPs. Cause: under `set -o pipefail`, `echo "$LOG" | grep -q` fails when grep -q exits early and echo gets SIGPIPE (7/200 on a 23 KB log). Fix: here-strings in all 5 places (0/30 false GAPs, test-pre-push-scan.sh passes). | Closed | Session 2026-11-24 |
| F32 | **Principle Factory follow-ups (2026-11-25).** (a) G14-direct: redefine as unrequested-work offers / filler, with a guard so required questions still get asked; Steps A–C on the 7.15.0 set (user: after wrap-up). (b) G15 confabulation: UNOBSERVABLE in a 12-turn sandbox; Rule or hook if wanted. (c) Compliance profile: AGENTS.md rules unchanged in 7.15.0 (stamp only) → classification none, scores kept. (d) Static record STALE (SOUL hash changed) → `upgrade agentfs` re-score (calibrated T4 while SDM is down). (e) template-check A15 default WARN → FAIL now that a CNL-clean template ships (user decision). (f) ✅ author-soul.sh: the normal path already used seed-soul.sh; its unreachable inline fallback (v6 prose) was removed, and it now fails before writing if seed-soul.sh is missing. (g) lint comma gap; risk_scan heredoc false positive. (h) T4 not re-measured for g12-r1 (accepted gap). | Session 2026-11-25 |
