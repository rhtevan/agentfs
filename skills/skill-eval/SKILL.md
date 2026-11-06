---
name: skill-eval
description: >
  check skill, eval skill, audit skill quality,
  check all skills, skill evaluation, assess skill
argument-hint: "hey check skill <name> | hey eval skill <name> | hey assess skill <name> | hey check all skills"
compatibility: "bash, shellcheck (optional), yq, jq"
metadata:
  author: agentfs
  version: "2.2.0"
  model-tier: T4
  tags: [agentfs, skills, evaluation, quality, audit, qoo, operable]
user-invocable: true
disable-model-invocation: false
---

# Skill Eval

Evaluate individual skills through deterministic checks, QOO build-time
scoring, and runtime operable assessment. Produces a severity-graded
report per skill with per-axis QOO bands.

This skill is the sole authority for skill-level evaluation.
`agentfs-eval` evaluates workspace health and does NOT inspect
skill internals.

## Prerequisites

- `bash`, `grep`, `find`, `wc`
- `shellcheck` (optional — S05 skipped if absent)
- `yq`, `jq` (required for Tier 1 QOO scoring)
- LLM required only for S23–S26 rubric checks
- SDM endpoint at localhost:9000 (required for Tier 1 QOO — skipped
  if unavailable)

## Quick Dispatch

| User says | Run |
|-----------|-----|
| "check skill \<name\>" | Tier 0 only. Run `skill-check.sh`. Stop after reporting. |
| "eval skill \<name\>" | Full eval. Execute ALL steps in the Full Eval Sequence below. |
| "assess skill \<name\>" | Comprehensive assessment. Execute ALL steps in the Assess Sequence below. |
| "check all skills" | List skills → ask human permission → run Tier 0 against each → summary. |

**ROUTING STOP: Find your match above, then jump to that section.
Do NOT read past the matched section. Do NOT run the Full Eval
Sequence unless the match says "Full eval".**

## Modes

### Mode 1: Single Skill — Tier 0 Only (check skill)

1. Resolve skill path — check USER (`~/.agents/skills/<name>/`)
   then PROJECT (`./.agents/skills/<name>/`).
2. Run deterministic checks:
   ```bash
   bash ~/.agents/skills/skill-eval/scripts/skill-check.sh <path-to-skill-dir>
   ```
3. Run LLM rubric checks (S23–S26) by reading each rubric YAML
   in `~/.agents/skills/skill-eval/rubrics/` and applying it to
   the skill content.
4. Present report.

**END OF TIER 0 ONLY. Stop here.**

### Mode 2: All Skills — Tier 0 Only (check all skills)

1. List all skills at the target scope (USER or PROJECT).
2. Present the list and ask for human confirmation before proceeding.
3. On approval, run Mode 1 against each skill.
4. Produce summary report with per-skill pass/warn/fail counts.

**END OF ALL SKILLS MODE. Stop here.**

---

## Full Eval Sequence (eval skill)

Execute ALL steps in order. Do NOT skip steps. Do NOT jump to a
later step because it seems more relevant to the conversation.

### Step 1 — Resolve Skill

Resolve the skill path. Check USER scope first (`~/.agents/skills/<name>/`),
then PROJECT scope (`./.agents/skills/<name>/`).

Verify `SKILL.md` exists. If absent, report and stop.

Set `SKILL_DIR` to the resolved absolute path.

### Step 2 — Tier 0: Deterministic Checks (S01–S22)

Run the deterministic check script:

```bash
bash ~/.agents/skills/skill-eval/scripts/skill-check.sh "$SKILL_DIR"
```

Record pass/fail/warn/skip counts. Continue to Step 3.

### Step 3 — Tier 0: LLM Rubric Checks (S23–S26)

For each rubric YAML file in `~/.agents/skills/skill-eval/rubrics/`:

1. Read the rubric file.
2. Read the target content from `$SKILL_DIR/SKILL.md`.
3. Apply the `prompt_template` from the rubric, substituting the
   skill content into the placeholder.
