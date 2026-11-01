---
title: "Quality Schema v2.0 — Implementation Plan"
parent: agentfs-engineering-evolution
created: 2026-10-31
updated: 2026-10-31
tags: [quality, schema, MCACS, SDM, measurement, weak-model, operability]
---

# Quality Schema v2.0 — Implementation Plan

- **Type:** Convention
- **Status:** ✅ COMPLETE
- **Predecessor:** Phase 1 (Skill QOO Factory) — all complete
- **Source:** QOO evaluation of `agentfs-readme-audit` revealed two
  Quality dimensions produce scores that don't predict weak-model
  operability

## Problem Statement

Two of six Quality (MCACS) dimensions use deterministic heuristics
to measure proxy metrics that fail to predict whether a weaker
model can execute the skill reliably.

### concern_count — Broken Heuristic

**Current method:** `gather-skill-state.sh` greps for keywords
(`gather`, `scope`, `report`, `evaluate`, etc.) and counts how
many concern categories have at least one keyword match.

**Why it's broken:**
- Keyword presence ≠ concern separation. A skill with 6
  well-separated concerns (each in its own step with a clear
  script) is more operable than a skill with 2 concerns tangled
  into one prose blob.
- The target (`<= 2`) penalizes legitimate orchestration skills
  that span gathering, analysis, and reporting — all of which
  are standard phases of any audit/evaluation workflow.
- The dimension answers "how many responsibilities does this
  skill have?" but the operability question is "can a weak
  model follow these steps clearly?"

### accidental_complexity — Broken Heuristic

