---
type: Pattern
title: Fail-Open Hook Design
description: Design rules for agent-runtime hooks that remind without locking a session — block at most once, enforce only on confirmed dependencies, leave compliance to the model
tags: [context-engineering, hooks, plugins, fail-open, jit-reminder, goose, reliability]
timestamp: 2026-11-19T21:31:00-05:00
---

# Fail-Open Hook Design

A [JIT-reminder hook](jit-reminder-recency-pattern.md) blocks a tool call
and uses the block reason as a recency-zone reminder. On a weak model it
measurably raises compliance (Pre-Flight rule: 3/12 → 12/12 on a T2 model).
But a hook that blocks wrongly, or more than once, costs more than the rule
it enforces: it can stall every turn or lock the session outright.

**Principle:** a hook is a reminder, not a gate. It must never be the reason
a session cannot make progress. When the hook cannot tell whether a block is
correct, it allows.

## Design Rules

| # | Rule | Failure it prevents |
|---|------|---------------------|
| 1 | **Block at most once** per trigger, then clear the flag *inside the blocking hook* | Lockout when the clearing event never fires |
| 2 | **Never depend on a follow-up event to unblock** | `AfterShellExecution`-style events fire only on *success*; a chained command that exits non-zero (`post-write.sh && grep -c x` with 0 matches) leaves the flag set forever |
| 3 | **Enforce only when every dependency is confirmed** (e.g. the extension the reminder points to is enabled in config) | Dead end: the reminder demands a tool that does not exist |
| 4 | **Treat state the hook cannot see as absent** | A per-session extension enable is invisible to hooks (config still says `enabled: false`) → the hook stays inactive; the model follows the prose rule |
| 5 | **Count the user's next reply after a hold as approval** | Re-arm loop: the runtime tells the model "do not retry", the model stops and asks, the user approves, the next prompt re-arms, the approved change is blocked again |
| 6 | **Recognise approval leniently, with a negation guard**: exact short words (`yes`, `go`), option picks (`A`, `option 2`), 2–3 word replies ending in one (`fix + go`) — but not `no go`, `don't go` | Holding a change the user already approved |
| 7 | **Build block JSON with `jq`**, never by string interpolation | Invalid JSON (backslashes, tabs in user text) → runtime sees no decision |
| 8 | **Classify read-only commands on the text with quotes hidden**; skip shell keywords (`for`, `do`, `done`) | `rg "a\|b"` split on the quoted pipe → misread as mutating → the one-shot block is wasted on a read |
| 9 | **Misclassification must err toward allowing** | A missed reminder costs one rule miss; a false block costs a turn |

## Goose Runtime Facts (1.60.1)

| Fact | Consequence |
|------|-------------|
| Only `PreToolUse` and `Stop` can block | No non-blocking context injection from a pre-tool hook |
| Every denial is wrapped: *"Tool call denied by policy hook `<plugin>`: <reason>. Do not retry; this is a policy denial, not a transient failure."* — fixed, not configurable | A reason saying "retry in this same turn" contradicts the wrapper; obedient models stop. Design for the stop (rule 5) |
| `on_failure: allow` is the default | A crashing hook already fails open; keep it |
| Hook `matcher` is an unanchored regex; omitted = all events | Anchor it (`^write$`) when the event should be narrow |

## Derived From

| Plugin | Incident | Fix |
|--------|----------|-----|
| `preflight-reminder` | Re-arm loop under the "Do not retry" wrapper; quoted `\|` misread as mutating; `A` / `fix + go` approvals not recognised | Rules 5, 6, 8 (1.2.0 → 1.3.2) |
| `post-write-enforce` | Session lockout: flag cleared only by a successful `post-write.sh` shell event | Rules 1, 2 (1.3.0) — 0 denials in 161 benchmark runs, so blocking once loses nothing |
| `signal-dispatch` | Dead end when the KGM extension was absent; invalid JSON on special characters; `note ` matching `notebook` | Rules 3, 4, 7 (2.4.0) |

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: first fresh Goose AgentFS setup (2026-11-19) | Three plugins debugged live; fixes shipped in `~/.agents` commits 62f62c2, 26caa24 |

## Implications

- Ship hooks only for rules with **measured** benefit at the target model
  tier; a hook with no measured gain is pure risk (post-write-enforce kept
  only because block-once makes it harmless).
- Test hooks against the **runtime's wording**, not the hook's own: the
  wrapper text decides what the model does next.
- Rule compliance beyond the one reminder is the model's job. Strong models
  (T3/T4) need no hook; weak models get one nudge, never a cage.
