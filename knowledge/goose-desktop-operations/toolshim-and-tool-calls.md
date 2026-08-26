---
type: Postmortem
title: "GOOSE_TOOLSHIM & Native Tool Call Providers"
description: "When the toolshim is needed vs harmful; Desktop hang diagnostic; provider compatibility"
tags: [goose, toolshim, tool-calls, desktop, custom-provider, vllm, hermes]
timestamp: 2026-08-26T12:07:00-04:00
---

# GOOSE_TOOLSHIM & Native Tool Call Providers

## What Is the Toolshim?

Goose has a secondary "tool interpreter" subsystem (`GOOSE_TOOLSHIM`)
that re-parses model responses through a local Ollama model
(`mistral-nemo` on `localhost:11434`) to extract tool calls from
plain text responses.

**Purpose:** Models behind plain text-completion APIs that cannot
return structured `tool_calls` in the OpenAI format.

**Not needed when:** The model provider already returns native
`tool_calls` in the response (e.g., `finish_reason: "tool_calls"`
with proper `function` objects).

## Incident: Desktop Hang with Skupper Provider

### Symptom

Goose Desktop hung (UI unresponsive, sidebar not clickable) after
the Skupper provider (`ibm-granite/granite-4.1-8b-fp8` via vLLM)
returned a response. CLI tests (`curl`, `test.sh`) all passed.

### Root Cause

`GOOSE_TOOLSHIM: true` in `~/.config/goose/config.yaml` forced
Goose to send every model response through Ollama on `localhost:11434`.
Ollama was not running → connection timeout (~30s) → Desktop UI froze.

The vLLM deployment already had `--enable-auto-tool-choice
--tool-call-parser hermes`, producing native OpenAI-format tool calls.
The toolshim was redundant.

### Diagnostic Pattern

1. Check logs: `~/.local/state/goose/logs/cli/<date>/*.log`
2. Search for: `Toolshim augmentation failed`
3. If present: the shim is active and failing
4. Search for: `Tool interpreter payload` — shows the secondary
   model request with the response being re-parsed
5. Check config: `grep GOOSE_TOOLSHIM ~/.config/goose/config.yaml`

### Fix

```yaml
# ~/.config/goose/config.yaml
GOOSE_TOOLSHIM: false
```

Restart Goose Desktop after the change.

## Provider Compatibility Matrix

| Provider Type | Native Tool Calls | Needs Toolshim? |
|---------------|:-----------------:|:---------------:|
| Anthropic API (Claude) | ✅ `tool_use` blocks | No |
| vLLM + `--tool-call-parser hermes` | ✅ OpenAI `tool_calls` | No |
| vLLM + `--tool-call-parser` (any) | ✅ OpenAI `tool_calls` | No |
| LiteLLM proxy (to Claude/OpenAI) | ✅ passthrough | No |
| IBM MaaS API | ✅ native | No |
| OpenAI API | ✅ native | No |
| Plain text-completion API (no tools) | ❌ | **Yes** |
| llama.cpp (no `--tool-call-parser`) | ❌ | **Yes** |

## Decision Rule

> If **all** configured providers support native tool calls,
> set `GOOSE_TOOLSHIM: false`. The shim adds latency when
> Ollama is running (two model calls per turn) and causes
> Desktop hangs when Ollama is not running.

## Streaming Bug: vLLM Hermes + Goose (v1.47.0)

### Symptom

With `toolshim:false` and `supports_streaming:true`, goose fails to
parse tool calls from vLLM's hermes parser. Every tool call attempt
returns `unparseable_tool_call` with error "hit the output token
limit" even though context/tokens are not exhausted.

### Root Cause

vLLM's hermes streaming format sends the first tool-call chunk with
**two entries** in the same `delta.tool_calls` array:

```
Entry 1: {index:0, id:"chatcmpl-tool-...", name:"shell", args: null}
Entry 2: {index:0, id:null, name:null, args:'{"command'}
```

Goose's streaming accumulator (line ~1326 in `openai.rs`) only
processes entries where **both** `id` and `name` are present. Entry 1
matches (stored with empty args). Entry 2 is silently dropped.

Subsequent chunks append args to the stored entry, but the **initial
argument fragment** (`{"command`) is lost. The final accumulated
arguments are missing the opening JSON characters, causing
`looks_truncated()` to fire and produce the misleading "output token
limit" error.

OpenAI's own API sends name and initial args in the **same** entry.
vLLM hermes sends them as **separate** entries. Goose only handles
the OpenAI pattern.

### Fix

Set `supports_streaming: false` in the custom provider JSON. This
makes goose use non-streaming `/v1/chat/completions` which returns
the complete `tool_calls` array in a single response — no
accumulation needed, no dropped fragments.

```json
{
  "supports_streaming": false
}
```

**Trade-off:** No incremental token display in Desktop UI. The entire
response arrives at once. For agentic tool-calling workloads this is
acceptable — most output is tool calls, not long prose.

**Cannot use toolshim:** `GOOSE_TOOLSHIM: true` hangs Goose Desktop
when Ollama is not running (see incident above). Non-streaming is the
correct workaround.

**Goose bug to file:** Streaming tool-call accumulation should handle
the case where a single chunk contains separate name-only and
args-only entries for the same tool call index.

## How vLLM Hermes Parser Works

Granite 4.1 outputs tool calls in XML format:
```xml
<tool_call>{"name": "tool", "arguments": {"key": "val"}}</tool_call>
```

The `hermes` parser in vLLM intercepts this, converts it to
OpenAI-format `tool_calls` in the response JSON, and sets
`finish_reason: "tool_calls"`. The client (Goose) sees a
standard OpenAI tool-call response — no secondary parsing needed.

vLLM flags required:
```
--enable-auto-tool-choice --tool-call-parser hermes
```

These are set in `hosted-model-ctl` profiles `g8b-spec-128k`
and `g8b-fp8-spec-128k`.
