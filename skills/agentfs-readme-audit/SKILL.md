---
name: agentfs-readme-audit
description: >
  audit readme, readme alignment, readme drift, check readme
metadata:
  version: "3.0.0"
  tags: [agentfs, readme, audit, semantic, pre-push]
user-invocable: true
disable-model-invocation: false
---

# AgentFS README Audit

Check whether a README accurately reflects the current state of an
AgentFS scope. Supports USER and PROJECT scopes.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 3.0.0 |
| **Trigger** | Automatic during Git Push Safety, or explicit |
| **Dependencies** | `scripts/gather-state.sh`, `scripts/evaluate-readme.sh` |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Gather filesystem state deterministically | `gather-state.sh` exits 0 with structured output |
| S2 | Evaluate README alignment via SDM | `evaluate-readme.sh` produces dimension verdicts |
| S3 | Present alignment report to user | Report contains dimension table and verdict |
| S4 | Recommend fixes for drift | Each drifted dimension has a specific fix |

## Workflow

Execute these steps in order.

### Step 1: Gather State

Run the gather-state script. Pass `--repo-root` if the audit target
is not the current working directory.

```bash
bash scripts/gather-state.sh
```

If the script exits 1, report to the user:
"No README found in PROJECT scope. Audit skipped."
Stop here.

Read the output. It contains the resolved scope, filesystem facts,
and full README content.

### Step 2: Evaluate Alignment

Run the evaluate-readme script. Pass the gather-state output.

```bash
bash scripts/gather-state.sh | bash scripts/evaluate-readme.sh
```

If SDM is unavailable (exit 2), skip SDM evaluation. Fall through
to Step 3 and perform the comparison using the gather-state facts
directly.

If SDM evaluation succeeds, read the output. It contains a dimension
table with per-dimension verdicts and an aggregate verdict.

### Step 3: Interpret Results

Read the gather-state output and the evaluate-readme output together.

For each dimension in the evaluate-readme report:
- If the dimension shows ✅, no action is needed.
- If the dimension shows ⚠️ DRIFT, check the gather-state facts
  to confirm the drift. State what the README claims and what the
  filesystem shows.
- If the dimension shows ℹ️ Gap, note it as informational. Gaps
  are not blocking.
- If the dimension shows ⚠️ uncertain, check the gather-state
  facts to make a judgment. SDM confidence was low.

If SDM was unavailable in Step 2, perform the comparison manually.
Compare the README content from gather-state output against the
filesystem facts. Check each dimension listed below.

#### USER scope dimensions

| # | Dimension | Check |
|---|-----------|-------|
| D1 | Skill Count | Does README count match actual skill count? |
| D2 | Skill Categories | Does category table match actual skills? |
| D3 | Knowledge Bundles | Does bundle count or list match? |
| D4 | Directory Structure | Does tree diagram match actual layout? |
| D5 | Guardrail Summary | Do guardrail names and count match? |
| D6 | Version References | Do version numbers match? |
| D7 | Feature Descriptions | Do features reflect actual skills? |
| D8 | Setup Instructions | Do paths and commands still work? |
| D9 | Coverage Gaps | Does major content exist without mention? |

#### PROJECT scope dimensions

| # | Dimension | Check |
|---|-----------|-------|
| P1 | Project Skill Count | Does count match actual? |
| P2 | Agent Profiles | Do profiles match actual? |
| P3 | Agent Identity | Does identity match SOUL.md? |
| P4 | Directory Structure | Does tree match actual layout? |
| P5 | AGENTS.md References | Are references accurate? |
| P6 | Feature Descriptions | Do features reflect actual content? |
| P7 | Setup / Onboarding | Do instructions still work? |
| P8 | Coverage Gaps | Does content exist without mention? |

Absence of a claim is not drift. Drift occurs only when the README
makes a claim that contradicts reality. Mark absent claims as N/A.

Coverage Gaps (D9/P8) are informational. Mark as ℹ️, not ⚠️.

### Step 4: Present Report

Format the findings as a single report. Use this structure:

```
## README Alignment Report (<SCOPE> scope)

| Dimension | Status | Detail |
|-----------|--------|--------|
| D1 Skill Count | ✅ / ⚠️ / N/A | [specifics] |
...

### Verdict

✅ ALIGNED — README accurately reflects current state.
ℹ️ COVERAGE GAPS — N area(s) not mentioned. Non-blocking.
⚠️ DRIFT DETECTED — N dimension(s) misaligned.
```

### Step 5: Recommend Fixes

For each dimension with ⚠️ DRIFT, state the specific edit needed.
Do not auto-apply fixes. Present them to the user for approval.

## Error Handling

| Step | Script | On Failure |
|:----:|--------|------------|
| 1 | `gather-state.sh` | Exit 1: no README, skip audit. Exit 2: not a git repo, report error. |
| 2 | `evaluate-readme.sh` | Exit 2: SDM unavailable, fall through to manual comparison. Exit 1: partial, report what succeeded. |

## Integration with Git Push Safety

When triggered by `pre-push-scan.sh` emitting `README_AUDIT_REQUIRED`:

1. Run Step 1 using the repo that Git Push Safety resolved.
2. Run Steps 2-5 as normal.
3. Present the alignment report alongside the pre-push security report.
4. Drift is advisory, not blocking. The user decides whether to fix
   before pushing.

## What This Skill Does NOT Do

- Does not auto-fix README.md.
- Does not replace `pre-push-scan.sh`.
- Does not check prose quality or grammar.

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
