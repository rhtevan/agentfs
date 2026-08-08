---
name: skill-gen
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
  version: "1.8.0"
  tags: [agentfs, skills, creation, scaffolding, evaluation]
  signals: ["create skill", "new skill", "make skill", "edit skill"]
user-invocable: true
disable-model-invocation: false
---

# Skill Gen

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
- **Skill Check**: "skill check", "scan skill", "check skill",
  "audit skill", "skill scan", "verify skill quality"

When in doubt, ask: *"Do you want a quick skill scaffold, or a
thorough process with test cases and evaluation?"*

---

## Skill Design Principles

Before creating any skill, understand the three foundational principles
that govern skill architecture. These apply to both Simple and Advanced
modes.

### Non-Interactive Scripts

Scripts under `scripts/` MUST be non-interactive — they MUST NOT use
`read`, `select`, interactive prompts, or any mechanism that blocks
waiting for stdin. All inputs MUST be accepted via CLI arguments,
environment variables, or input files.

- **Why:** Skills can be triggered by scheduled jobs, other skills,
  or automated pipelines where no human is at the terminal. A
  blocking `read` call will hang or fail.
- **How:** Use positional args (`$1`, `$2`) or named flags
  (`--name "$NAME"`). Validate inputs with usage errors (exit 2)
  rather than interactive fallbacks.

### Agent-as-Orchestrator

Skills implement a three-layer separation of concerns:

| Layer | Responsibility | Interactive? |
|---|---|---|
| **SKILL.md** | Defines the process — steps, decision points, gates | N/A (blueprint) |
| **Agent** | Orchestrates flow, mediates user interaction, feeds data between steps | ✅ Conversationally |
| **Scripts** | Execute deterministic, repeatable actions | ❌ Never |

The agent handles ambiguous inputs, clarifications, approvals, and
error explanations. Scripts handle validation, API calls, and data
transformations. SKILL.md is the contract between them.

### Business Process Modeling

Skills can model multi-step processes with human interaction points.
Interactivity belongs in the **agent ↔ user conversation**, not in
script execution. A process skill defines:

- **Action steps** — deterministic scripts the agent runs
- **Interaction steps** — the agent gathers input, presents results,
  or requests approval from the user
- **Decision points** — branching based on script exit codes or
  user responses
- **External gates** — steps that wait for external input
  (approvals, reference numbers, third-party data)

