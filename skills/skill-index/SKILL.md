---
name: skill-index
description: >
  refresh skill index, index skills, regenerate skill index
metadata:
  version: "4.0.0"
  tags: [agentfs, skills, index, discovery]
user-invocable: true
disable-model-invocation: false
---

# Skill Index Generator

> **Scope guard:** This skill is not available in LITE scope projects.
> LITE scope does not support skills or knowledge bundles. If the
> target project's AGENTS.md contains `agentfs-scope: lite`, refuse
> with a clear message.

Regenerate `index.md` for a skills directory by scanning all `SKILL.md` files.

## Skill Location Selection

| User signal | Skills root used |
|-------------|------------------|
| *(no hint)* — "refresh skill index", "index skills" | **USER**: `~/.agents/skills/` |
| "project skills", "index for project", "local skills" | **PROJECT**: `./.agents/skills/` |
| Explicit path provided | Use the provided path as-is |

**Default to USER.** Only use `./.agents/skills/` when the user
specifically calls out project scope.

## Steps

1. **Resolve the skills root** — apply location selection rules above.
2. **Run the canonical index generator:**
   ```bash
   python3 ~/.agents/skills/agentfs-setup/scripts/regen-skill-index.py <skills_root>
   ```
3. **Report** — show output (skill count, warnings) to user.

## What the script does

- Scans each immediate subdirectory for `SKILL.md`
- Extracts `name`, `description`, `metadata.tags` from YAML frontmatter
  (supports multi-line scalars `>`, `|`)
- Falls back to first paragraph line if no frontmatter
- Validates: name-directory consistency, `metadata.version` presence,
  legacy `metadata.signals` absence
- Generates `index.md` sorted reverse-chronologically (newest first)
- Exit 0 = clean, exit 1 = warnings found

## Verification

- [ ] `index.md` exists at the skills root
- [ ] Every subdirectory with `SKILL.md` has a corresponding row
- [ ] Each link resolves to the correct `SKILL.md`
- [ ] Rows sorted newest-first
- [ ] No name-mismatch or missing-version warnings

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
