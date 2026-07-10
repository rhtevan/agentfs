---
name: skill-creator
description: >
  Create new skills, modify and improve existing skills. Operates in two
  modes: simple (quick scaffold with AgentFS conventions) and advanced
  (full eval/iterate/optimize loop using upstream Anthropic skill-creator).
  Use when users want to create a skill from scratch, turn a workflow into
  a reusable skill, edit or optimize an existing skill, or run evals to
  test a skill. Default mode is simple; use advanced when the user says
  "thorough", "with evals", "production quality", or "advanced".
argument-hint: "Describe what the skill should do. Add 'advanced' for full eval loop."
compatibility: "Any agent with file write capability. Advanced mode benefits from subagent support."
metadata:
  author: agentfs
  version: "1.0"
  tags: [agentfs, skills, creation, scaffolding, evaluation]
user-invocable: true
disable-model-invocation: false
---

# Skill Creator

Create new skills or improve existing ones with built-in AgentFS conventions.

This is a **proxy skill** that operates in two modes:

| Mode | When | What Happens |
|------|------|-------------|
| **Simple** (default) | Quick utility skills, SOPs, small workflows | Scaffold + write + AgentFS post-creation checklist |
| **Advanced** | "advanced", "thorough", "with evals", "production quality" | Full upstream eval/iterate/optimize loop + AgentFS checklist |

## Mode Selection

Detect mode from user's language:

- **Simple** (default): "create a skill", "make this reusable",
  "turn this into a skill", "skill for this workflow"
- **Advanced**: "create a skill, advanced", "thorough skill",
  "production quality skill", "with evals", "benchmark this skill"

When in doubt, ask: *"Do you want a quick skill scaffold, or a
thorough process with test cases and evaluation?"*

---

## Simple Mode

### Step 1 — Capture Intent

Understand what the skill should do. The current conversation may
already contain the workflow to capture. Extract:

1. What should this skill enable the agent to do?
2. What are the steps involved?
3. What inputs does it accept?
4. What does success look like?
5. Are there scripts to generate or reference docs to include?

### Step 2 — Determine Scope

- **Default: USER** (`~/.agents/skills/<skill-name>/`)
- **PROJECT only when explicit**: user says "project skill",
  "for this project", "local skill" → `./.agents/skills/<skill-name>/`

### Step 3 — Create Directory Structure

```bash
SKILL_DIR="$HOME/.agents/skills/<skill-name>"  # or ./.agents/skills/ for PROJECT
mkdir -p "$SKILL_DIR/scripts"
# mkdir -p "$SKILL_DIR/references"  # only if needed
```

### Step 4 — Write SKILL.md

Generate a SKILL.md with this exact structure:

```markdown
---
name: <skill-name>
description: >
  <One-paragraph description. Include WHAT it does AND WHEN to use it.
  Be slightly "pushy" — list specific trigger contexts so the agent
  invokes it reliably.>
argument-hint: "<usage hint>"
compatibility: "<requirements, if any>"
metadata:
  author: agentfs
  version: "1.0"
  tags: [<relevant-tags>]
user-invocable: true
disable-model-invocation: false
---

# <Title>

<Overview paragraph — what this skill does and why>

## Prerequisites

- <List of requirements>

## Steps

1. **Step name**
   Description and commands.

2. **Step name**
   Description and commands.

## Verification

- [ ] <How to confirm success>

## Changelog

| Updated | Change |
|---------|--------|
| YYYY-MM-DD HH:MM | v1.0 — Initial skill |
```

**Writing guidance:**

- **Explain the why** — don't just say MUST/NEVER; explain reasoning
  so the agent can generalize beyond the literal instructions
- **Imperative form** — "Run the script" not "You should run the script"
- **Keep SKILL.md under 500 lines** — if longer, add `references/`
  directory with supporting docs and clear pointers from SKILL.md
- **Progressive disclosure** — metadata (~100 words) always in context;
  SKILL.md body loaded on trigger; bundled resources loaded as needed

### Step 5 — Write Scripts (if applicable)

Generate executable scripts under `scripts/`:

- **Idempotent**: Check preconditions before acting
- **Exit codes**: 0 = success, 1 = failure, 2 = usage error
- **Portable**: Use `$HOME` not hardcoded paths; use `$(uname)` for
  platform-specific commands
- **Documented**: Header comment with usage

```bash
#!/usr/bin/env bash
# <script-name>.sh — <one-line description>
# Usage: bash <script-name>.sh [args]
set -euo pipefail
# ... implementation ...
```

