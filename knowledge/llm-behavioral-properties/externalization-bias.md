# Externalization Bias

## Observable Behavior

When asked to fix a behavioral failure, models propose tooling
solutions (scripts, hooks, checks) rather than acknowledging
the fix is "follow the existing rule." The model externalizes
responsibility for compliance into infrastructure.

## Evidence

Granite 8B, asked "how to implement the fix for missing canary,"
produced a bash script with `shuf`, a curated list of canary
names, and a grep-based detection mechanism — none of which
would work. The actual fix was: follow Rule 4 as written.

The model also checked `log.md` for prior agent responses
(log.md records file changes, not conversation turns) and
proposed storing canary state in MEMORY.md (which the rule
explicitly forbids).

## Root Cause

Models are trained to be helpful by producing actionable output.
"Just follow the rule" feels like a non-answer. The model
generates plausible-looking infrastructure because that feels
like "implementing a fix." This is compounded by the model not
having a reliable self-model — it cannot introspect on WHY it
failed to follow the rule, only that it did.

## AgentFS Mitigations

| Layer | Mitigation |
|-------|-----------|
| **Instruction** | Write rules as unambiguous formatting directives — "start your response with X" leaves no room for the model to propose alternative mechanisms |
| **Plugin** | Deterministic enforcement (signal-dispatch plugin) catches behavioral failures at runtime — the model doesn't need to build its own enforcement |
| **Skill design** | Push deterministic logic into scripts, not prose — if compliance can be verified by a script, the model doesn't need to self-enforce |

## Implications for Skill Design

- When a model fails to follow prose instructions, the fix is
  better prose — not additional tooling the model also has to
  follow
- A model that can't follow Rule 4 as written will not reliably
  execute a script it wrote to enforce Rule 4
- Exception: plugin-level enforcement (PreToolUse hooks) works
  because it's external to the model's generation — the model
  cannot bypass it
