---
name: hermes-headroom-provider
description: >
  configure hermes headroom, hermes headroom provider
argument-hint: "Run when setting up Hermes to use Headroom proxy"
compatibility: "Requires Hermes Agent, Headroom proxy, and LiteLLM proxy"
metadata:
  author: agentfs
  version: "1.3.0"
  model-tier: "n/a"
  tags: [hermes, headroom, proxy, provider, llm]
user-invocable: true
disable-model-invocation: false
---

# Skill: hermes-headroom-provider

Configure Hermes Agent to use the local Headroom context-optimization proxy as its custom LLM provider, with model discovery and verification.


## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
