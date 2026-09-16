---
name: agentfs-readme-audit
description: >
  audit readme, readme alignment, readme drift, check readme
metadata:
  version: "2.1.0"
  tags: [agentfs, readme, audit, semantic, pre-push]
user-invocable: true
disable-model-invocation: false
---

# AgentFS README Audit

Semantic alignment check for a README against the actual state of an
AgentFS scope. Supports both USER (`~/.agents/`) and PROJECT
(`./.agents/`) scopes. Designed to complement the deterministic
README staleness check in `pre-push-scan.sh`.

## Overview

| Property | Value |
|----------|-------|
| **Version** | 2.1 |
| **Trigger** | Automatic during Git Push Safety workflow, or explicit |
| **Scope** | USER (`~/.agents/README.md`) or PROJECT (repo-root `README.md` / `.agents/README.md`) — resolved at runtime |
| **Dependencies** | `ls`, `grep`, `wc`, `cat`, `git` — data gathering is deterministic |
| **LLM required** | Yes — alignment assessment is semantic |

## When This Runs

This skill activates in two scenarios:

### 1. During Pre-Push (Git Push Safety workflow)

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
                  └─ Agent resolves scope (Step 0)
                       └─ Agent runs this skill against resolved scope
                            └─ If aligned → proceed to push approval
                            └─ If drift detected → report specifics, recommend fixes
                                 └─ User decides whether to fix before push
       └─ NO → skip skill entirely
```

### 2. Explicit Invocation

The user asks directly:
> "audit readme" · "check readme alignment" · "readme drift"

When invoked explicitly, Step 0 still applies — the agent resolves
scope from the current working directory.

## Execution Steps

### Step 0: Resolve Scope

Determine which scope to audit based on the git repo root where
the audit was triggered. This step runs before any data gathering.

1. Identify the git repo root: `git rev-parse --show-toplevel`
2. If the repo root is `~/.agents` (i.e. the USER-scope AgentFS repo):
   - **Scope = USER**
   - `AGENTS_ROOT=~/.agents`
   - `README_PATH=~/.agents/README.md`
3. Otherwise (any other repo):
   - **Scope = PROJECT**
   - `REPO_ROOT=<git rev-parse --show-toplevel>`
   - `AGENTS_ROOT=$REPO_ROOT/.agents`
   - README resolution order (use first that exists):
     1. `$REPO_ROOT/.agents/README.md`
     2. `$REPO_ROOT/README.md`
   - If neither exists → **skip audit**, report:
     `✅ N/A — no README found in PROJECT scope (not an error)`

### Step 1: Gather Actual State

Collect ground truth from the filesystem. All commands are
deterministic — no LLM involvement yet. Commands use the
resolved `AGENTS_ROOT` from Step 0.

#### USER scope

```bash
# Skill count and list
ls -d ~/.agents/skills/*/SKILL.md 2>/dev/null | sed 's|.*/skills/||;s|/SKILL.md||' | sort > /tmp/readme-audit-skills.txt
SKILL_COUNT=$(wc -l < /tmp/readme-audit-skills.txt)

# Knowledge bundle count and list
ls -d ~/.agents/knowledge/*/index.md 2>/dev/null | sed 's|.*/knowledge/||;s|/index.md||' | sort > /tmp/readme-audit-knowledge.txt
KNOWLEDGE_COUNT=$(wc -l < /tmp/readme-audit-knowledge.txt)

# Skill categories (extract from skills/index.md)
grep '^|' ~/.agents/skills/index.md | grep -v '^| Name\|^| Skill\|^|---' > /tmp/readme-audit-skill-index.txt

# Directory structure (top level)
tree -L 2 --dirsfirst -I '__pycache__|node_modules' ~/.agents/ > /tmp/readme-audit-tree.txt 2>/dev/null

# Guardrail list from seed template
grep -oP '### [0-9]+\. .+' ~/.agents/skills/agentfs-setup/scripts/seed-agents-md.sh > /tmp/readme-audit-guardrails.txt 2>/dev/null

# Template version
grep -oP 'version:\s*"\K[^"]+' ~/.agents/skills/agentfs-setup/SKILL.md > /tmp/readme-audit-template-version.txt 2>/dev/null
```

#### PROJECT scope

```bash
REPO_ROOT="<resolved from Step 0>"
AGENTS_ROOT="$REPO_ROOT/.agents"

# Project skill count and list (if any)
ls -d "$AGENTS_ROOT/skills/"*/SKILL.md 2>/dev/null | sed 's|.*/skills/||;s|/SKILL.md||' | sort > /tmp/readme-audit-skills.txt
SKILL_COUNT=$(wc -l < /tmp/readme-audit-skills.txt)

# Project profiles
ls -d "$AGENTS_ROOT/profiles/"*/ 2>/dev/null | sed 's|.*/profiles/||;s|/$||' | sort > /tmp/readme-audit-profiles.txt 2>/dev/null
PROFILE_COUNT=$(wc -l < /tmp/readme-audit-profiles.txt 2>/dev/null || echo 0)

# AGENTS.md content summary
head -50 "$REPO_ROOT/AGENTS.md" > /tmp/readme-audit-agentsmd.txt 2>/dev/null

# Directory structure
tree -L 2 --dirsfirst -I '__pycache__|node_modules' "$AGENTS_ROOT/" > /tmp/readme-audit-tree.txt 2>/dev/null

