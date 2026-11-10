---
name: skill-merge
description: >
  merge skills, copy skills to user, promote skills
metadata:
  version: "1.2.0"
  model-tier: T1
  tags: [agentfs, skills, merge, project, user]
---

# Skill Merge

Copy project-scoped skills into the shared USER skills directory so
they become available across all projects and agents.

## Rules

Do NOT fabricate or invent command output, status, or results.
Every report MUST come from actual script or command execution.
If a command fails, report the actual error — do not guess.

Do NOT skip steps or combine multiple operations into one step.
Execute each step in order and verify before proceeding.

## Natural-Language Signals

| User says | Behavior |
|-----------|----------|
| "merge skills", "copy skills to system" *(no names)* | Copy **all** skills from `./.agents/skills/` to `~/.agents/skills/` |
| "merge skill foo", "copy foo and bar to system" | Copy only the **named** skill(s) |
| "merge skills --force", "overwrite existing" | Overwrite existing USER skills with the same name |

## Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `project_root` | `.` (current working directory) | Project root containing `.agents/skills/` |
| `skill_names` | *(all)* | Space-separated list of skill directory names to copy. If empty, all skills are copied |
| `force` | `false` | If `true`, overwrite existing USER skills with the same name |

## Prerequisites

- `./.agents/skills/` must exist and contain at least one skill
  (subdirectory with a `SKILL.md` file).
- `~/.agents/skills/` must exist (run `agentfs-setup` in USER scope
  if not).

## Workflow

### Step 1 — Merge skills

The agent MUST run the merge script:

```bash
bash ~/.agents/skills/skill-merge/scripts/merge-skills.sh [--force] [--project-root DIR] [SKILL_NAME ...]
```

The agent MUST report the script output verbatim, including the
per-skill status table.

### Step 2 — Refresh index

If any skills were copied, the agent MUST run post-write to refresh
the USER skills index:

```bash
bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh ~/.agents/skills/index.md "Skills merged from project scope"
```

## Safety

- **No overwrites by default.** If a USER skill with the same name
  already exists, it is skipped with a warning. The user must explicitly
  say "overwrite", "force", or "replace" to enable overwriting.
- **No deletions.** This skill only copies — it never removes skills
  from the PROJECT directory or from USER.
- **Idempotent.** Running the skill multiple times with the same input
  produces the same result (skipped skills stay skipped unless forced).


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
