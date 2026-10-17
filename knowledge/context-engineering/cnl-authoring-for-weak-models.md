---
type: Convention
title: CNL Authoring Rules for Weak Models
description: Controlled Natural Language principles applied to agent instruction authoring to improve compliance on weaker models
tags: [context-engineering, cnl, weak-models, authoring, agentfs, asd-ste100]
timestamp: 2026-10-16T02:55:00-04:00
---

# CNL Authoring Rules for Weak Models

AgentFS was developed and tested primarily with Claude Opus 4.6.
Weaker models (Granite 8B, Qwen3-14B) show degraded rule compliance
— not from misunderstanding rules, but from rules that require too
much parsing effort before the model can act on them.

Controlled Natural Language (CNL) principles — drawn from
ASD-STE100 (Simplified Technical English) — reduce parsing
ambiguity and lower the cognitive bar for instruction following.

## The Three Authoring Rules

These are codified in `skill-gen` SKILL.md Principle 1 checklist
(v3.7.1+) and the AGENTS.md rule format mandate in `design-spec.md`
(v7.3.5+).

### 1. One Instruction Per Sentence

Each sentence in a procedural step states exactly one action.

**Before (compound):**
> On session start, read `.agents/memories/USER.md` if it exists
> — apply preferences.

**After (split):**
> 1. Read `.agents/memories/USER.md`. Apply any preferences found.

Split sentences that contain "and", "then", or "also" into separate
lines. No compound instructions.

### 2. Active Imperative Voice

All action steps use active imperative mood.

| ❌ Avoid | ✅ Use |
|----------|--------|
| "The canary should be emitted" (passive) | "Write a random two-word canary" (imperative) |
| "You may want to call search_nodes" (modal hedging) | "Call search_nodes with the keywords" (direct) |
| "A plan needs to be stated" (passive) | "State what you will do" (imperative) |

### 3. Single Vocabulary

One term per concept throughout a skill or rule set. Do not mix
synonyms.

| ❌ Mixed | ✅ Consistent |
|----------|--------------|
| rules / guardrails | rules |
| emit / produce / generate | write |
| session / conversation | session |
| Session begins / session start / turn 1 | Turn 1 |

## Structural Rule: Numbered Do: Blocks

When an AGENTS.md rule's `Do:` block contains two or more distinct
actions, express them as a numbered list. No multi-action prose
paragraphs.

**Before:**
```markdown
**Do:** On session start, read USER.md if it exists — apply
preferences. Start your response with a random two-word canary.
The canary is ephemeral — do not write it anywhere. Re-verify
every 10 turns.
```

**After:**
```markdown
**Do:**
1. Read `.agents/memories/USER.md`. Apply any preferences found.
2. Write a random two-word canary at the top of your response.
   Use this format: `🐦 word-word` (example: `🐦 cobalt-heron`).
3. Keep the canary in memory for this session. Do not write it
   to any file.
4. On every 10th turn and after every compaction: re-read
   `MEMORY.md` and `USER.md`. Run a silent self-check against
   all rules. Report only if you find a violation.
```

## What CNL Fixes vs. What It Doesn't

| CNL Fixes | CNL Does Not Fix |
|-----------|------------------|
| Ambiguous instructions with multiple valid readings | Attention degradation at context depth |
| Synonyms that split the model's probability mass | Generation prior conflicts (e.g., social greeting overriding canary rule) |
| Complex sentences with embedded conditionals | Competing priors from pretraining |
| Hedging language that weakens imperative force | Model executing instructions it understands but doesn't attend to |

CNL is a parsing intervention. Generation prior conflicts require
structural interventions (hooks, prefill, role separation).

## Where to Apply (Priority Order)

| Priority | Target | Rationale |
|----------|--------|-----------|
| High | AGENTS.md rules with known failure rates | Direct measurable impact on compliance |
| High | SKILL.md procedural steps | Weaker models over-tool when prose is ambiguous |
| Medium | SOUL.md principles | Already close to CNL; structured bullet format helps |
| Low | Memory files, logs | Agent-authored; model is reader and writer |

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: AgentFS Evolution | Analysis of Session Canary rule failure on Qwen3-14B; CNL rewrite of rule 4; codification in skill-gen v3.7.1 and design-spec v7.3.5 |
| context-eng | Session: AgentFS Evolution | ASD-STE100 assessment: full compliance adds 20-40% token overhead; selective application recommended |
| goofing-around | Session: Test qw14b-40k | Baseline violation data showing the prose rule was parseable but not acted on |

## v7.3.7 Full Template Rewrite (2026-10-16)

All 7 PROJECT scope rules and 3 LITE scope rules in `seed-agents-md.sh`
rewritten for CNL compliance:
- Circled-number format (①②③) replaced with numbered lists
- Compound instructions split (6 instances across rules 2, 3, 5, 7)
- Passive voice converted to active imperative (rule 7)
- Synonym mixing eliminated (rule 7: "mature" → "graduate")
- Blank line between `**When:**` and `**Do:**` standardized (all 7 rules)
- Signal Dispatch rule (rule 1) given `**Do:**` header and blank-line format

Net result: ~15% more lines in rules section. All rules follow consistent
`When: / Do:` + numbered list format. Template version 7.3.7.

## Implications

- CNL is a necessary but insufficient condition for weak-model
  compliance. Apply it first, then layer structural enforcement
  (MCASC principles — see `agentfs-engineering-evolution` bundle).
- The `skill check` procedure (skill-gen Principle 1) now audits
  for these three rules mechanically.
- Token cost tradeoff: CNL may increase total token count (more
  sentences). The benefit is higher per-sentence compliance.
  Measure with behavioral tests at multiple context depths.
