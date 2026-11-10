---
title: Dry-Run Pattern Adoption & AgentFS Compliance Profile
parent: agentfs-engineering-evolution
created: 2026-11-09
updated: 2026-11-09
tags: [dry-run, cqs, compliance, benchmark, agentfs, action-plan]
---

# Dry-Run Pattern Adoption & AgentFS Compliance Profile

- **Type:** Action Plan
- **Status:** IN PROGRESS — Obj 1 Phases 1+2 complete, Obj 2 complete
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
| B.1 | Add T10 test for `--dry-run` interpretation (Phase 1 dependency) | Test script |
| B.2 | Add `--output-yaml` mode to benchmark.sh | Machine-readable output |
| B.3 | Create `update-compliance.sh` that runs harness → updates YAML | Automation script |
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
| D.2 | When `seed-agents-md.sh` changes → flag "compliance profile stale" | Warning in log.md |
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