4. Answer the closed-ended question — select ONLY from the
   enumerated choices.
5. Record the answer.

The LLM acts as a CLASSIFIER, not a judge. Answer only the specific
question asked. Do not provide open-ended commentary.

Continue to Step 4.

### Step 4 — Tier 1: Gather Structural Facts

Run the gather-state script to produce deterministic facts:

```bash
bash ~/.agents/scripts/gather-skill-state.sh "$SKILL_DIR" > /tmp/skill-eval-evidence.txt
```

Read the output file. It contains pre-computed metrics for all
QOO dimensions. Continue to Step 5.

### Step 5 — Tier 1: BMBT Build-time Operable Score

Run SDM evaluation against the operable schema using build-time
dimensions:

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/operable.yaml \
  --evidence /tmp/skill-eval-evidence.txt \
  --phase build
```

If the output contains `"band": "SDM_UNAVAILABLE"`, report:
"⚠️ SDM unavailable — BMBT score skipped."
Skip to Step 8.

Extract the build-phase dimensions from the SDM JSON output:
`has_bones`, `has_muscle`, `has_brain`, `has_harness`.

Record each dimension's score, pass/fail, and confidence.
Continue to Step 6.

### Step 6 — Tier 1: Quality + Observable Read

**6a. Read existing scores:**

If `$SKILL_DIR/scores.yaml` exists, read the `quality` and
`observable` sections. Report these scores in the final report
as "Quality (from skill-gen)" and "Observable (from skill-gen)".

**6b. Compute fresh Quality + Observable for comparison:**

Run SDM evaluation against Quality and Observable schemas:

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/quality.yaml \
  --evidence /tmp/skill-eval-evidence.txt
```

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/observable.yaml \
  --evidence /tmp/skill-eval-evidence.txt
```

Report these scores as "Quality (fresh)" and "Observable (fresh)"
in the final report. Do NOT persist them — `quality` and
`observable` sections in `scores.yaml` are owned by `skill-gen`.

Continue to Step 7.

### Step 7 — Tier 2: CECX Runtime Operable Score

Search for the latest execution trace for this skill:

```bash
LATEST_TRACE=$(ls -t ~/.agents/.traces/${SKILL_NAME}*.jsonl 2>/dev/null | head -1)
```

**If no trace exists:** Report "⚠️ No execution traces found.
CECX runtime score: N/A. Run the skill to generate traces."
Skip to Step 8.

**If a trace exists:** Run SDM evaluation:

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$LATEST_TRACE" \
  ~/.agents/skills/schemas/operable.yaml
```

Extract the runtime-phase dimensions from the SDM JSON output:
`step_completion`, `no_fabrication`, `minimal_inference_hops`,
`token_efficiency`, `correct_sequence`, `scope_resolution`,
`no_improvised_recovery`.

Record each dimension's score, pass/fail, and confidence.
Continue to Step 8.

### Step 8 — Persist Operable Scores

Update the skill's scores file:

```
$SKILL_DIR/scores.yaml
```

Read the existing file if present. Update these sections from
Steps 5 and 7:

1. **`operable.build.dimensions`** — copy each build-phase
   dimension's score, pass, and confidence from Step 5.
2. **`operable.runtime.dimensions`** — copy each runtime-phase
   dimension's score, pass, and confidence from Step 7.
   If Step 7 was N/A, set `operable.runtime` to `null` with
   a note: "No execution traces available."
3. **`operable.build.aggregate_score`** and **`band`** — from
   SDM JSON root.
4. **`operable.runtime.aggregate_score`** and **`band`** — from
   SDM JSON root (or null if N/A).
5. **`operable.runtime.model`** — extract from the trace init
   record or from the user's stated model. CECX scores are
   model-dependent. Record which model produced the trace.
6. **`operable.runtime.trace`** — the trace filename used.
7. **`operable.evaluated`** — current timestamp.
8. **`history`** — append a new entry with date, type `operable`,
   score (build aggregate), band, and a one-line note.

