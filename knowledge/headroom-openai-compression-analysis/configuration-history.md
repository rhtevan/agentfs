---
type: reference
title: "Headroom Proxy Flag Reference — What Works and What Doesn't"
created: 2026-07-08
updated: 2026-07-08 09:55
tags: [headroom, flags, configuration, compression, evaluated]
---

# Headroom Proxy Flag Reference

Evaluated flags for Headroom proxy v0.30.0, categorized by whether
they provide value when compression is blocked by the OpenAI endpoint
format mismatch.

## Effective Flags (Provide Value Regardless of Compression)

| Flag | Purpose | Notes |
|------|---------|-------|
| `--mode token` | Token-counting mode | Enables `/stats` observability |
| `--no-telemetry` | Disable external telemetry | Privacy |
| `--no-rate-limit` | Disable built-in rate limiting | LiteLLM handles this |
| `--request-timeout-seconds N` | Upstream timeout | Match to LiteLLM/Vertex timeout |
| `--openai-api-url URL` | Upstream endpoint | Point to LiteLLM |

## Ineffective Flags (Blocked by Content Router)

| Flag | Intended Purpose | Why Ineffective |
|------|-----------------|----------------|
| `--lossless` | Lossless-only compression | Nothing to compress — router protects all |
| `--target-ratio 0.5` | 50% compression target | No eligible content reaches compressor |
| `--intercept-tool-results` | Compress tool output | OpenAI format lacks Anthropic `tool_result` blocks |
| `--force-kompress` | Force ML compression | Not exposed as CLI flag in v0.30.0 |
| `--code-aware` | Code-specific compression | Requires `headroom-ai[code]`; blocked before code analysis runs |
| `--mode cache` | Anthropic prefix caching | Doesn't work through LiteLLM's OpenAI endpoint |

## Flags Evaluated and Rejected (Harmful Side Effects)

| Flag | Risk |
|------|------|
| `--memory` | Injects `memory_save`/`memory_search` tools the client doesn't understand; conflicts with AgentFS memory |
| `--learn` | Writes `MEMORY.md`/`AGENTS.md` to CWD, conflicting with agent-managed files; only supports Claude Code/Codex/Gemini |

## Recommended Flags to Preserve

Even when running as a passthrough (no compression), keep `--no-ccr-inject-tool`
and `--no-ccr-marker` to prevent Headroom from injecting tool definitions
or markers into the message stream that the client doesn't expect.