This preserves all guardrails — scripts stay idempotent
(Guardrail #6), the SKILL.md *is* the process documentation,
each script is independently testable, and the same scripts can
be reused by other skills or automated jobs with pre-known inputs.

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
  <Concise description — WHAT it does and WHEN to use it. Keep short;
  this is loaded into every session via the built-in skills listing.
  Avoid repeating information available in the SKILL.md body.>
argument-hint: "<usage hint>"
compatibility: "<requirements, if any>"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [<relevant-tags>]
  signals: ["<trigger phrase 1>", "<trigger phrase 2>"]
    - "skill check"
    - "scan skill"
    - "audit skill"
    - "check skill quality"
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
| YYYY-MM-DD HH:MM | v1.0.0 — Initial skill |
```

**Writing guidance:**

- **Follow the canonical schema** — see
  [`references/skill-schema.md`](./references/skill-schema.md) for
  required/optional fields, version format (quoted 3-part semver in
  `metadata.version`), and changelog rules.
- **Explain the why** — don't just say MUST/NEVER; explain reasoning
  so the agent can generalize beyond the literal instructions
- **Imperative form** — "Run the script" not "You should run the script"
- **Defensive file templates** — when a skill writes or modifies
  external files (configs, JSON, YAML), include the exact template
  inline with a warning block:
  ```
  > ⚠️ **Use this exact schema.** Do NOT write from memory or
  > improvise field names. Copy this template and substitute only
  > the marked placeholders.
  ```
  This prevents agents from bypassing the skill and writing
  malformed files from stale context or hallucinated schemas.
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
      `name`, `description`, `metadata.version` (quoted 3-part semver,
      e.g., `version: "1.0.0"`), `metadata.tags` (bracket notation,
      e.g., `tags: [domain, function, artifact]`), `metadata.signals`
      (list of natural-language trigger phrases, e.g.,
      `signals: ["create skill", "new skill"]`), `user-invocable`.
      A skill without tags is invisible to tag-based discovery
      (Guardrail #5, Index Currency). A skill without signals is
      invisible to signal-based routing via `skills/index.md`.
      See [`skill-gen/references/skill-schema.md`](~/.agents/skills/skill-gen/references/skill-schema.md)
      for the full canonical schema.
- [ ] **Signal quality** — Signals should capture how users
      naturally express intent for this skill. If the skill name
      and description are self-explanatory, signals can mirror the
      key phrases. If the mapping is non-obvious (e.g., "sync
      agentfs" → `agentfs-setup`), signals are critical for
      discoverability.
- [ ] **Name consistency** — The `name` field in the YAML frontmatter
      MUST exactly match the skill's parent directory name. This is
      required by the Agent Skills open standard
      ([agentskills.io/specification](https://agentskills.io/specification)).
      For example, a skill in `crc-ols/SKILL.md` must have `name: crc-ols`.
      The name must be lowercase alphanumeric + hyphens only, no
      consecutive hyphens, and must not start or end with a hyphen.
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
bash ~/.agents/skills/skill-gen/scripts/fetch-upstream.sh
```

This downloads the complete Anthropic skill-creator file structure
into `~/.agents/skills/skill-gen/.cache/upstream/`.

### Step 2 — Load Upstream Instructions

Load the full upstream SKILL.md for detailed instructions:

```
load_skill(name: "skill-gen/.cache/upstream/SKILL.md")
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

## Skill Check Mode

Audit one or more skills against four quality principles. Use when:
- A skill has undergone significant changes across sessions
- Scripts may be stale after architecture changes
- Pre-flight check before committing skill updates
- Validating a skill works autonomously in a fresh session

**Trigger phrases:** "skill check", "scan skill", "check skill",
"audit skill", "verify skill quality"

### Four Principles

#### Principle 1 — Accuracy & Consistency

> Prioritize deterministic scripts and code over natural language.
> Use natural language as 'glue' putting everything together.

**Check for:**
- [ ] Operations are implemented as **scripts** (not inline commands
      that the agent must interpret and may vary between sessions)
- [ ] Scripts match the documented procedures in SKILL.md
- [ ] All ports, hostnames, container names, routing keys in scripts
      match SKILL.md tables and inline YAML/JSON
- [ ] Model IDs, aliases, and context limits are consistent across
      all tables, scripts, and supporting files
- [ ] No hardcoded values that contradict configurable parameters

#### Principle 2 — Autonomous & Currency

> Skill MUST NOT rely on current session history. It must function
> in a fresh NEW session without glitches. No obsolete scripts,
> code, instructions, or content.

**Check for:**
- [ ] Scripts are self-contained (no session-context dependencies)
- [ ] No references to deleted/renamed files, old namespaces, or
      deprecated platform modes
- [ ] All container commands use current image tags and flags
- [ ] Platform references are current (e.g., no linux/systemd if
      migrated to podman)
- [ ] Environment assumptions are documented in Prerequisites
- [ ] Scripts have proper error handling and exit codes

#### Principle 3 — Concise, Traceable & Well-Formatted

> Avoid redundant, conflicting, and obsolete instructions and
> scripts. Historical content must be distilled to knowledge items
> with links from the skill's changelog.

**Check for:**
- [ ] No duplicate instructions (same procedure in two places)
- [ ] No conflicting instructions (two procedures that contradict)
- [ ] No obsolete content (old procedures kept "just in case")
- [ ] Historical lessons distilled to knowledge bundles with links
- [ ] Changelog is current and version matches `metadata.version`
- [ ] Markdown renders correctly (tables, code blocks, YAML blocks)

#### Principle 4 — Verifiable Specification & Test

> A description of purpose is not sufficient. The skill MUST have
> a list of verifiable specification items that clearly and concisely
> prescribe what the skill can do. Associated with each spec item
> are testcases — preferably deterministic scripts/code, or at
> minimum unambiguous instructions with expected results.

**Check for:**
- [ ] A **Specification** section exists listing each capability
      with a unique ID (e.g., S1, S2, S3)
- [ ] Each spec item has a **verifiable criterion** (not vague
      descriptions like "works correctly")
- [ ] A **Tests** section exists with testcases mapped to spec IDs
- [ ] Testcases are implemented as **scripts** where possible
      (e.g., `scripts/test.sh <alias>` → expected HTTP code + model ID)
- [ ] Where scripts aren't feasible, testcases have **unambiguous
      instructions** and **concrete expected results**
- [ ] Test coverage: every spec item has at least one testcase

**Example Specification section:**

```markdown
## Specification

| ID | Capability | Verifiable By |
|:--:|-----------|---------------|
| S1 | List all model containers on both hosts | `scripts/list.sh` outputs status table |
| S2 | Start model by alias on correct host/port | `scripts/start.sh g350m` → HTTP 200 on port 10000 |
| S3 | Stop model by alias | `scripts/stop.sh g350m` → container status Exited |

## Tests

| Test | Spec | Command | Expected Result |
|:----:|:----:|---------|----------------|
| T1 | S1 | `scripts/list.sh` | Table showing 5 models with status |
| T2 | S2 | `scripts/start.sh g350m && scripts/test.sh g350m` | HTTP 200, model=granite-4.0-350m |
| T3 | S3 | `scripts/stop.sh g350m && scripts/status.sh g350m` | Container Exited |
```

### Skill Check Procedure

1. **Load the target skill** — `load_skill(name: "<skill-name>")`
2. **Read all supporting files** — scripts, references, templates
3. **Apply Principle 1** — verify scripts exist and match SKILL.md;
   flag inline-only operations as 🔴 critical
4. **Apply Principle 2** — check for session dependencies, obsolete
   references; verify scripts are self-contained
5. **Apply Principle 3** — scan for redundancy, conflicts, obsolete
   content; check Markdown rendering
6. **Apply Principle 4** — verify Specification and Tests sections
   exist; check spec coverage and test determinism
7. **Report findings** — table of issues with severity (🔴 critical,
   🟡 warning, 🟢 info) and recommended fix
8. **Fix** — apply fixes with user approval; version bump; changelog

### Report Format

```markdown
## Skill Check Report: <skill-name>

| # | Principle | Severity | Finding | Fix |
|:-:|:---------:|:--------:|---------|-----|
| 1 | P1 Accuracy | 🔴 | ... | ... |
| 2 | P4 Spec/Test | 🟡 | ... | ... |
```

## Upstream Source

| Item | Value |
|------|-------|
| Repository | [anthropics/skills](https://github.com/anthropics/skills) |
| Path | `skills/skill-creator/` |
| License | See `LICENSE.txt` in cached upstream |
| Cache location | `~/.agents/skills/skill-gen/.cache/upstream/` |
| Cache refresh | Every 7 days, or `fetch-upstream.sh --force` |

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-08 13:39 | v1.8.0 — Skill Check expanded to 4 principles: added Principle 4 (Verifiable Specification & Test) with spec table and testcase mapping examples; Principle 1 now flags inline-only operations as critical |
| 2026-08-08 13:20 | v1.7.0 — Added Skill Check mode: audit skills against 3 principles (Accuracy/Consistency, Autonomous/Currency, Concise/Traceable); checklist-driven procedure with severity-rated findings report |
| 2026-08-08 10:55 | v1.6.0 — Added "Defensive file templates" writing guidance: skills that write external files must include exact templates with warning blocks; added `writes-files` optional field to skill-schema.md |
| 2026-08-04 23:47 | v1.5.0 — Added canonical SKILL.md frontmatter schema (`references/skill-schema.md`); template now uses quoted 3-part semver (`"1.0.0"`); post-creation checklist requires `metadata.version`; writing guidance references schema doc |
| 2026-07-27 18:35 | v1.4 — Added `metadata.signals` to SKILL.md template and post-creation checklist; added signal quality check; updated description guidance to emphasize conciseness (loaded every session via built-in skills listing) |
| 2026-07-14 14:51 | v1.3 — Added "Name consistency" check to post-creation checklist: `name` field must match directory name per Agent Skills open standard (agentskills.io/specification) |
| 2026-07-13 16:11 | v1.2 — Added "Skill Design Principles" section: non-interactive scripts, agent-as-orchestrator pattern, business process modeling |
| 2026-07-13 11:19 | v1.1 — Renamed from `skill-creator` to `skill-gen` for naming consistency with `okf-bundle-gen`, `bash-completion-gen`; updated all internal path references |
| 2026-07-10 17:05 | v1.0 — Initial proxy skill: simple + advanced modes, upstream Anthropic skill-creator integration, AgentFS post-creation checklist, agent compatibility notes |
