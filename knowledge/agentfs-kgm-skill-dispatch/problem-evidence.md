# Problem & Evidence

## Problem

Granite 4.2 8B (ibm-granite/granite-4.2-8b-fp8) cannot reliably
match user input against the `# Skills` section in the system prompt
(60 skill entries) to call `load_skill`. Claude Opus handles this
natively. The gap is model capability, not missing instructions.

## Evidence: Granite Thinking Traces

| Input | Granite's thinking | First tool call | Correct? |
|-------|-------------------|----------------|----------|
| "skupper status" | "There's a skupper-model-provider **extension**... let me check if skupper is installed" | `shell("skupper status")` | ❌ |
| "check crc status" | "I should check if the **crc command** is..." | `shell("crc status")` | ❌ |
| "hey git" | "According to the **rules**, this triggers the skill agentfs-git-push" | `load_skill("agentfs-git-push")` | ✅ |

Key finding: "hey git" works because Rule 7 explicitly names the
skill and tool call. General Rule 8 ("check # Skills section") is
not followed by 8B models.

## Behavioral Score Progression

| Version | Model | Template | Behavioral | Change |
|---------|-------|----------|-----------|--------|
| 5.10.1 | granite-4.2-8b-fp8 | 70 | — | Baseline |
| 5.11.1 | granite-4.2-8b-fp8 | 100 | 0/3 | Section reorder, anti-pattern, trim prose |
| 5.11.2 | granite-4.2-8b-fp8 | 100 | 1/3 | Rule 8 example added (only Rule 7 "hey git" passes) |
| 5.11.3 | granite-4.2-8b-fp8 | — | 1/3 | Concrete example in Rule 8 — no improvement |
| 5.12.0+ | granite-4.2-8b-fp8 | 100 | pending | KGM-based dispatch |

## Root Cause

The model conflates skills, extensions, and CLI commands. When it
sees "skupper", it reaches for `shell` or `extensionmanager` —
tools it's trained to use — rather than `load_skill`, which requires
scanning a long prose list to find the right name.

The only reliable path for 8B: explicit rule entries (Rule 7 pattern)
or tool-based lookup (KGM `search_nodes`).
