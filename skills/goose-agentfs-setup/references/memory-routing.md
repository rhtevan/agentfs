# Goose Memory Routing Override (AgentFS)

This file contains the full Goose-specific memory signal routing table.
It is loaded on-demand when Cognee, Memory, or Chat Recall tools are
detected in the current session.

## Runtime Resolution Rule

This table is STATIC — it lists all possible routes regardless of which
extensions are currently enabled. Resolve dynamically at runtime:

1. For each matching signal, check the "Tool to Check" column
2. If that tool EXISTS in your current available tools list, use it
3. If the tool DOES NOT exist (extension disabled), skip that row and
   try the next priority
4. If NO Goose-specific tool matches, fall through to AGENTS.md
   Guardrail #2 (Memory Scope & Signal Routing)

Tool existence = extension enabled. Goose only injects tools into the
session when their parent extension is active.

## Goose Memory Signal Decision Table

| Pri | Signal / Keyword | Intent | Tool to Check | Route To (Tool Call) | Extension |
|---|---|---|---|---|---|
| 1 | "remember this document", "learn this", "ingest this", "add to knowledge" | Knowledge graph ingestion | cognee__remember | cognee__remember(data, dataset_name) | Cognee |
| 1 | "remember for this session only", "session note" | Session-scoped fast cache | cognee__remember | cognee__remember(data, session_id) | Cognee |
| 1 | "remember this", "note that", "save this", "keep in mind" | Store persistent memory (fact/observation) | cognee__remember | cognee__remember(data, dataset_name) | Cognee |
| 1 | "what do you know about X", "what connections exist", "search knowledge" | Knowledge graph query | cognee__recall | cognee__recall(query) | Cognee |
| 1 | "forget dataset", "clear knowledge base" | Delete knowledge graph data | cognee__forget | cognee__forget(dataset) | Cognee |
| 1 | "forget this", "remove that note" | Remove specific memory | cognee__forget | cognee__forget(dataset) | Cognee |
| 2 | "remember this", "note that", "save this", "keep in mind" | Store persistent memory | memory__remember_memory | memory__remember_memory(category, data, tags, is_global) | Memory |
| 2 | "retrieve my notes about", "what did I save about" | Retrieve stored memories | memory__retrieve_memories | memory__retrieve_memories(category, is_global) | Memory |
| 2 | "forget this memory", "remove memory about" | Remove specific memory | memory__remove_specific_memory | memory__remove_specific_memory(category, content, is_global) | Memory |
| 2 | "forget all memories", "clear all notes" | Bulk memory delete | memory__remove_memory_category | memory__remove_memory_category(category="*", is_global) | Memory |
| 3 | "what did we discuss", "last time we talked about", "previous session" | Past conversation search | chatrecall | chatrecall(query) | Chat Recall |
| 3 | "load session", "show me session X" | Session summary | chatrecall | chatrecall(session_id) | Chat Recall |

## Priority Rationale

| Priority | Extension | Rationale |
|---|---|---|
| 1 (highest) | Cognee | Knowledge graph with semantic search — subsumes Memory when enabled |
| 2 | Memory | Simple persistent .txt storage — fallback when Cognee unavailable |
| 3 | Chat Recall | Past session search — unique capability, no storage overlap |

When Cognee is enabled, it effectively renders the Memory extension redundant
for storage signals. This is intentional — Cognee provides a superset of
Memory capabilities. Users who enable Cognee should consider disabling Memory.

## Which MEMORY.md to use (AGENTS.md fallthrough)

When no Goose-specific tool matches and signals fall through to AGENTS.md:
- Default agent: ./.agents/memories/MEMORY.md
- Named profile (subagent): ./.agents/profiles/<name>/memories/MEMORY.md
- If operating as a subagent under a named profile, ALWAYS use that profile MEMORY.md

## Ambiguity Resolution

When "forget" intent is ambiguous and lacks a clear object (dataset, memory,
note), ask the user: "Do you want me to forget a specific saved memory,
clear a knowledge base dataset, or just disregard what was just said?"

When routing a memory signal, briefly state which system you are routing to
and why (e.g., "Routing to Cognee remember because cognee__remember is
available") before executing.

## Session bridge pattern

The primary legitimate use of the Goose memory extension alongside AgentFS is as
a session bridge: temporarily stash critical context so it survives into a new
session, then at session start, retrieve the stashed content and commit it to
the appropriate MEMORY.md file. After committing, clear the stashed entries from
the Goose memory store.
