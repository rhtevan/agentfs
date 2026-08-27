---
title: Context Window Requirements for AgentFS
created: 2026-08-04
tags: [agentfs, context-window, llm, agent, requirements]
---

# Context Window Requirements for AgentFS

AgentFS loads several context files at session start. These consume a
significant portion of the model's context window before any user
interaction begins. This document establishes minimum context window
requirements for AgentFS-compatible LLM backends.

## AgentFS Context Overhead

| File | Typical Size | Tokens (~) |
|------|-------------|:----------:|
| `AGENTS.md` (full, with guardrails) | ~8 KB | 2,500–3,500 |
| `SOUL.md` | ~1 KB | ~300 |
| `memories/MEMORY.md` | ~1–4 KB | 300–1,200 |
| `memories/USER.md` | ~0.5–2 KB | 150–600 |
| `~/.agents/skills/index.md` | ~4–6 KB | 1,200–1,800 |
| Cross-agent files (`CLAUDE.md`, etc.) | ~0.5–2 KB | 150–600 |
| **Total AgentFS overhead** | | **~4,500–8,000** |

## Context Window Compatibility

| Context Window | PROJECT Scope | LITE Scope | Notes |
|:--------------:|:-------------------:|:---:|-------|
| 2K | ❌ No | ❌ No | Even LITE AGENTS.md (~850 tokens) leaves no room |
| 4K | ❌ No | ⚠️ Barely | LITE fits but tight for conversation |
| 8K | ⚠️ Barely | ✅ Comfortable | LITE leaves ~7K for interaction |
| **16K** | ✅ **Minimum practical** | ✅ Ideal for LITE | LITE uses ~5% of context vs ~23% for PROJECT |
| 32K | ✅ Comfortable | ✅ | Full AgentFS + multi-turn + tool calling |
| 128K+ | ✅ Ideal | ✅ | Full AgentFS + RAG + complex agent workflows |

## Implications for Model Selection

- Models with ≤ 4K context (e.g., older LLaMA, some quantized models)
  **cannot serve as AgentFS backbone**
- Models with 16K+ context are the minimum for practical AgentFS use
- For RAG-heavy workflows, 32K+ is recommended
- The context budget for user conversation is:
  `available = model_context - agentfs_overhead`

## Example Budget (16K context)

| Allocation | Tokens |
|-----------|:------:|
| AgentFS overhead | ~6,000 |
| System prompt / instructions | ~1,000 |
| **Available for conversation** | **~9,000** |
| Multi-turn chat (5-6 turns) | ~6,000 |
| Tool call schemas | ~1,000 |
| **Remaining headroom** | **~2,000** |

## Recommendations

1. **16K minimum** for single-user interactive chat with AgentFS
2. **32K recommended** for tool-calling agents with moderate memory
3. **128K ideal** for RAG, long documents, or complex multi-step workflows
4. Keep skills index lean — each skill entry costs ~40 tokens
5. Prune `MEMORY.md` regularly — graduate to knowledge bundles

## Source

Derived from token analysis of AgentFS context files across multiple
projects, validated against `granite-4.1-8b` (128K native, 16K deployed)
and `granite-4.0-1b` (2K context — insufficient for AgentFS).