9. **`qoo-qualified`** — compute deterministically from all
   available scores in the file. The formula:
   ```
   qoo-qualified = quality.band ∈ {Tunable, Operable}
                AND observable.band ∈ {Tunable, Operable}
                AND operable.build.band ∈ {Tunable, Operable}
   ```
   If any axis has not been evaluated yet (section missing),
   set `qoo-qualified: false`. Runtime CECX is exempt — it is
   model-dependent and does not gate qualification.
   Do NOT set this field based on judgment. Compute it from
   the band values only.

Do NOT overwrite the entire file. Preserve the `quality` and
`observable` sections (owned by `skill-gen`), the `skill`,
and `version` fields, and existing history entries.

Immediately run post-write.sh after writing:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh \
  "$SKILL_DIR/scores.yaml" "skill-eval: operable scores updated"
```

Do NOT respond to the user until the command completes.

### Step 9 — Consolidated Report

Produce a single report covering all tiers:

```
## Skill Eval Report: <skill-name>

Date: YYYY-MM-DD HH:MM
Version: <metadata.version>
Path: <skill-dir>

### Tier 0 — Deterministic (S01–S22)
Pass: N | Fail: N | Warn: N | Skip: N
<details for failures and warnings>

### Tier 0 — LLM Rubric (S23–S26)
<per-rubric pass/fail/N/A>

### Tier 1 — Build-time Operable (BMBT)
| Dimension | Score | Pass | Confidence |
|-----------|:-----:|:----:|:----------:|
| has_bones | ... | ... | ... |
| has_muscle | ... | ... | ... |
| has_brain | ... | ... | ... |
| has_harness | ... | ... | ... |
Aggregate: <score> | Band: <band>

### Tier 1 — Quality (MCACS) — read-only
<existing scores from scores.yaml or fresh SDM scores>

### Tier 1 — Observable — read-only
<existing scores from scores.yaml or fresh SDM scores>

### Tier 2 — Runtime Operable (CECX)
<per-dimension scores or "N/A — no traces">
Aggregate: <score> | Band: <band>

### QOO Summary
| Axis | Score | Band | Source |
|------|:-----:|------|--------|
| Quality | ... | ... | skill-gen / fresh |
| Observable | ... | ... | skill-gen / fresh |
| Operable (build) | ... | ... | skill-eval |
| Operable (runtime) | ... | ... | skill-eval / N/A |
```

---

## Assess Sequence (assess skill)

Comprehensive assessment that chains Score Skill (Quality + Observable)
with Full Eval (Tier 0 + BMBT + CECX) into a single pass. Evidence is
gathered once and reused across all SDM calls.

Execute ALL steps in order. Do NOT skip steps.

### Step 1 — Resolve Skill

Same as Full Eval Step 1. Resolve the skill path. Check USER scope
first (`~/.agents/skills/<name>/`), then PROJECT scope
(`./.agents/skills/<name>/`).

Verify `SKILL.md` exists. If absent, report and stop.

Set `SKILL_DIR` to the resolved absolute path.

### Step 2 — Gather Evidence (once)

```bash
bash ~/.agents/scripts/gather-skill-state.sh "$SKILL_DIR" > /tmp/skill-assess-evidence.txt
```

Read the output. This evidence file is reused by all subsequent
SDM calls. Do NOT re-run gather-skill-state.sh.

### Step 3 — Score: Quality (MCACS)

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/quality.yaml \
  --evidence /tmp/skill-assess-evidence.txt
```

Record the JSON output.

### Step 4 — Score: Observable

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/observable.yaml \
  --evidence /tmp/skill-assess-evidence.txt
