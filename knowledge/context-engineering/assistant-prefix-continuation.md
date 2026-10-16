---
type: Lesson
title: Assistant Prefix as Continuation Framing
description: Empirical finding that assistant-role prefix messages shift the model from generation mode to continuation mode, improving forced-output rule compliance
tags: [context-engineering, assistant-prefill, continuation, canary, compliance, openai-api]
timestamp: 2026-10-16T02:55:00-04:00
---

# Assistant Prefix as Continuation Framing

Adding a partial `role: assistant` message before inference shifts
the model from generating a fresh response to continuing its own
prior output. This framing change empirically improves compliance
with forced-output rules.

## The Mechanism

Standard request (model generates from scratch):
```json
[
  {"role": "system", "content": "...rules including canary..."},
  {"role": "user",   "content": "hello"}
]
```

With assistant prefix (model continues from partial output):
```json
[
  {"role": "system",    "content": "...rules including canary..."},
  {"role": "user",      "content": "hello"},
  {"role": "assistant", "content": "This is turn 1. Per Session Canary rule, I must start with a 🐦 canary before anything else.\n\n🐦 "}
]
```

The model treats the assistant message as its own prior output
and continues from where it left off.

## Empirical Results

Tested against Qwen3-14B-FP8 on vLLM at `localhost:9000`, 40K
max context, fresh session with `"hello"` as user input:

| Configuration | Pass Rate | Runs |
|---------------|:---------:|:----:|
| Baseline (system + user only) | 81% (13/16) | 16 |
| With assistant prefix | 100% (16/16) | 16 |

## Why It Works

The assistant prefix does not mechanically force output. The model
must still cooperate. But the framing shift is significant:

| Property | Generation Mode | Continuation Mode |
|----------|:-:|:-:|
| Model's task | "Respond to the user" | "Continue what I was saying" |
| Pretraining prior | Social greeting for `hello` | Follow the established pattern |
| Rule checking | Optional — model may skip | Already done (the prefix references the rule) |
| Output starts with | Whatever the strongest prior produces | Whatever follows the prefix |

The prefix embeds the rule reference *in the model's own voice*.
The model reads it as something it already decided to do, not an
external instruction it must choose to follow.

## Important Caveat

This is NOT a mechanical guarantee. It is still a cooperative
mechanism:

- The model must treat `role: assistant` as its own prior output
  (most models do, but it depends on the chat template)
- The serving infrastructure must pass the partial assistant
  message through (vLLM does; some providers strip it)
- The model can still diverge from the prefix's intent

The correct framing: assistant prefix is **the most effective
cooperative mechanism** tested, but it is not deterministic
enforcement.

## Comparison with Other Approaches

| Approach | Where Injected | Compliance Rate | Deterministic? |
|----------|----------------|:-:|:-:|
| System prompt rule | `role: system` (~5K tokens in) | ~80% | No |
| JIT user-message reminder | `role: user` (appended) | Not tested | No |
| Assistant prefix | `role: assistant` (partial turn) | 100% (N=16) | No |
| PreToolUse hook block | `role: tool` (block reason) | High (for tool-call rules) | Yes (blocks the tool) |

## Current Limitation in Goose

Goose does not currently support assistant prefill. Every
`role: assistant` message in goose's request payload is a completed
prior model response. There is no mechanism to inject a partial
assistant turn before inference. Implementing this would require
changes to goose's provider abstraction layer.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: AgentFS Evolution | Direct curl testing against localhost:9000 — 16 baseline runs, 16 prefix runs |
| context-eng | Session: AgentFS Evolution | Analysis of why `/clear` restores compliance — continuation framing from administrative context |

## Implications

- For forced-output rules (canary, specific format requirements),
  assistant prefix is the most effective intervention available
  via the OpenAI API.
- The approach could generalize to any per-turn behavioral
  requirement: format enforcement, language constraints, role
  adherence.
- Goose would need to expose assistant prefill capability —
  either as a hook type or a provider-level configuration.
- The `developer` role (if supported by the model) could achieve
  similar priority separation without requiring prefill.
