---
type: analysis
title: "OpenAI-Compatible Endpoints Block LLM Proxy Compression"
created: 2026-07-08
updated: 2026-07-08 09:55
tags: [headroom, compression, openai, content-routing, proxy, architectural-mismatch]
---

# OpenAI-Compatible Endpoints Block LLM Proxy Compression

LLM compression proxies (e.g., Headroom) that sit between a client and
an upstream API can achieve zero compression when the client uses the
OpenAI-compatible `/v1/chat/completions` format instead of the
Anthropic Messages API.

## The Architectural Mismatch

Compression proxies identify compressible content by classifying
message types:

| Anthropic Messages API | OpenAI Chat Completions |
|------------------------|------------------------|
| Structured `tool_result` blocks with `tool_use_id` → compressible | Tool results embedded in flat `user`/`assistant` text → invisible |
| Typed message roles (`tool_result`, `tool_use`) → rich routing | Only `system`/`user`/`assistant` roles → limited routing |
| Older assistant turns → eligible for compression | All `user` messages → protected by content router |

The content router classifies everything as `user_msg` and **protects
it from compression**. This is by design — the router cannot
distinguish tool output from user prose in a flat message stream.

## Why Configuration Cannot Fix This

The bottleneck is the **content router classification**, not the
compression parameters:

| Flag | Expected Effect | Why It Fails |
|------|----------------|-------------|
| Remove `--lossless` | Enable ML compression | Router still protects all content |
| `--target-ratio 0.5` | Set compression target | No content is eligible to compress |
| `--intercept-tool-results` | Compress tool output | Looks for Anthropic-style blocks that don't exist |

## Key Insight

Clients that embed tool results inside regular messages (OpenAI format)
make those results invisible to compression proxies that expect
structured `tool_result` blocks (Anthropic format). The two formats
are fundamentally incompatible for compression purposes.

## Measured Impact

- 70 tokens saved across 692 requests (~$0.00 of $98.82 input cost)
- Proxy overhead: ~38ms avg latency, ~755MB memory
- 100% of requests classified as `router:protected:user_message`

## Implication

Compression proxies only deliver value when the client speaks the
proxy's native API format. For OpenAI-compatible clients, the proxy
becomes a passthrough with observability-only value.
