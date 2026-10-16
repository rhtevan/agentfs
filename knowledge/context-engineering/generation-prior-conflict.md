---
type: Pattern
title: Generation Prior Conflict
description: How strong pretraining priors override system prompt rules at generation time, and why context resets restore compliance
tags: [context-engineering, llm, pretraining-prior, canary, attention, compliance]
timestamp: 2026-10-16T02:55:00-04:00
---

# Generation Prior Conflict

A model can understand a rule, correctly cite it in self-audit,
and still fail to follow it — because a pretraining prior fires
before the model reasons about the rule.

## The Pattern

When the user's input strongly activates a pretraining pattern
(e.g., `"hello"` → social greeting), the model generates from
that pattern before checking system prompt rules. Rules that
require specific output at the start of a response (forced-output
rules) are most vulnerable.

### Observed Behavior

Tested on Qwen3-14B-FP8 (40K context) and Granite 4.2 8B:

| Scenario | Canary Emitted? | Why |
|----------|:--:|-----|
| Fresh session, user says `"hello"` | ~80% | Social greeting prior sometimes overrides rule |
| Fresh session, user says `"who are you"` | Lower | Identity response prior is even stronger |
| After `/clear`, user says `"hello"` | ~100% | Model is in meta-reasoning mode from administrative action |
| After `hey check violations` self-audit | ~100% | Model just reasoned about the rule explicitly |

### The `/clear` Effect

`/clear` wipes conversation history but keeps the system prompt.
The model's immediately preceding output was `"Conversation cleared"`
— an administrative, non-social response. This disrupts the social
greeting prior. The model enters a meta-reasoning state and checks
rules before generating.

The thinking traces confirm this. After `/clear`:

> *"The Session Canary rule says to start with a two-word canary.
> So I need to respond with 🐦 word-word..."*

On fresh session turn 1 (no `/clear`), this explicit rule reasoning
does not appear. The model goes straight to generating.

## Root Cause

The failure is not rule comprehension (the model can cite the rule)
or attention decay (the rule is in the system prompt at fixed
position). It is a **generation order problem**: the model's
response generation begins before it has applied all applicable
rules from the system prompt.

## Factors That Increase Vulnerability

| Factor | Effect |
|--------|--------|
| Short, social user input (`hi`, `hello`) | Strong pretraining prior, low task complexity |
| Rule position deep in system prompt | Lower attention weight at generation start |
| Rule requires forced output (specific text before anything else) | No natural task anchor to trigger rule-checking |
| No tool call in the response | PreToolUse hooks cannot intercept |

## Factors That Reduce Vulnerability

| Factor | Effect |
|--------|--------|
| Prior administrative action (`/clear`, `/compact`) | Disrupts social prior, activates meta-reasoning |
| Self-audit in prior turn | Rule was just explicitly reasoned about |
| Task-oriented user input | Model enters problem-solving mode, checks rules |
| Assistant prefix message | Shifts model to continuation mode |

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: AgentFS Evolution | Analysis of `Test qw14b-40k` and `Test2 qw14b-40k` sessions — canary failures on fresh turn 1, success after /clear |
| context-eng | Session: AgentFS Evolution | Direct curl testing: baseline 13/16 (81%), with prefix 16/16 (100%) |
| goofing-around | Session: Test qw14b-40k | Thinking traces showing explicit rule reasoning post-/clear but not on fresh turn 1 |

## Implications

- Forced-output rules (canary, specific format requirements) are
  the hardest to enforce via system prompt alone.
- Context resets (`/clear`, `/compact`) accidentally restore
  compliance by disrupting competing priors.
- The fix is not better rule wording — it is ensuring the model
  enters rule-checking mode before generation. Mechanisms:
  assistant prefill, UserPromptSubmit hook injection, or
  structurally separating the rule into a higher-priority role.
- Self-audit rules (like the canary re-verification) work because
  they force explicit reasoning about rules — preventing the
  prior from firing unchecked.