```

Record the JSON output.

### Step 5 — Persist Quality + Observable

Update `$SKILL_DIR/scores.yaml` with the `quality:` and `observable:`
sections from Steps 3 and 4. Follow the same structure and rules as
Score Skill mode in `skill-gen` (Step 5 of that mode).

Do NOT overwrite `operable:` — that section is owned by `skill-eval`.
Preserve existing `operable:` and `history:` entries.

Append a history entry with type `quality+observable`.

Immediately run post-write.sh after writing.

### Step 6 — Tier 0: Deterministic Checks

```bash
bash ~/.agents/skills/skill-eval/scripts/skill-check.sh "$SKILL_DIR"
```

Record pass/fail/warn/skip counts.

### Step 7 — Tier 0: LLM Rubric Checks (S23–S26)

Same as Full Eval Step 3. For each rubric YAML in
`~/.agents/skills/skill-eval/rubrics/`, apply the rubric
as a classifier against `$SKILL_DIR/SKILL.md`.

### Step 8 — BMBT Build-time Operable

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$SKILL_DIR" \
  ~/.agents/skills/schemas/operable.yaml \
  --evidence /tmp/skill-assess-evidence.txt \
  --phase build
```

Record the build-phase dimensions.

### Step 9 — CECX Runtime Operable

Search for the latest execution trace:

```bash
LATEST_TRACE=$(ls -t ~/.agents/.traces/${SKILL_NAME}*.jsonl 2>/dev/null | head -1)
```

If no trace exists, report N/A and skip to Step 10.

If a trace exists:

```bash
bash ~/.agents/scripts/sdm-evaluate.sh "$LATEST_TRACE" \
  ~/.agents/skills/schemas/operable.yaml
```

Record the runtime-phase dimensions.

### Step 10 — Persist Operable + Compute Qualification

Update `$SKILL_DIR/scores.yaml` with `operable.build` and
`operable.runtime` from Steps 8 and 9. Same rules as Full Eval
Step 8.

Compute `qoo-qualified` deterministically:

```
qoo-qualified = quality.band ∈ {Tunable, Operable}
             AND observable.band ∈ {Tunable, Operable}
             AND operable.build.band ∈ {Tunable, Operable}
```

Runtime CECX is exempt. Append a history entry with type `assess`.

Immediately run post-write.sh after writing.

### Step 11 — Combined Report

Produce a single report covering all axes:

```
## Skill Assessment: <skill-name>

Date: YYYY-MM-DD HH:MM
Version: <metadata.version>
Path: <skill-dir>

### Tier 0 — Deterministic (S01–S22)
Pass: N | Fail: N | Warn: N | Skip: N
<details for failures and warnings>

### Tier 0 — LLM Rubric (S23–S26)
<per-rubric pass/fail>

### QOO Scores

| Axis | Score | Band | Dims |
|------|:-----:|------|------|
| Quality (MCACS) | ... | ... | N/N pass |
| Observable | ... | ... | N/N pass |
| Operable (build) | ... | ... | N/N pass |
| Operable (runtime) | ... | ... | N/N pass or N/A |

qoo-qualified: true/false

### Quality Dimensions
<per-dimension table>

### Observable Dimensions
<per-dimension table>

### Build Dimensions (BMBT)
<per-dimension table>

### Runtime Dimensions (CECX)
<per-dimension table or "N/A — no traces">

### Improvement Priorities
<top 3 failing dimensions with suggested fixes>
```

---

## Checks

### Deterministic Checks (S01–S22)

Run via `scripts/skill-check.sh`. No LLM required.

