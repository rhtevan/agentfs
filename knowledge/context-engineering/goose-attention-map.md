---
type: Reference
title: Goose Turn-Message Attention Map
description: U-shaped attention analysis of Goose's per-turn message structure, with zone classifications and strategic placement guidance for rules, skills, and instructions
tags: [context-engineering, goose, attention, u-shape, primacy, recency, lost-in-the-middle, system-prompt]
timestamp: 2026-11-02T11:36:00-05:00
---

# Goose Turn-Message Attention Map

Mapping the empirically validated U-shaped attention curve onto
Goose's actual per-turn message structure. The goal: know exactly
where each piece of content lands in the attention landscape so
we can place critical instructions at high-attention positions.

## The U-Shape: Confirmed

The "lost in the middle" phenomenon is established science:

- **Liu et al. (TACL 2024)** — *"Lost in the Middle: How Language
  Models Use Long Contexts"* — performance degrades significantly
  when key information is in the middle of long contexts.
- **Hsieh et al. (ACL 2024)** — *"Found in the Middle: Calibrating
  Positional Attention Bias"* — LLMs exhibit a U-shaped attention
  distribution where tokens at the beginning and end receive higher
  attention regardless of relevance.
- **Wu et al. (ICML 2025)** — graph-theoretic analysis: the causal
  attention mask inherently biases toward earlier tokens in deeper
  layers (primacy), while RoPE positional encoding favors nearby
  tokens (recency).
- **arxiv 2508.07479 (2025)** — the lost-in-the-middle effect is
  strongest when inputs occupy up to 50% of context window; beyond
  that, primacy weakens but recency remains stable.

**Net effect:** The first ~10% and last ~10% of the context window
receive disproportionate attention. The middle 80% is attenuated.
This applies within a single system message AND across the full
messages array.

## Goose Per-Turn Message Structure

Every inference call from Goose produces this messages array:

```
messages: [
  [0]  role: system    — monolithic system prompt (~4,600 tokens)
  [1]  role: user      — user message + <turn-context>
  [2]  role: assistant  — model's tool call (content null)
  [3]  role: tool       — tool result
       ...repeating assistant/tool pairs...
  [N-1] role: user      — latest user message + <turn-context>    ← RECENCY EDGE
]
```

On Turn 1, the array is just `[system, user]`. On later turns,
it grows with conversation history.

## System Prompt Internal Layout (Measured)

From actual LLM request logs (`llm_request.*.jsonl`), the single
`role: system` message contains ~18,400 chars (~4,600 tokens)
assembled by `PromptManager.build_parts()`:

```
Position   Section                              ~Tokens  Pos%   Zone
─────────────────────────────────────────────────────────────────────
  0%       Goose identity                          40     0%    🟢 PRIMACY PEAK
  1%       # Turn Context                         170     1%    🟢 PRIMACY
  5%       # Response Guidelines                   16     5%    🟢 PRIMACY
  5%       # Additional Instructions (header)       7     5%    🟢 PRIMACY
  5-40%    # Skills (61 entries)                 1,600    5%    🟡 FADING PRIMACY
 40-47%    # Extensions (developer, KGM)          370   40%    🔴 DEAD ZONE
 47-48%    ### Project Hints (header)               36   47%    🔴 DEAD ZONE
 48-50%    # AGENTS.md header + SOUL.md import      90   48%    🔴 DEAD ZONE
 50%       ## Principles (SOUL.md)                 360   50%    🔴 DEAD ZONE CENTER
 58%       ## Rules (preamble)                      78   58%    🔴 DEAD ZONE
 59-67%    ### 1. Signal Dispatch                  375   59%    🔴 DEAD ZONE
 67-73%    ### 2. Pre-Flight                       232   67%    🔴 DEAD ZONE
 73-76%    ### 3. Session Canary                   138   73%    🔴 DEAD ZONE
 76-77%    ### 4. Conflict Resolution               76   76%    🟡 APPROACHING RECENCY
 77-81%    ### 5. Checkpoint                       155   77%    🟡 APPROACHING RECENCY
 81-85%    ### 6. Scope & Post-Write               202   81%    🟡 APPROACHING RECENCY
 85-90%    ## Signal Dispatch (table)              224   85%    🟢 RECENCY
 90-94%    ## Quick Orientation                    179   90%    🟢 RECENCY
 94-96%    ## Scope Definitions                     90   94%    🟢 RECENCY
 96-99%    ### What Lives Where                    143   96%    🟢 RECENCY PEAK
 99%       ## Agent Profiles                        53   99%    🟢 RECENCY PEAK
```

### Attention Zone Classification

