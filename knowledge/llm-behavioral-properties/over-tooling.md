# Over-Tooling

## Observable Behavior

Weaker models default to tool calls for tasks that stronger
models solve in pure reasoning. Given a task that requires
reviewing 3 conversation turns, an 8B model makes 14 tool
calls (reading files, running Python scripts, querying git)
instead of reasoning over content already in context.

## Evidence

Granite 8B, running `agentfs-violation-chk` on a 3-turn session:
- Read SOUL.md twice (already in system prompt)
- Ran `find` to locate AGENTS.md (already in system prompt)
- Read MEMORY.md and USER.md (reasonable)
- Ran `git log` (reasonable for behavioral evidence)
- Wrote 4 Python scripts attempting to programmatically audit
  the conversation — unnecessary and incorrect approach
- Total: 14 tool calls, ~15 minutes elapsed

A stronger model completes the same violation check in one
thinking block with 0 tool calls — the conversation is already
in context.

## Root Cause

Weaker models have limited working memory for multi-step
reasoning. When a task requires holding several pieces of
information (7 rules, 8 principles, 3 conversation turns)
and cross-referencing them, the model offloads to tools as a
form of external memory. Each tool call retrieves one piece
of information the model couldn't hold in its reasoning buffer.

## AgentFS Mitigations

| Layer | Mitigation |
|-------|-----------|
| **Skill design** | Push complex logic into scripts, not prose. If a violation check can be partially automated (`skill-check.sh` for P1-P7), do so — reduce the reasoning load on the model |
| **Instruction** | Keep procedures short. 3 steps with scripts > 6 steps with prose. Each prose step is a potential over-tooling point |
| **Template** | AGENTS.md rules should be self-contained — each rule's trigger and action in one paragraph. Cross-referencing between rules ("see Rule 3") is acceptable only when there's a causal link (Pre-Flight → Post-Write) |

## Implications for Skill Design

- Skills targeting broad model compatibility should minimize
  prose reasoning steps and maximize script delegation
- The `agentfs-violation-chk` skill could benefit from a
  partial-automation script that collects the evidence
  (conversation turns, rules list, file state) and presents
  it in a structured format — reducing the reasoning step to
  classification only
- Complexity thresholds: if a procedure has >5 prose steps,
  consider whether a wrapper script could reduce it to 1-2
  script calls + 1-2 reasoning steps
