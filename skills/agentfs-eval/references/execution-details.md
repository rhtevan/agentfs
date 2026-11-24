# agentfs-eval — Execution Details (reference)

Moved from SKILL.md 2026-11-18 (line budget, skill-eval S17). The Full Eval Sequence in SKILL.md is authoritative; this is the detailed walk-through.


The Full Eval Sequence above is the authoritative execution flow.
The sections below provide implementation details for each layer.

### Step 1: Determine Target

If the user provides a path, use it. Otherwise use the current
working directory.

```bash
TARGET="${user_provided_path:-.}"
```

Verify `.agents/` exists at the target:

```bash
if [ ! -d "$TARGET/.agents" ]; then
  echo "L0 — Absent: No .agents/ directory at $TARGET"
  # Stop here — nothing to evaluate
fi
```

If `.agents/` does not exist, report **L0 (Absent)** and stop.

### Step 2: Run Stage S1 — Structural Assertions

Run the structural check script:

```bash
bash <skill-dir>/scripts/agentfs-check.sh "$TARGET"
```

This produces a pass/fail report for 7 structural assertions.
No LLM involvement — pure shell.

### Step 3: Run Stage S2 — Behavioral Assertions

Run the behavioral check script:

```bash
bash <skill-dir>/scripts/agentfs-behavior.sh "$TARGET"
```

This checks for accumulated evidence (git history, log.md entries,
MEMORY.md content) and runs behavioral assertions against what it
finds. Assertions without sufficient evidence report `N/A`.

No LLM involvement — pure shell.

### Step 4: Run Stage S3 — Semantic Assertions

For each rubric YAML file in `<skill-dir>/rubrics/`:

1. Read the rubric file
2. Read the target content specified by the rubric
3. If target content is empty or absent → report `N/A` for this rubric
4. For each entry/item in the target content:
   a. Apply the `prompt_template` from the rubric, substituting the
      entry content into the `{entry}` placeholder
   b. Answer the closed-ended question — select ONLY from the
      enumerated choices
   c. Record the answer
   d. Use `vote_count` from the rubric (1 since 2026-11-18, F17)
5. Score: compare answers against `pass_answers` and `fail_answers`
6. Report pass/fail per entry with the `fail_routing` message if failed

**Critical: The LLM acts as a CLASSIFIER, not a judge.** Answer only
the specific question asked. Do not provide open-ended commentary
on content quality.

### Step 5: Produce Report

Use the template at `<skill-dir>/templates/report.md` to structure
the output. Include:

- Target path and date
- Git status (tracked? how many commits?)
- Per-layer results with pass/fail/N/A per assertion
- Details for any failures or warnings
- Overall maturity level (the highest level with no FAIL in it or below)
- Recommendations for reaching the next level

### Maturity Level Calculation

```
If .agents/ does not exist           → L0 (Absent)
Else if .agents/ exists              → L1 (Scaffolded)
  If NO Stage S1 assertion fails      → L2 (Structurally Sound)
    If NO Stage S2 assertion fails    → L3 (Behaviorally Safe)
      If NO Stage S3 assertion fails  → L4 (Semantically Accurate)
```

Only FAIL blocks a level. Assertions reporting `WARN` (advisory) or
`N/A` (insufficient evidence) do not block advancement; list them in
the report under the level they would affect. (Clarified 2026-11-24:
"all pass" was ambiguous for WARN.)

L5 (Self-Correcting) is assessed by a human observing whether the
agent can run eval, detect violations, and fix them in the same
session. It is not automatically scored.

