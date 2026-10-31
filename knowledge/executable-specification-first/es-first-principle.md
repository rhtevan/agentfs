# ES-First Principle

## Statement

Before any implementation or change to AgentFS tooling (scripts,
rules, checkers, skills), write an Executable Specification (ES)
that defines pass/fail criteria. The ES must be verified failing
against the current state before the fix is implemented. The
implementation can only claim completion when the ES passes.

## Three Components

| # | Component | Requirement |
|---|-----------|-------------|
| 1 | **ES-First** | Write the test before the fix. The test defines what "fixed" means. |
| 2 | **Fail-Verify** | Run the ES against the current (broken) state. It must produce FAIL. If it passes, the ES does not detect the problem — fix the test first. |
| 3 | **Completion Gate** | Run the ES after the fix. It must produce PASS. Do not claim completion until it does. |

## Sequence

```
1. Identify problem
2. Write ES (test case / checker / assertion)
3. Run ES against current state → must FAIL (red)
4. Implement the fix
5. Run ES against fixed state → must PASS (green)
6. Claim completion
```

Steps 3 and 5 are non-negotiable. Skipping step 3 risks writing
a test that always passes (vacuously true). Skipping step 5 risks
claiming a fix that doesn't actually work.

## Relationship to Existing AgentFS Concepts

| Concept | Relationship |
|---------|-------------|
| Pre-Flight Validation Gate (Rule 2, Tier 2) | Covers component 3 (completion gate) but not components 1–2. ES-First strengthens Pre-Flight by requiring the gate to exist and fail-verify before execution begins. |
| QOO `has_harness` dimension | Measures test coverage, not test sequence. ES-First adds the temporal constraint: test must precede implementation. |
| Self-Contained Actions Principle | Was discovered through an implicit ES-First process (benchmark revealed 0% fire rate → fix → benchmark passed). ES-First codifies that implicit process. |

## What Counts as an Executable Specification

An ES can be implemented through any combination of:

1. **Deterministic script** — shell, python, grep-based checker.
   Produces binary pass/fail from filesystem or output inspection.
2. **SDM-scored evaluation** — uses a Structured Decision Model to
   turn semantic or qualitative assessment into a quantitative score
   with a pass/fail threshold.
3. **Benchmark test case** — a `benchmark.sh` test with a checker
   function that validates model behavior against expected output
   patterns.

The key property is **executability** — the specification must be
runnable without human judgment. "Looks correct" is not an ES.
"grep finds pattern X in output" is.

## When to Apply

Apply ES-First when modifying:

- Benchmark checkers (`benchmark.sh` checker functions)
- AGENTS.md rules (via `seed-agents-md.sh`)
- AgentFS scripts (`post-write.sh`, `checkpoint.sh`, etc.)
- QOO schemas and scoring logic
- Skill behavioral logic (SKILL.md workflow steps backed by scripts)

Do NOT apply to:

- Documentation-only changes (prose, comments, READMEs)
- Memory writes (experiential, not testable)
- Knowledge bundle content (reference material, not executable)

## Origin

Derived from the qw14b-40k benchmark failure analysis (2026-10-31).
A weaker model called `search_nodes` with the wrong parameter name
(`keywords` instead of `query`). The existing benchmark checker
(`check_qoo`) only verified that `search_nodes` appeared in the
output — it could not detect that the call used wrong parameters.
The checker passed vacuously while the actual dispatch failed.

This gap was only discovered through manual session forensics. An
ES-First discipline would have required writing the improved checker
(that detects parameter errors) before implementing the rule prose
fix, and verifying the checker catches the known failure before
claiming it works.
