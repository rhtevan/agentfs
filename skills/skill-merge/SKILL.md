---
name: skill-merge
description: >
  Copy skills from PROJECT skills (./.agents/skills/) to USER skills
  (~/.agents/skills/). If no specific skill name(s) are mentioned, copies
  all project skills. Otherwise copies only the named skills. Existing
  USER skills with the same name are NOT overwritten unless the user
  explicitly signals force/overwrite. After merging, refreshes the
  USER skills index.
metadata:
  tags: [agentfs, skills, merge, project, user]
---

# Skill Merge

Copy project-scoped skills into the shared USER skills directory so
they become available across all projects and agents.

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
- `~/.agents/skills/` must exist (run `agentfs-setup` in USER mode
  if not).

## Steps

1. **Resolve paths**
   - Source: `<project_root>/.agents/skills/`
   - Destination: `~/.agents/skills/`

2. **Build skill list**
   - If `skill_names` is empty: discover all immediate subdirectories
     of the source that contain a `SKILL.md` file.
   - If `skill_names` is provided: validate each name exists as a
     subdirectory with a `SKILL.md` in the source. Report and skip
     any that don't exist.

3. **Copy each skill**
   For each skill in the list:

   a. Check if `~/.agents/skills/<name>/` already exists.
      - If it exists and `force` is `false`:
        **Skip** — print a warning and do not overwrite.
      - If it exists and `force` is `true`:
        **Overwrite** — remove the existing directory first, then copy.
      - If it does not exist: proceed with copy.

   b. Copy the entire skill directory recursively:
      ```bash
      cp -r <source>/<name> ~/.agents/skills/<name>
      ```

   c. Report the result: copied, skipped (already exists), or error.

4. **Refresh USER skills index**
   After all copies are complete, regenerate `~/.agents/skills/index.md`
   using the `skill-index` skill (USER mode — the default).
   This is mandatory per the **Index Currency** guardrail (AGENTS.md §6):
   `skills/index.md` MUST stay current whenever skills are added, renamed,
   moved, or deleted in either scope.

5. **Report summary**
   Print a table of results:
   ```
   Skill       | Status
   ------------|--------
   my-skill    | ✓ copied
   other-skill | ⊘ skipped (already exists)
   bad-name    | ✗ not found in project
   ```

## Example Usage

```bash
# From an agent console — the agent runs these steps:

# 1. Discover what's available
ls .agents/skills/

# 2. Copy all project skills to USER
# (agent iterates and runs cp -r for each)

# 3. Copy specific skills only
# (agent copies only the named directories)
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

| Updated | Change |
|---------|--------|
| 2026-06-30 23:36 | v1.2 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:16 | v1.1 — Added explicit reference to Index Currency guardrail (AGENTS.md §6) in step 4; reinforced mandatory skills/index.md update |
| 2026-06-30 16:46 | v1.0 — Initial skill: copy PROJECT skills to USER with optional name filtering and force flag |