| ID | P | Check | Severity | Method |
|:--:|:-:|-------|:--------:|--------|
| S01 | 1 | Frontmatter has `name`, `description`, `metadata.version` (quoted semver), `metadata.tags` (non-empty), `user-invocable` | 🔴 | YAML parse |
| S02 | 1 | `name` matches parent directory name | 🔴 | String compare |
| S03 | 1 | Signal phrases are 2–4 words each | 🟡 | Word count |
| S04 | 1 | Opening paragraph after `# Title` heading | 🟡 | Line scan |
| S05 | 1 | Shellcheck passes on `.sh` scripts | 🟡 | `shellcheck` |
| S06 | 1 | Consistent values across scripts and SKILL.md (ports, hostnames) | 🟡 | Cross-reference |
| S07 | 2 | Referenced commands exist | 🟡 | `command -v` |
| S08 | 2 | Referenced file paths exist | 🔴 | Filesystem check |
| S09 | 2 | Supporting Files section matches actual directory contents | 🟡 | Dir listing diff |
| S10 | 2 | No references to deleted/renamed files | 🔴 | Path check |
| S11 | 3 | `CHANGELOG.md` exists; latest version matches `metadata.version` | 🟡 | Version compare |
| S12 | 3 | Markdown well-formed (unclosed code blocks, broken tables) | 🟢 | Syntax scan |
| S13 | 4 | Specification section exists with IDs | 🟡 | Section scan |
| S14 | 4 | Tests section exists with testcases mapped to spec IDs | 🟡 | Section scan |
| S15 | 5 | No hardcoded secrets/API keys in scripts | 🔴 | Regex patterns |
| S16 | 5 | No `eval`/`source` of untrusted input in scripts | 🔴 | Grep scan |
| S17 | 6 | SKILL.md line count; warn if >300 | 🟡 | `wc -l` |
| S18 | 6 | `## References` section if `references/` dir exists | 🟡 | Dir + heading check |
| S19 | 7 | Scripts use semantic exit codes (0/1/2/3) | 🟡 | Parse `exit` statements |
| S20 | 7 | Error Handling table exists | 🟡 | Section scan |
| S21 | 7 | Troubleshooting table exists | 🟡 | Section scan |
| S22 | 7 | Privilege gates use exit 3 | 🟡 | Grep `sudo` + exit code |

### LLM Rubric Checks (S23–S26)

Rubric YAMLs in `rubrics/`. Require LLM classification.

| ID | P | Check | Method |
|:--:|:-:|-------|--------|
| S23 | 1 | Operations as prose that should be scripts | LLM per code block |
| S24 | 3 | Duplicate/conflicting procedures | LLM across sections |
| S25 | 5 | Prompt injection patterns in SKILL.md | LLM classification |
| S26 | 1 | Steps follow logical sequence | LLM classification |

## Severity Levels

| Icon | Level | Meaning |
|:----:|:-----:|---------|
| 🔴 | Critical | Skill will malfunction |
| 🟡 | Warning | Skill works but violates a principle |
| 🟢 | Info | Improvement suggestion |

## QOO Axis Ownership

| `scores.yaml` section | Written by | Signal |
|------------------------|------------|--------|
| `quality:` (MCACS) | `skill-gen` | `hey score skill` |
| `observable:` | `skill-gen` | `hey score skill` |
| `operable.build:` (BMBT) | `skill-eval` | `hey eval skill` |
| `operable.runtime:` (CECX) | `skill-eval` | `hey eval skill` |
| `history:` | Both (append-only) | Either |

`skill-eval` computes Quality and Observable fresh for the report
but does NOT persist them. Those sections are owned by `skill-gen`.

## QOO Band Thresholds

| Band | Score Range |
|------|:-----------:|
| Redesign | 0–39 |
| Re-engineer | 40–59 |
| Tunable | 60–79 |
| Operable | 80–100 |

## Companion Skills

- **`skill-gen`** — Creates and upgrades skills. Owns `quality` and
  `observable` sections in `scores.yaml`.
- **`agentfs-eval`** — Evaluates workspace health. Does NOT inspect
  skill internals — that responsibility belongs to `skill-eval`.
- **`skill-check`** — Alias. `skill-check.sh` is the Tier 0
  deterministic engine used by this skill.

## Supporting Files

- `scripts/skill-check.sh` — Tier 0 deterministic checks (S01–S22)
- `rubrics/prose-to-script.yaml` — S23 rubric
- `rubrics/duplicate-procedures.yaml` — S24 rubric
- `rubrics/prompt-injection.yaml` — S25 rubric
- `rubrics/logical-sequence.yaml` — S26 rubric

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