| Zone | Position | Attention Weight | Color |
|------|----------|:---:|:---:|
| **Primacy Peak** | 0-5% | ★★★★★ | 🟢 |
| **Fading Primacy** | 5-40% | ★★★☆☆ | 🟡 |
| **Dead Zone** | 40-75% | ★☆☆☆☆ | 🔴 |
| **Approaching Recency** | 75-85% | ★★★☆☆ | 🟡 |
| **Recency Peak** | 85-100% | ★★★★★ | 🟢 |

## Where Things Actually Land

### Content that SHOULD get high attention but DOESN'T

| Content | Current Position | Zone | Impact |
|---------|:---:|:---:|--------|
| SOUL.md Principles | 50% | 🔴 Dead Zone | Agent identity drops on weak models |
| Rules preamble ("scan each rule's When clause") | 58% | 🔴 Dead Zone | Rule-scanning instruction itself is lost |
| **R1 Signal Dispatch** | 59-67% | 🔴 Dead Zone | Works because of deterministic plugin enforcement |
| **R2 Pre-Flight** | 67-73% | 🔴 Dead Zone | Works at 100% — task-triggered, not attention-dependent |
| **R3 Session Canary** | **73-76%** | **🔴 Dead Zone** | **60% on 14B — the failure we're fixing** |
| R4 Conflict Resolution | 76% | 🟡 Approaching | Rarely triggered, hard to measure |
| R5 Checkpoint | 77% | 🟡 Approaching | Rarely triggered |
| R6 Scope & Post-Write | 81% | 🟡 Approaching | Works because of deterministic plugin enforcement |

### Content that gets high attention but SHOULDN'T need it

| Content | Current Position | Zone | Actual Need |
|---------|:---:|:---:|--------|
| Skills list (61 entries) | 5-40% | 🟢🟡 Primacy | Low — only consulted on skill dispatch |
| Quick Orientation table | 90% | 🟢 Recency | Low — reference material |
| Scope Definitions table | 94% | 🟢 Recency | Low — reference material |
| What Lives Where table | 96% | 🟢 Recency Peak | Low — reference material |
| Agent Profiles table | 99% | 🟢 Recency Peak | Low — rarely referenced |

### Why R1 and R6 succeed despite the Dead Zone

R1 (Signal Dispatch) and R6 (Post-Write) both have **deterministic
plugin enforcement** via Goose hooks:
- `signal-dispatch` plugin: `PreToolUse` blocks non-`search_nodes`
  calls after `hey`, injecting a JIT reminder into the recency zone
- `post-write-enforce` plugin: `PreToolUse` blocks next tool call
  after `.agents/` write until `post-write.sh` runs

The plugins move these rules from prose-only enforcement (attention-
dependent) to deterministic enforcement (hook-based). The AGENTS.md
prose for R1 and R6 is still in the dead zone, but it doesn't
matter — the hook fires regardless.

### Why R3 (Canary) fails

R3 has **no enforcement hook and no task anchor**:
1. Position: 73% — deep in the dead zone
2. No tool call on Turn 1 — `PreToolUse` cannot intercept
3. No task complexity — `"hello"` activates a social greeting prior
4. No JIT reminder — no hook fires to push the rule into recency

Every other rule that works at >80% has either a hook or a task-
triggered anchor. R3 has neither.

## Full Turn-Level Attention Map (Multi-Turn)

On a multi-turn conversation with N messages:

```
Attention
  ▲
  █ ← system prompt (primacy peak: Goose identity, Turn Context)
  █
  ▓ ← skills list (fading primacy)
  ▒
  ░ ← extensions, KGM hints
  ░ ← AGENTS.md: SOUL, Principles, Rules  ← DEAD ZONE (all rules here)
  ░ ← AGENTS.md: Signal Dispatch table
  ▒ ← AGENTS.md: Reference tables (recency within system msg)
  ·
  · ← conversation history (prior turns — middle of full context)
  ·
  ░ ← assistant tool calls from 3 turns ago
  ░ ← tool results from 3 turns ago
  ░
  ▒ ← assistant tool calls from 2 turns ago
  ▒ ← tool results from 2 turns ago
  ▓
  ▓ ← assistant response from prior turn
  █ ← user message (current turn)        ← RECENCY PEAK
  █ ← <turn-context> block               ← RECENCY PEAK
  ▼
```

### Cross-Message Attention Dynamics

The U-shape applies at **two levels**:

1. **Within the system message** — the first and last sections of
   the ~4,600 token system prompt get more attention than the middle.
   The Rules block (tokens 2,600-3,800) is squarely in the dead zone
   of the system message.

2. **Across the full messages array** — the system message as a whole
   gets primacy attention, and the latest user message gets recency
   attention. Prior conversation turns in the middle get attenuated.
   On Turn 1, the U-shape is steep (only 2 messages). By Turn 20,
   the middle is enormous and the dead zone is vast.

## Strategic Placement Guidance

### 🟢 Primacy Zone (0-5% of system prompt) — Use For:

- **Forced-output rules** (canary, format requirements)
- **Identity assertions** that must survive social priors
- **One-line imperatives** that must fire on every turn