**Current method:** `gather-skill-state.sh` counts lines matching
shell-like regex patterns (`|`, `>`, `$()`, ` ``` `) plus lines
inside code fences. Reports as a percentage of total lines.

**Why it's broken:**
- **Markdown tables are false positives.** Pipe characters `|...|`
  in specification tables and overview tables match the regex.
  For `agentfs-readme-audit`: 31 of 43 SHELL_LINES are markdown
  tables, not shell commands.
- **Code fence markers are double-counted.** ` ``` ` lines match
  SHELL_LINES regex AND demarcate CODE_FENCE_LINES — counted in
  both sums.
- **Reference templates conflated with execution code.** Code
  fences containing report format templates (WHAT content) are
  counted the same as script call blocks (HOW content).
- Actual shell commands in the file: 2. Heuristic reports: 62
  lines (35%). Real ratio: ~12%.

### Shared Root Cause

Both dimensions attempt to measure a **semantic property**
(code clarity, concern separation) using **syntactic heuristics**
(regex, keyword grep). The heuristics are:
1. Imprecise (false positives dominate)
2. Measuring the wrong thing (proxy ≠ operability)
3. Not actionable (a high concern_count doesn't tell you what
   to fix for weak-model reliability)

## Design Principle

> Every Quality dimension must answer: **"Will a weaker model
> execute this skill reliably?"** Dimensions that don't predict
> operability are noise.

### Two Measurement Classes

| Class | Method | When to use |
|-------|--------|-------------|
| **Deterministic** | Bash-countable filesystem facts | When the measurement is unambiguous and the number directly predicts operability (e.g., script coverage %) |
| **Semantic** | SDM-judged from prose evidence | When the measurement requires reading comprehension — understanding what the prose *means* for executability |

`concern_count` and `accidental_complexity` tried to be Class 1
(deterministic) but were measuring Class 2 (semantic) properties
through lossy proxies. The fix: promote them to proper Class 2
measurements.

## Solution

Replace the two broken dimensions with semantic dimensions that
directly predict weak-model execution reliability.

### Dimension Replacement

| Old Dimension | New Dimension | Change |
|---------------|---------------|--------|
| `concern_count` | `step_clarity` | Keyword count → SDM judges step quality |
| `accidental_complexity` | `prose_executability` | Regex ratio → SDM judges prose-step operability |

### New Dimension: step_clarity

| Field | Value |
|-------|-------|
| Name | `step_clarity` |
| Question | Read each workflow step in this skill. For each step, check two things: (1) does the step state exactly one action? (2) does the step have an unambiguous completion criterion (exit code, file created, output to read)? Rate the overall clarity. |
| Metric | `score` (ordinal) |
| Criteria | `["all steps are unclear or compound", "few steps are clear", "most steps are clear with completion criteria", "every step states one action with an unambiguous completion criterion"]` |
| Target | `">= 2"` (most steps clear — maps to ordinal index 2+) |
| Weight | 1.0 |
| MCACS | Cohesion |
| Polarity | positive (higher is better) |
| Evidence | Step excerpts with `[SCRIPTED: yes/no]` markers |
| Why it matters | Compound or vague steps cause weak models to skip actions, invent steps, or stall waiting for undefined confirmation |

**Scoring math:**
- Criteria array has 4 levels (indices 0-3), max_scale=3
- Target `>= 2` → pass when SDM picks index 2 or 3
- score_val = score_raw / 3 * 100
  - Index 0 → 0, Index 1 → 33, Index 2 → 67, Index 3 → 100

### New Dimension: prose_executability

| Field | Value |
|-------|-------|
| Name | `prose_executability` |
| Question | Read only the prose-only steps (those marked `[SCRIPTED: no]`). Can a model with basic instruction-following ability execute them correctly without domain expertise, implicit context, or multi-hop reasoning? A prose step is executable if it tells the agent exactly what to do, what to look at, and what to output. |
| Metric | `score` (ordinal) |
| Criteria | `["prose steps require deep expertise or are ambiguous", "some prose steps need expertise or multi-hop reasoning", "most prose steps are self-contained and executable", "all prose steps are self-contained with explicit instructions"]` |
| Target | `">= 2"` (most executable) |
| Weight | 1.0 |
| MCACS | Separation of Concerns |
| Polarity | positive (higher is better) |
| Evidence | Prose-only step excerpts (steps without script calls) |
| Why it matters | Directly measures the operability gap of non-scripted steps — the weak-model failure surface |

**Scoring math:** Same as step_clarity (4-level ordinal, max_scale=3).

## Implementation Plan

### Step 1 — Update quality.yaml schema

**File:** `~/.agents/skills/schemas/quality.yaml`

**Changes:**
1. Bump `schema-version` from `"1.0"` to `"2.0"`
2. Replace the `concern_count` dimension block with `step_clarity`
3. Replace the `accidental_complexity` dimension block with
   `prose_executability`
4. Retain all other dimensions unchanged

**Exact replacement blocks:**

Replace concern_count with:
```yaml
  - name: step_clarity
    question: >
      Read each workflow step in this skill. For each step, check:
      (1) does the step state exactly one action? (2) does the step
      have an unambiguous completion criterion (exit code, file
      created, output to read)? Rate the overall step clarity.
    evidence_source: skill.md step excerpts
    metric: score
    criteria:
      - "all steps are unclear or compound"
      - "few steps are clear"
      - "most steps are clear with completion criteria"
      - "every step states one action with an unambiguous completion criterion"
    target: ">= 2"
    weight: 1.0
    polarity: positive
    mcacs: Cohesion
```

Replace accidental_complexity with:
```yaml
  - name: prose_executability
    question: >
      Read only the prose-only steps (marked [SCRIPTED: no]). Can
      a model with basic instruction-following ability execute them
      correctly without domain expertise, implicit context, or
      multi-hop reasoning? A prose step is executable if it tells
      the agent exactly what to do, what to look at, and what to
      output.
    evidence_source: skill.md prose-only step excerpts
    metric: score
    criteria:
      - "prose steps require deep expertise or are ambiguous"
      - "some prose steps need expertise or multi-hop reasoning"
      - "most prose steps are self-contained and executable"
      - "all prose steps are self-contained with explicit instructions"
    target: ">= 2"
    weight: 1.0
    polarity: positive
    mcacs: Separation of Concerns
```

**Validation:** `yq '.dimensions | length' quality.yaml` → 6.
Schema parses without error.

### Step 2 — Update gather-skill-state.sh evidence output

**File:** `~/.agents/scripts/gather-skill-state.sh`

**Changes:**
1. Remove the `# --- Concern detection ---` block (keyword grep
   heuristic, ~30 lines)
2. Remove the `# --- Accidental complexity ---` block (regex
   line counting, ~15 lines)
3. Add a `# --- Step excerpts ---` block that:
   a. Iterates through each `### Step` header
   b. Extracts the text block for each step
   c. Marks each step as `[SCRIPTED: yes]` or `[SCRIPTED: no]`
      based on whether the block contains a
      `(bash|sh)\s+.*scripts/` reference
   d. Outputs the excerpts in a structured format
4. Update the output facts section:
   - Remove: `Concern count: N (...)` line
   - Remove: `Accidental complexity lines: N of M total (P%).` line
   - Add: Step excerpt section

**Output format change:**

Before:
```
Concern count: 6 (data gathering, scope resolution, ...)
Accidental complexity lines: 62 of 173 total (35%).
```

After:
```
Step excerpts:
--- Step 1: Gather State [SCRIPTED: yes] ---
Run the gather-state script. It auto-detects scope (PROJECT first,
falls back to USER if no PROJECT README exists):
bash ~/.agents/skills/.../gather-state.sh > /tmp/readme-audit-state.txt
To force a specific scope, add --scope user or --scope project.
If the script exits 1, report to the user: "No README found."
Read /tmp/readme-audit-state.txt. It contains the resolved scope...
--- Step 2: Evaluate Alignment [SCRIPTED: yes] ---
Run the alignment evaluation script:
bash ~/.agents/skills/.../evaluate-alignment.sh /tmp/readme-audit-state.txt
If the script exits 2, SDM is unavailable...
--- Step 3: Report [SCRIPTED: no] ---
Interpret the CECX JSON from Step 2 and present a report.
Load the dimension lookup table for the resolved scope...
For each dimension, map the SDM result to a status...
```

**Implementation detail — step excerpt extraction:**

```bash
# --- Step excerpts ---
# Extract each step's text with SCRIPTED marker for SDM evidence.
echo "Step excerpts:"
for idx in "${!step_lines[@]}"; do
  start=${step_lines[$idx]}
  if [[ $((idx + 1)) -lt ${#step_lines[@]} ]]; then
    end=$((${step_lines[$((idx + 1))]} - 1))
  else
    next_section=$(awk -v s="$((start + 1))" \
      'NR > s && /^##[^#]/ {print NR; exit}' "$SKILL_MD")
    end=${next_section:-$total_lines_file}
  fi
  # Get step header
  header=$(sed -n "${start}p" "$SKILL_MD" | sed 's/^### //')
  # Extract block
  block=$(sed -n "${start},${end}p" "$SKILL_MD")
  # Check for script reference
  if echo "$block" | grep -qP '(bash|sh)\s+.*scripts/'; then
    scripted="yes"
  else
    scripted="no"
  fi
  # Strip code fence markers for cleaner evidence
  clean_block=$(echo "$block" | grep -v '^```' | head -20)
  echo "--- ${header} [SCRIPTED: ${scripted}] ---"
  echo "$clean_block"
done
```

Note: `step_lines` array is already computed in the script_coverage
block (from the Step 2 fix in this session). Reuse it.

**Truncation:** Each step excerpt is capped at 20 lines to keep
total evidence size bounded for SDM context window.

### Step 3 — Verify sdm-evaluate.sh compatibility

**File:** `~/.agents/scripts/sdm-evaluate.sh`

No code changes expected. Verify that:
1. `score` metric type with `criteria` array works for the new
   dimensions (it already does — used by `count` and `ratio`)
2. `polarity: positive` is handled (it is — the scoring logic
   checks `target_op == ">="` → higher is better)
3. The evidence text (now including step excerpts) doesn't exceed
   SDM context limits. Estimate: ~500 tokens for a 3-step skill,
   ~2000 for a 10-step skill. Well within 14B context.

**Validation:** Run `sdm-evaluate.sh` with the new schema against
a test evidence file. Confirm it produces valid CECX JSON with
the new dimension names.

### Step 4 — Re-score agentfs-readme-audit

1. Run: `bash gather-skill-state.sh <skill-dir> > /tmp/evidence.txt`
2. Verify step excerpts appear in evidence
3. Run: `bash sdm-evaluate.sh <skill-dir> quality.yaml --evidence /tmp/evidence.txt`
4. Verify new dimensions `step_clarity` and `prose_executability`
   appear in output with valid scores
5. Persist to `scores.yaml` via `hey score skill agentfs-readme-audit`

### Step 5 — Re-score crc-status

Same as Step 4 for `crc-status`.

### Step 6 — Update documentation

1. Update `scores.yaml` comment explaining quality dimensions
2. Update `implementation-plan.md` status to include Phase 6
3. Log changes to `~/.agents/log.md`

## Dependency Graph

```
Step 1 (quality.yaml)
  ↓
Step 2 (gather-skill-state.sh)
  ↓
Step 3 (verify sdm-evaluate.sh) ← no changes expected
  ↓
Step 4 (re-score agentfs-readme-audit) ──→ scores.yaml
  ↓
Step 5 (re-score crc-status) ──→ scores.yaml
  ↓
Step 6 (documentation)
```

Steps 1-2 are sequential (schema must exist before evidence
references it). Steps 4-5 are independent (can run in either
order). Step 3 is a verification gate.

## Risk Assessment

| Risk | Likelihood | Mitigation |
|------|:----------:|------------|
| SDM 14B can't reliably judge step_clarity | Low | Criteria are concrete and ordered. 14B handles ordinal classification well per Phase 0 benchmarks. |
| Step excerpts too large for SDM context | Low | 20-line cap per step. Even 10-step skills stay under 2000 tokens. |
| New scores incomparable with v1.0 history | Certain | Expected. Document schema version in history entries. Old entries retain v1.0 dimension names. |
| Other tools depend on concern_count or accidental_complexity output format | Low | Searched: only `sdm-evaluate.sh` consumes the evidence. No other tools parse these specific lines. |

## Success Criteria

1. `quality.yaml` schema-version is `"2.0"` with 6 dimensions
2. `gather-skill-state.sh` produces step excerpts, no concern
   count, no accidental complexity ratio
3. `sdm-evaluate.sh` scores the new dimensions without errors
4. `agentfs-readme-audit` Quality score reflects actual prose
   operability (expected: ≥75 Tunable given clear, well-structured
   steps)
5. `crc-status` re-scored without regression
6. Dimension scores are actionable: a low `step_clarity` score
   tells you which steps to clarify; a low `prose_executability`
   score tells you which prose steps need scripts or simplification
