---
name: agentfs-readme-audit
description: >
  audit readme, readme alignment, readme drift, check readme
metadata:
  version: "1.2.0"
  tags: [agentfs, readme, audit, semantic, pre-push]
user-invocable: true
disable-model-invocation: false
---

# AgentFS README Audit

Semantic alignment check for `~/.agents/README.md` against the actual
state of the AgentFS USER scope. Designed to complement the
deterministic README staleness check in `pre-push-scan.sh`.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 1.1 |
| **Trigger** | Automatic during Guardrail #10 (Git Push Safety), or explicit |
| **Scope** | USER scope `~/.agents/README.md` only |
| **Dependencies** | `ls`, `grep`, `wc`, `cat` — data gathering is deterministic |
| **LLM required** | Yes — alignment assessment is semantic |

## When This Runs

This skill activates in two scenarios:

### 1. During Pre-Push (Guardrail #10)

Run this skill when **any** agentfs files are staged:
- `skills/`, `knowledge/`, or `AGENTS.md` appear in `git diff --cached --name-only`
- `pre-push-scan.sh` emits `README_AUDIT_REQUIRED` in its output

`README.md` does **not** need to be staged — the audit compares the
*existing* README against the staged changes to detect drift.
If `README.md` is also staged, the audit additionally validates whether
the in-progress README update is sufficient.

**Flow:**
```
git diff --cached --name-only
  └─ skills/ or knowledge/ or AGENTS.md staged?
       └─ YES → pre-push-scan.sh emits README_AUDIT_REQUIRED
                  └─ Agent runs this skill (semantic comparison)
                       └─ If aligned → proceed to push approval
                       └─ If drift detected → report specifics, recommend fixes
                            └─ User decides whether to fix before push
       └─ NO → skip skill entirely
```

### 2. Explicit Invocation

The user asks directly:
> "audit readme" · "check readme alignment" · "readme drift"

## Execution Steps

### Step 1: Gather Actual State

Collect ground truth from the filesystem. All commands are
deterministic — no LLM involvement yet.

```bash
# Skill count and list
ls -d ~/.agents/skills/*/SKILL.md 2>/dev/null | sed 's|.*/skills/||;s|/SKILL.md||' | sort > /tmp/readme-audit-skills.txt
SKILL_COUNT=$(wc -l < /tmp/readme-audit-skills.txt)

# Knowledge bundle count and list
ls -d ~/.agents/knowledge/*/index.md 2>/dev/null | sed 's|.*/knowledge/||;s|/index.md||' | sort > /tmp/readme-audit-knowledge.txt
KNOWLEDGE_COUNT=$(wc -l < /tmp/readme-audit-knowledge.txt)

# Skill categories (extract from skills/index.md)
grep '^|' ~/.agents/skills/index.md | grep -v '^| Name\|^|---' > /tmp/readme-audit-skill-index.txt

# Directory structure (top level)
tree -L 2 --dirsfirst -I '__pycache__|node_modules' ~/.agents/ > /tmp/readme-audit-tree.txt 2>/dev/null

# Guardrail list from seed template
grep -oP '### [0-9]+\. .+' ~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh > /tmp/readme-audit-guardrails.txt 2>/dev/null

# Template version
grep -oP 'version:\s*"\K[^"]+' ~/.agents/skills/agentfs-setup/SKILL.md > /tmp/readme-audit-template-version.txt 2>/dev/null
```

### Step 2: Read README.md

Read the full content of `~/.agents/README.md`.

### Step 3: Semantic Comparison

Compare README claims against actual state across these dimensions:

| # | Dimension | What to Check |
|---|-----------|---------------|
| D1 | **Skill Count** | Does the README mention a skill count? Does it match `$SKILL_COUNT`? |
| D2 | **Skill Categories** | Does the README's category table reflect the actual skills in `index.md`? Are any categories missing or obsolete? |
| D3 | **Knowledge Bundles** | If README mentions knowledge bundles, does the count/list match? |
| D4 | **Directory Structure** | Do the tree diagrams in README match the actual `~/.agents/` layout? |
| D5 | **Guardrail Summary** | If README lists guardrails, do the names/numbers match the seed template? |
| D6 | **Version References** | Any version numbers mentioned — do they match current metadata? |
| D7 | **Feature Descriptions** | Do capability descriptions reflect what skills actually exist? Are there described features with no backing skill, or skills with no README mention? |
| D8 | **Setup Instructions** | Do installation/setup steps still work given current directory layout? |

### Step 4: Produce Report

Format findings as:

```markdown
## README Alignment Report

| Dimension | Status | Detail |
|-----------|--------|--------|
| D1 Skill Count | ✅ / ⚠️ | README says N, actual is M |
| D2 Skill Categories | ✅ / ⚠️ | [specifics] |
| D3 Knowledge Bundles | ✅ / ⚠️ / N/A | [specifics] |
| D4 Directory Structure | ✅ / ⚠️ | [specifics] |
| D5 Guardrail Summary | ✅ / ⚠️ / N/A | [specifics] |
| D6 Version References | ✅ / ⚠️ / N/A | [specifics] |
| D7 Feature Descriptions | ✅ / ⚠️ | [specifics] |
| D8 Setup Instructions | ✅ / ⚠️ | [specifics] |

### Verdict

✅ **ALIGNED** — README accurately reflects current AgentFS state.
⚠️ **DRIFT DETECTED** — N dimension(s) misaligned. Recommend updating README before push.
```

### Step 5: Recommend Fixes (if drift detected)

For each misaligned dimension, provide the specific edit needed.
Do NOT auto-apply — present to user for approval, consistent with
Guardrail #10's wait-for-approval pattern.

## Integration with Guardrail #10

When acting as part of the pre-push workflow, the agent should:

1. Run `pre-push-scan.sh` (deterministic)
2. If output contains `README_AUDIT_REQUIRED`, run this semantic audit —
   regardless of whether `README.md` is itself staged
3. Present both reports together before the push approval prompt
4. If semantic drift is found, recommend specific fixes before pushing
   (but don't block — user decides)

## What This Skill Does NOT Do

- Does not check PROJECT-scope README files
- Does not auto-fix README.md (presents recommendations only)
- Does not replace `pre-push-scan.sh` — complements it
- Does not check prose quality or grammar — only factual alignment

## Companion Skills

- **`agentfs-setup`** — Contains `pre-push-scan.sh` that this skill complements
- **`agentfs-eval`** — Structural health of PROJECT `.agents/`
- **`agentfs-ctx-chk`** — Context efficiency audit (different focus)
- **`skill-index`** — Maintains the `skills/index.md` used as ground truth


## Changelog

| Date | Change |
|------|--------|
| 2026-08-16 | Initial version — semantic README alignment check |