Currently occupied by: Goose identity, Turn Context instructions,
Response Guidelines. These are **Goose-owned** and not controllable
by AgentFS.

**Opportunity:** `system.md` is customizable via
`~/.config/goose/prompts/system.md`. A custom system.md can inject
a canary instruction at byte 0, before everything else.

**Trade-off:** This is a **Goose-specific** customization. It breaks
the agent-agnostic principle of AGENTS.md. But the U-shape makes
this the highest-impact placement for forced-output rules.

### 🟡 Fading Primacy Zone (5-40%) — Use For:

- **Reference material** that benefits from primacy (skill list)
- Content that needs to be seen but isn't time-critical

Currently occupied by: Skills list (61 entries, ~1,600 tokens).
This is a good fit — skills are consulted on-demand, and primacy
position helps discovery.

### 🔴 Dead Zone (40-75%) — Minimize What Goes Here:

- Everything in this zone needs **external enforcement** (hooks,
  plugins) or **task-triggered anchoring** (the rule fires only
  when the user's input naturally invokes it)
- Prose-only rules placed here will fail on weak models

Currently occupied by: Extensions, KGM hints, SOUL.md, all 6 rules.
This is the worst possible location for the rules that matter most.

### 🟡 Approaching Recency (75-85%) — Use For:

- **Less-critical rules** (Conflict Resolution, Checkpoint)
- **Contextual reference** that benefits from being near recency

### 🟢 Recency Zone (85-100% of system prompt) — Use For:

- **Signal dispatch table** (correctly placed — fires on every `hey`)
- **Quick reference tables** that the model may need immediately

Currently occupied by: Signal Dispatch table, Quick Orientation,
Scope Definitions, Agent Profiles. The Signal Dispatch table is
well-placed. The reference tables are wasting recency on low-value
content.

### 🟢 Recency Peak (user message) — Use For:

- **JIT reminders** injected via `UserPromptSubmit` hooks
- **Turn-context** (already correctly placed)
- **Task-specific instructions** from the user

This is the highest-attention position in the entire context and
is controlled by the user + hook system.

## Proposed R3 Canary Fix: Two-Layer Attention Strategy

### Layer 1: Primacy Injection (system.md customization)

Create `~/.config/goose/prompts/system.md` with a canary instruction
at the very top:

```markdown
You are a general-purpose AI agent called goose...

**Turn 1 rule: Start your FIRST response with `🐦 word-word` (random canary). Read `.agents/memories/USER.md`.**

{% raw %}{% if moim_system_prompt_block is defined %}{% endraw %}
...rest of template...
```

This places the canary instruction at the primacy peak (~0-1%)
instead of the dead zone (73%).

### Layer 2: Recency Injection (UserPromptSubmit hook)

A `UserPromptSubmit` hook detects Turn 1 and appends a reminder
to the user's message:

```
User types: "hello"
Hook appends: "\n\n[Per Rule 3: start with 🐦 word-word canary]"
```

This places the reminder at the recency peak — the last tokens
before generation.

### Combined Effect

| Layer | Zone | Position | Mechanism |
|-------|------|:---:|-----------|
| system.md canary line | Primacy Peak | 0-1% | Static — always present |
| UserPromptSubmit hook | Recency Peak | 100% | Dynamic — Turn 1 only |
| AGENTS.md Rule 3 | Dead Zone | 73% | Prose — anchor for self-audit |

The rule stays in AGENTS.md for self-audit and documentation, but
enforcement moves to both edges of the U-shape.

## Agent-Agnostic Trade-Off

The `system.md` customization is **Goose-specific**. It breaks the
pure agent-agnostic model where AGENTS.md is the sole instruction
surface. However:

1. The U-shape is an architectural reality of all transformer models
2. AGENTS.md alone cannot overcome positional attention bias
3. The effectiveness gain (60% → estimated 90%+) justifies the
   agent-specificity for the canary rule
4. AGENTS.md retains the canonical rule text for documentation,
   self-audit, and agents that don't have customizable system prompts

This is a **pragmatic concession**: use agent-specific placement
for enforcement, keep AGENTS.md for specification.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: R3 Canary Gap Analysis | Wire-level LLM request log analysis, section position mapping |
| context-eng | Session: R3 Canary Gap Analysis | Goose source: `prompt_manager.rs`, `load_hints.rs`, `system.md`, `openai.rs` |
| (external) | Liu et al. TACL 2024 | "Lost in the Middle: How Language Models Use Long Contexts" |
| (external) | Hsieh et al. ACL 2024 | "Found in the Middle: Calibrating Positional Attention Bias" |
| (external) | Wu et al. ICML 2025 | Graph-theoretic analysis of transformer positional biases |
| (external) | IntuitionLabs 2026 | "LLM Position Bias: Primacy and Recency Effects in Prompts" |