### Step 6 — AgentFS Post-Creation Checklist

**MUST complete ALL of these after creating/updating the skill:**

- [ ] **Scope verification** — skill is in the correct directory
      (USER `~/.agents/skills/` or PROJECT `./.agents/skills/`)
- [ ] **Frontmatter validation** — YAML frontmatter includes:
      `name`, `description`, `metadata.tags`, `user-invocable`
- [ ] **Changelog** — Changelog table exists with at least a v1.0 entry
- [ ] **Index regeneration** — invoke the `skill-index` skill to
      regenerate `skills/index.md` at the appropriate scope
- [ ] **Log update** — append entry to `~/.agents/log.md` (USER scope)
      or `./.agents/log.md` (PROJECT scope) with ISO 8601 timestamp

---

## Advanced Mode

Advanced mode uses the full **Anthropic skill-creator** workflow:
draft → test → evaluate → iterate → optimize.

### Step 1 — Fetch Upstream

Ensure the upstream skill-creator is cached locally:

```bash
bash ~/.agents/skills/skill-creator/scripts/fetch-upstream.sh
```

This downloads the complete Anthropic skill-creator file structure
into `~/.agents/skills/skill-creator/.cache/upstream/`.

### Step 2 — Load Upstream Instructions

Load the full upstream SKILL.md for detailed instructions:

```
load_skill(name: "skill-creator/.cache/upstream/SKILL.md")
```

### Step 3 — Follow Upstream Workflow

Follow the upstream instructions for the full lifecycle:

1. **Capture intent** — interview the user
2. **Write SKILL.md draft** — using upstream's writing guide
3. **Create test cases** — 2-3 realistic test prompts
4. **Run tests** — execute and collect results
5. **Evaluate** — qualitative (user review) + quantitative (assertions)
6. **Iterate** — improve based on feedback, repeat
7. **Optimize description** — triggering accuracy loop (if available)

### Agent Compatibility Notes for Upstream

The upstream skill-creator was written for Claude Code. When using
with a different agent, apply these adaptations:

| Upstream Feature | Claude Code | Goose / Other Agents |
|-----------------|-------------|---------------------|
| Subagents | `spawn subagent` | Use Goose `orchestrator` extension if available, otherwise run test cases sequentially |
| `claude -p` CLI | Native | Skip description optimization (`run_eval.py`, `run_loop.py`, `improve_description.py`). These scripts hardcode `claude -p`. |
| `.claude/commands/` | Native skill discovery | Not applicable — skills discovered via `.agents/skills/` |
| Browser viewer | `open <file>` | Use `--static <path>` flag to generate HTML file, then open manually or with `xdg-open` |
| Cowork | Claude-specific | Not applicable |
| `present_files` tool | Claude-specific | Not applicable — skip packaging step |

**What works everywhere:**
- Skill writing guide (anatomy, progressive disclosure, writing patterns)
- Intent capture and interview process
- Test case design and manual evaluation
- Iteration loop (draft → test → review → improve)
- `scripts/aggregate_benchmark.py` (pure Python)
- `scripts/package_skill.py` (pure Python)
- `scripts/generate_report.py` (pure Python)
- `eval-viewer/generate_review.py` with `--static` flag (pure Python)
- `agents/grader.md`, `agents/analyzer.md` (agent instructions, agent-agnostic)

### Step 4 — AgentFS Post-Creation Checklist

**Same as Simple Mode Step 6** — apply the AgentFS post-creation
checklist after the upstream workflow completes. The upstream does NOT
handle AgentFS conventions (scoping, indexing, logging), so this step
is essential.

---

## Updating an Existing Skill

For both modes:

1. Read the existing SKILL.md first
2. Preserve the original `name` field — do not rename
3. Add a new changelog entry (do not remove existing entries)
4. In advanced mode, use the existing skill as the baseline for
   comparison in the eval loop
5. Run the AgentFS Post-Creation Checklist (Step 6 / Step 4)

---

## Upstream Source

| Item | Value |
|------|-------|
| Repository | [anthropics/skills](https://github.com/anthropics/skills) |
| Path | `skills/skill-creator/` |
| License | See `LICENSE.txt` in cached upstream |
| Cache location | `~/.agents/skills/skill-creator/.cache/upstream/` |
| Cache refresh | Every 7 days, or `fetch-upstream.sh --force` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-10 17:05 | v1.0 — Initial proxy skill: simple + advanced modes, upstream Anthropic skill-creator integration, AgentFS post-creation checklist, agent compatibility notes |
