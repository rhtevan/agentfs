---
name: agentfs-readme-audit
description: >
  audit readme, readme alignment, readme drift, check readme
metadata:
  version: "3.4.0"
  model-tier: T3
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
| **Version** | 3.3.0 |
| **Trigger** | Automatic during Git Push Safety, or explicit |
| **Dependencies** | `scripts/gather-state.sh`, `scripts/evaluate-alignment.sh` |

## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | Gather filesystem state deterministically | `gather-state.sh` exits 0 with structured output |
| S2 | Evaluate README alignment via SDM | `extract-comparison.sh` + `sdm-evaluate.sh` produces CECX JSON |
| S3 | Present alignment report to user | Report contains dimension table and verdict |
| S4 | Recommend fixes for drift | Each drifted dimension has a specific fix |

## Rules

Do NOT read README.md directly. Do NOT use `cat`, `shell`, `read_image`,
or any tool to read the README file. The gather-state script reads it.
All state comes from scripts. You orchestrate scripts, not files.

Do NOT fabricate, generate, or invent data. Every fact in your report
MUST come from script output. If a dimension cannot be evaluated from
the available evidence, mark it N/A — do not guess.

## Workflow

Execute these steps now. Run the scripts immediately. Do not explain
the steps to the user. Do not ask for confirmation before Step 1.

### Step 1: Gather State

Run the gather-state script. It auto-detects scope (PROJECT first,
falls back to USER if no PROJECT README exists):

```bash
bash ~/.agents/skills/agentfs-readme-audit/scripts/gather-state.sh > /tmp/readme-audit-state.txt
```

To force a specific scope, add `--scope user` or `--scope project`.

If the script exits 1, report to the user:
"No README found. Audit skipped."
Stop here.

Read `/tmp/readme-audit-state.txt`. It contains the resolved scope,
filesystem facts, and full README content. This is the ONLY source
of truth for this audit. Do not gather state by other means.

### Step 2: Evaluate Alignment

Run the alignment evaluation script:

```bash
bash ~/.agents/skills/agentfs-readme-audit/scripts/evaluate-alignment.sh /tmp/readme-audit-state.txt
```

If the script exits 2, SDM is unavailable. Fall through to Step 3
and perform the comparison using the facts from
`/tmp/readme-audit-state.txt` directly.

If it succeeds, read the CECX JSON output. Each dimension has
`pass: true/false`, `score`, and `confidence`.

### Step 3: Report

Interpret the CECX JSON from Step 2 and present a report.

Load the dimension lookup table for the resolved scope:

```
load_skill(name: "agentfs-readme-audit/references/dimensions.md")
```

For each dimension, map the SDM result to a status:
- `pass: true` with `confidence >= 0.7` → ✅ aligned
- `pass: true` with `confidence < 0.7` → ⚠️ uncertain
- `pass: false` with `score: 0` → ⚠️ DRIFT
- `pass: false` with `score: 50` → ⚠️ uncertain
- Coverage Gaps (D9/P8) → ℹ️ informational

Filter dimensions by scope: `D*` for USER, `P*` for PROJECT.

If SDM was unavailable in Step 2, compare the raw gather-state
facts against the README content from `/tmp/readme-audit-state.txt`.

Format as a single report:

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

For each dimension with ⚠️ DRIFT, state the specific edit needed.
Do not auto-apply fixes. Present them to the user for approval.

## Error Handling

| Step | Script | On Failure |
|:----:|--------|------------|
| 1 | `gather-state.sh` | Exit 1: no README, skip audit. Exit 2: not a git repo, report error. |
| 2 | `extract-comparison.sh` + `sdm-evaluate.sh` | Exit 2: SDM unavailable, fall through to manual comparison. Exit 1: partial, report what succeeded. |

## Integration with Git Push Safety

When triggered by `pre-push-scan.sh` emitting `README_AUDIT_REQUIRED`:

1. Run Step 1 using the repo that Git Push Safety resolved.
2. Run Steps 2-3 as normal.
3. Present the alignment report alongside the pre-push security report.
4. Drift is advisory, not blocking. The user decides whether to fix
   before pushing.

## What This Skill Does NOT Do

- Does not auto-fix README.md.
- Does not replace `pre-push-scan.sh`.
- Does not check prose quality or grammar.

## References

- [`references/dimensions.md`](./references/dimensions.md) — USER (D1-D9) and PROJECT (P1-P8) dimension lookup tables

## Supporting Files

| File | Purpose |
|------|---------|
| `scripts/gather-state.sh` | Deterministic state gathering — scope resolution, filesystem facts, README content |
| `scripts/extract-comparison.sh` | Extract compact comparison evidence from gathered state |
| `scripts/evaluate-alignment.sh` | Wrapper: extract-comparison + sdm-evaluate in one call |
| `scores.yaml` | QOO scores (quality, observable, operable) |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Exit 1 + "no README found" | No README.md in PROJECT or USER scope | Create README.md or use `--scope user` |
| Exit 2 + "not a git repository" | CWD is not inside a git repo | `cd` to a git repo or use `--scope user` |
| Exit 2 + "SDM unavailable" | localhost:9000 not running | Start the LLM/SDM endpoint. Fall through to manual comparison. |
| Empty report | `gather-state.sh` output redirected, model didn't read the file | Check stderr for `✅` confirmation. Read `/tmp/readme-audit-state.txt`. |
| All dimensions N/A | Scope mismatch — USER dims shown for PROJECT or vice versa | Verify scope in gather-state output. Use `--scope` flag. |

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