# SOUL.md identity
head -5 "$AGENTS_ROOT/SOUL.md" > /tmp/readme-audit-soul.txt 2>/dev/null
```

### Step 2: Read README

Read the full content of the resolved `README_PATH` from Step 0.

### Step 3: Semantic Comparison

Compare README claims against actual state. The audit dimensions
differ by scope.

#### USER scope dimensions

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
| D9 | **Coverage Gaps** | Do major content categories (skills, knowledge) exist on the filesystem but have zero mention in the README? Report as ℹ️ informational, not ⚠️ drift. Example: "11 knowledge bundles exist but README doesn't reference any by name or count." |

#### PROJECT scope dimensions

| # | Dimension | What to Check |
|---|-----------|---------------|
| P1 | **Project Skill Count** | If README mentions project-scoped skills, does the count match `.agents/skills/`? |
| P2 | **Agent Profiles** | If README lists agent profiles, do they match `.agents/profiles/`? |
| P3 | **Agent Identity** | If README describes agent identity/persona, does it match `.agents/SOUL.md`? |
| P4 | **Directory Structure** | If README shows a tree or file listing, does it match actual `.agents/` layout? |
| P5 | **AGENTS.md References** | If README references guardrails, rules, or AGENTS.md content, are those references accurate? |
| P6 | **Feature Descriptions** | Do capability descriptions reflect what actually exists in `.agents/`? Are there described features with no backing file, or files with no README mention? |
| P7 | **Setup / Onboarding** | If README has setup or onboarding instructions, do paths and commands still work? |
| P8 | **Coverage Gaps** | Do major content categories (skills, profiles, agent identity) exist on the filesystem but have zero mention in the README? Report as ℹ️ informational, not ⚠️ drift. |

> **Note:** Dimensions D3 (Knowledge Bundles), D5 (Guardrail Summary
> from seed template), and D8 (Setup Instructions for USER scope) are
> USER-specific and do not apply to PROJECT scope. PROJECT scope does
> not have `knowledge/` directories or seed templates.

### Step 4: Produce Report

Format findings as:

#### USER scope report

```markdown
## README Alignment Report (USER scope)

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
| D9 Coverage Gaps | ✅ / ℹ️ | [specifics — content exists but not mentioned] |

### Verdict

✅ **ALIGNED** — README accurately reflects current AgentFS state.
ℹ️ **COVERAGE GAPS** — N content area(s) exist but are not mentioned in README. Non-blocking.
⚠️ **DRIFT DETECTED** — N dimension(s) misaligned. Recommend updating README before push.
```

#### PROJECT scope report

```markdown
## README Alignment Report (PROJECT scope: <repo-name>)

| Dimension | Status | Detail |
|-----------|--------|--------|
| P1 Project Skill Count | ✅ / ⚠️ / N/A | [specifics] |
| P2 Agent Profiles | ✅ / ⚠️ / N/A | [specifics] |
| P3 Agent Identity | ✅ / ⚠️ / N/A | [specifics] |
| P4 Directory Structure | ✅ / ⚠️ / N/A | [specifics] |
| P5 AGENTS.md References | ✅ / ⚠️ / N/A | [specifics] |
| P6 Feature Descriptions | ✅ / ⚠️ / N/A | [specifics] |
| P7 Setup / Onboarding | ✅ / ⚠️ / N/A | [specifics] |
| P8 Coverage Gaps | ✅ / ℹ️ | [specifics — content exists but not mentioned] |

### Verdict

✅ **ALIGNED** — README accurately reflects current project AgentFS state.
ℹ️ **COVERAGE GAPS** — N content area(s) exist but are not mentioned in README. Non-blocking.
⚠️ **DRIFT DETECTED** — N dimension(s) misaligned. Recommend updating README before push.
```

> When a dimension is not mentioned in the README at all, mark it
> `N/A` — absence of a claim is not drift. Drift only occurs when
> the README makes a claim that contradicts reality.
>
> **Exception:** D9/P8 (Coverage Gaps) specifically checks for content
> that exists but is never mentioned. Mark as `ℹ️ Gap` (not ⚠️ drift)
> when the filesystem has substantive content (skills, bundles,
> profiles) that the README doesn't acknowledge at all. This is a
> non-blocking informational signal — the user decides whether to
> update the README.

### Step 5: Recommend Fixes (if drift detected)

For each misaligned dimension, provide the specific edit needed.
Do NOT auto-apply — present to user for approval, consistent with
the Git Push Safety workflow's wait-for-approval pattern.

## Integration with Git Push Safety

When acting as part of the pre-push workflow, the agent should:

1. Run `pre-push-scan.sh` (deterministic)
2. If output contains `README_AUDIT_REQUIRED`, resolve scope (Step 0)
   using the repo that Git Push Safety resolved in its own Step 0
3. Run this semantic audit against the resolved scope —
   regardless of whether `README.md` is itself staged
4. Present both reports together before the push approval prompt
5. If semantic drift is found, recommend specific fixes before pushing
   (but don't block — user decides)

## What This Skill Does NOT Do

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
| 2026-09-16 | v2.1.0 — Added D9/P8 Coverage Gaps dimension: non-blocking informational signal when filesystem content (skills, bundles, profiles) exists but README doesn't mention it |
| 2026-09-11 | v2.0.0 — Add PROJECT scope support: scope resolution (Step 0), PROJECT-specific dimensions (P1–P7), dual report format, graceful skip when no README exists |
| 2026-08-16 | Initial version — semantic README alignment check |
