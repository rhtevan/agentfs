---
type: Reference
title: Goose Message Role Mapping
description: How Goose maps its internal concepts to OpenAI Chat Completions API message roles
tags: [context-engineering, goose, openai-api, message-roles, system-prompt]
timestamp: 2026-10-16T02:55:00-04:00
---

# Goose Message Role Mapping

Goose sends requests to the model using the OpenAI Chat Completions
API format. It uses exactly four of the five available API roles.

## Wire Format

```
messages: [
  { role: "system",    content: "<monolithic system prompt>" },
  { role: "user",      content: "<user message + turn-context>" },
  { role: "assistant", content: null | "<text>" },
  { role: "tool",      content: "<result>", tool_call_id: "..." },
  ...repeating assistant/tool pairs...
]
```

## Role Mapping

| API Role | What Goose Puts In It |
|----------|----------------------|
| `system` | Single monolithic message: goose identity + turn-context instructions + extension instructions (developer, knowledgegraphmemory) + skills list (61 entries) + AGENTS.md + SOUL.md content. ~19K chars total. |
| `user` | User message concatenated with `<turn-context>` block (timestamp, working directory, compaction status). One message per user turn. |
| `assistant` | Model's prior response. Content is `null` when the model made a tool call; text when it responded to the user. |
| `tool` | Tool execution result. Linked to the assistant's tool call via `tool_call_id`. |

## Roles NOT Used

| API Role | Status | Impact |
|----------|--------|--------|
| `developer` | Not used | No separation between platform instructions and project instructions. Everything is in one `system` message. |
| `assistant` (prefill) | Not used | Goose never sends a partial assistant message to seed the model's response. Every assistant message is a completed prior turn. |
| Multiple `system` messages | Not used | All context is concatenated into a single system string. |

## System Prompt Internal Structure

Within the single `system` message, content is ordered:

```
1. Goose identity ("You are goose...")           ~500 chars
2. Turn Context instructions                      ~300 chars
3. Extension instructions (developer, KGM)       ~2,000 chars
4. Skills list (61 entries)                       ~1,100 tokens
5. AGENTS.md (rules, dispatch table, profiles)   ~3,750 tokens
6. KGM Project Hints (inlines AGENTS.md again)   variable
```

AGENTS.md content — including all operational rules — lands at
position 5, after ~4,000+ tokens of platform content.

## Implications

- The Session Canary rule (rule 4 of 8 in AGENTS.md) sits ~5,000+
  tokens into the system prompt. It competes with platform
  instructions for attention.
- No structural separation exists between "must always do" rules
  and general context. Everything is flat text in one message.
- The `developer` role could separate platform rules from project
  rules, but goose does not use it.
- Assistant prefill could force output patterns (like the canary),
  but goose does not support it.
- Any hook-based intervention can only modify the `user` message
  (via UserPromptSubmit) or block tools (via PreToolUse). No hook
  type exists to modify the system prompt or prefill the assistant
  response.

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| context-eng | Session: AgentFS Evolution | Direct inspection of `~/.local/state/goose/logs/llm_request.*.jsonl` — raw API payloads |
| context-eng | Session: AgentFS Evolution | Goose docs: `https://goose-docs.ai/docs/guides/logs` — LLM request log format |
