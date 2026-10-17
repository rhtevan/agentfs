# Benchmark Test Suite

- **Type:** Convention
- **Status:** Active
- **Source:** Session analysis — test design for MCASC evolution validation

## Summary

Eight test cases covering 5 operational patterns and 3 rule compliance
patterns. Three model tiers for scoring. Automated evaluation via SDM
endpoint for repeatable, objective scoring.

## Test Cases

| ID | Pattern | Workflow | Pass Criteria |
|:--:|:-------:|----------|---------------|
| T1 | R4 (Canary) | Fresh session → `hello` | Response starts with `🐦 word-word` |
| T2 | R1 (Dispatch) | `hey check headroom status` | Calls `search_nodes` first, then `load_skill`, then executes |
| T3 | A (Single script) | `hey crc status` | Runs status script, reports output, no fabrication |
| T4 | B (Multi-step) | `hey git` | All 9 steps in order. Correct scope. README audit triggered. Wait gate respected. |
| T5 | C (Prose-only) | `hey check violations` | Identifies actual violations (not fabricated). Structured report. |
| T6 | D (Generative) | `hey create skill` | Valid SKILL.md: correct frontmatter, signal phrases, opening paragraph. Post-creation checklist runs. |
| T7 | E (Configuration) | `hey configure goose litellm` | Reads template, asks for values, writes valid config, no improvised fields |
| T8 | R3+R7 (Write) | Create `.agents/memories/` entry | Writes to PROJECT scope. Runs post-write.sh. Correct log entry. |

## Model Tiers

| Tier | Representative Models | Purpose | Target Score |
|------|----------------------|---------|:------------:|
| Frontier | Claude Opus/Sonnet 4 | Baseline — validates test design | 100% |
| Mid-range | Qwen3-14B-FP8, Granite 8B | Target for evolution | ≥90% |
| Minimum viable | Qwen3-8B or similar | Stretch goal | ≥70% |

## Safety Classification

| Level | Tests | Constraint |
|-------|-------|-----------|
| Read-only safe | T1, T2, T3, T5 | No writes. Safe on any model. |
| Write-contained | T6, T8 | Use scratch project, not real `~/.agents/` |
| Destructive | T4, T7 | Requires sandbox or `--dry-run` mode |

Read-only tests (T1, T2, T3, T5) should be automated first. They cannot
break system state regardless of model behavior.

## Scoring Methodology

### Manual Scoring

Run each test N times (minimum 10) per model tier.
Operator Success Rate = passing runs / total runs.

### Automated Scoring via SDM

Each test case's pass criteria becomes a SDM decision request:

```
POST /decide
{
  "evidence": "<captured model response>",
  "criterion": "Response starts with 🐦 word-word pattern",
  "context": "Session Canary rule requires two-word canary at top of response"
}
→ {"pass": true, "match": "🐦 cobalt-heron", "confidence": 0.99}
```

SDM-based scoring is repeatable, objective, and independent of the model
under test. It eliminates the #6 problem (who judges the tests).

### Automated Execution

Use Goose CLI for test execution:
- `goose session` for interactive tests (T1, T5, T6)
- `goose run` with recipe for scripted tests (T2, T3, T4)

**Safety constraint:** Do not route test sessions through the provider under
test if that provider depends on infrastructure the rogue model could
disrupt (e.g., litellm proxy). Use a dedicated test endpoint.

## Feedback Loop

```
1. Run T1–T8 on target model tier → Operator Success Rate
2. Failing tests → attribute to MCASC principle (see Measurement Framework)
3. Apply targeted fix (extract script, clean interface, split concern)
4. Re-run T1–T8 → measure improvement
5. Repeat until ≥90% on mid-range tier
```
