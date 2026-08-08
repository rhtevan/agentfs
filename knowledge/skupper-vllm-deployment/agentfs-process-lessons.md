---
type: Postmortem
title: "AgentFS Process Failures & Defensive Fixes"
description: "Custom provider JSON incident, skill bypass prevention, backup guardrail, and skill-index bug fix"
tags: [agentfs, guardrails, goose, custom-provider, skill-routing, defensive-design]
timestamp: 2026-08-08T12:09:00-04:00
---

# AgentFS Process Failures & Defensive Fixes

## Incident 1: Goose Custom Provider JSON Schema Violation

### What Happened

During the final sanity check (Phase E, step 26), the action plan
explicitly said `load_skill("goose-skupper-provider")`. Instead,
the agent wrote `custom_skupper.json` directly from memory using
wrong field names:

| Field Written (WRONG) | Correct Field |
|----------------------|---------------|
| `"auth": {"type": "none"}` | `"requires_auth": false` + `"api_key_env": ""` |
| `"default_params": {"timeout": 300}` | `"timeout_seconds": 300` |
| `"name": "Skupper"` | `"name": "custom_skupper"` |
| Missing `display_name` | `"display_name": "Skupper"` |
| Missing 15+ fields | `headers`, `catalog_provider_id`, `setup_steps`, etc. |

### Impact

The malformatted JSON broke Goose Desktop's custom provider discovery.
All custom providers (MaaS, Red Hat, Headroom, Skupper) disappeared
from the Settings and Select Model menus.

### Root Cause

The agent "remembered" an OpenAI-style provider schema from training
data rather than loading the skill's documented Goose-specific schema.
Late in a long session (~200+ turns), confidence was high but accuracy
dropped. The existing AgentFS signal routing rules already required
`load_skill` but were not followed.

### Fix: Three-Layer Defense

| Layer | Where | What |
|:-----:|-------|------|
| **1** | `AGENTS.md` Signal Routing Rules | Added: "Never improvise when a skill exists" — agent MUST `load_skill` even if it believes it already knows the procedure |
| **2** | `goose-skupper-provider/PROVIDER.md` | Added: `⚠️ ALWAYS use this exact schema` warning block above the JSON template |
| **3** | `skill-gen/SKILL.md` Step 4 | Added: "Defensive file templates" writing guidance — new skills that write external files must include exact templates with warning blocks |

### Supporting Changes

- Added `writes-files` optional field to `skill-gen/references/skill-schema.md`
- Updated `agentfs-setup` template to v3.9 with both new rules
- Synced all project AGENTS.md files

## Incident 2: Backup Guardrail Gap

During the JSON incident, the broken `custom_skupper.json` had no
backup. The file is in `~/.config/goose/custom_providers/` — outside
any git repo, untracked.

### Fix

Added to Guardrail #9 (Checkpoints & Resumability):

> **Backup untracked files.** Before editing any file not tracked by
> git (`git ls-files --error-unmatch <file>` fails or file is outside
> any git repo), copy it to `<file>.bak.<YYYYMMDD_HHMMSS>` in the
> same directory. Git-tracked files need no backup — version control
> provides recovery.

Backup is **colocated** with the active copy — same directory, same
name with `.bak.<timestamp>` suffix.

## Incident 3: Skill-Index Signals Extraction Bug

### What Happened

44 of 48 skills had empty Signals columns in `skills/index.md`,
making signal-based skill discovery non-functional.

### Root Cause

The documented regex for capturing the `metadata:` block:

```python
r'^metadata:((?:[ \t]+.*(?:\n|$))*)'
```

In Python, `\$` matches a **literal `$` character**, not end-of-string.
The regex captured **zero characters** after `metadata:`, so the
signals (nested inside the metadata block) were silently dropped.

Tags worked because they used a separate, simpler regex.

### Fix

Replaced the regex with a **line-by-line state machine** that:
1. Enters `in_metadata` state on seeing `metadata:`
2. Exits on non-indented line
3. Handles both signal formats:
   - Inline: `signals: ["foo", "bar"]`
   - Multi-line: `signals:` followed by `- "foo"` items

Result: **48/48 skills** now have populated Signals columns.

## Incident 4: Log.md Rendering Issue

The `<!-- Append-only. Newest entries at top. -->` HTML comment
between the heading and first entry caused a visible gap in some
Markdown renderers.

### Fix

- Removed the comment from all `log.md` files
- Updated the insertion anchor in Guardrail #5 from referencing
  the comment to referencing the `# Directory Update Log` heading
- Updated `scaffold-dotagents.sh` template to not generate the comment

## Meta-Lesson: Context Window Degradation

In sessions exceeding ~100 turns, the agent's adherence to guardrails
degrades as:
- Guardrails (read at session start) get pushed out of attention
- Recent context dominates decision-making
- "I already know this" confidence increases while accuracy decreases

**Mitigation:** Structural defenses (warnings at point-of-action,
skill templates with built-in warnings) are more reliable than
rules-only guardrails because they're encountered at the moment
of action, not just at session start.
