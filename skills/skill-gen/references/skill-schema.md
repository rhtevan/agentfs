---
title: SKILL.md Frontmatter Schema
version: "1.1.0"
status: canonical
---

# SKILL.md Frontmatter Schema

This document defines the canonical YAML frontmatter schema for all
`SKILL.md` files under `~/.agents/skills/` (USER) and
`./.agents/skills/` (PROJECT). It is the single source of truth —
`skill-gen`, `skill-harvest`, `skill-index`, and any future skill
factory or validator MUST reference this document rather than
maintaining independent copies.

## Required Fields

| Field | Location | Required | Format | Notes |
|-------|----------|----------|--------|-------|
| `name` | top-level | ✅ | lowercase alphanumeric + hyphens | Must exactly match parent directory name ([agentskills.io/specification](https://agentskills.io/specification)) |
| `description` | top-level | ✅ | Multi-line `>` or `>-` scalar | Concise — loaded every session via built-in skills listing |
| `version` | `metadata.version` | ✅ | Quoted 3-part semver: `"1.0.0"` | See [Version Rules](#version-rules) |
| `tags` | `metadata.tags` | ✅ | Bracket list: `[tag1, tag2]` | A skill without tags is invisible to tag-based discovery |
| `signals` | `metadata.signals` | ✅ | List of trigger phrases | A skill without signals is invisible to signal-based routing |

## Optional Fields

| Field | Location | Format | Default | Notes |
|-------|----------|--------|---------|-------|
| `author` | `metadata.author` | string | `agentfs` | Creator attribution |
| `related_skills` | `metadata.related_skills` | bracket list | — | Cross-references to companion skills |
| `argument-hint` | top-level | string | — | Usage hint shown to user |
| `compatibility` | top-level | string | — | Platform/tool requirements |
| `platforms` | top-level | bracket list | — | e.g., `[linux]` |
| `user-invocable` | top-level | boolean | `true` | Whether users can trigger directly |
| `disable-model-invocation` | top-level | boolean | `false` | Whether to suppress auto-invocation |
| `writes-files` | top-level | boolean | `false` | Skill writes/modifies files outside `.agents/` — signals critical file templates that must be followed exactly |

## Version Rules

1. **Location:** Always inside `metadata:` block — never at YAML
   top-level. This keeps version grouped with other metadata
   (`tags`, `signals`, `author`) under a single parse path.

2. **Format:** Always quoted, always 3-part semver:
   `"MAJOR.MINOR.PATCH"` (e.g., `"1.0.0"`, `"2.3.1"`).
   - Quoting is mandatory because YAML treats unquoted `1.0` as
     float `1`, and `1.10` as float `1.1` — both lose information.
   - 3-part is mandatory for unambiguous ordering and consistency.

3. **Incrementing:**
   - PATCH (`x.y.Z`) — bug fixes, typo corrections, minor wording
   - MINOR (`x.Y.0`) — new steps, new features, new scripts
   - MAJOR (`X.0.0`) — breaking changes to workflow, renamed
     parameters, restructured steps

4. **Sync with changelog:** The `metadata.version` value MUST match
   the most recent version mentioned in the `## Changelog` section.
   If the changelog says `v2.3.1`, then `metadata.version` must be
   `"2.3.1"`.

## Changelog Rules

1. **Location:** A `## Changelog` Markdown section in the SKILL.md
   body (not inside YAML frontmatter).

2. **Format:** Rendered Markdown table with reverse chronological
   order (newest first):
   ```markdown
   ## Changelog

   | Updated | Change |
   |---------|--------|
   | YYYY-MM-DD HH:MM | vX.Y.Z — Description of change |
   ```

3. **Do NOT** put changelog data inside YAML frontmatter as a
   `metadata.changelog` array — this bloats frontmatter that
   index parsers must skip and duplicates information.

4. **Every skill MUST have** at least one changelog entry
   (the initial `v1.0.0` entry).

## Anti-Patterns

| ❌ Anti-Pattern | ✅ Correct |
|----------------|------------|
| `version: 1.2` (top-level, unquoted, 2-part) | `metadata: version: "1.2.0"` |
| `version: 2` (bare integer) | `metadata: version: "2.0.0"` |
| `version: 1.0.0` (top-level, unquoted) | `metadata: version: "1.1.0"` |
| `changelog:` inside YAML frontmatter | `## Changelog` as Markdown section |
| Version only in changelog text, not in frontmatter | Both `metadata.version` AND changelog entry |
| `metadata.version` says `"1.0"` but changelog says `v1.3` | Must match: `"1.3.0"` in both |

## Reference Template

```yaml
---
name: <skill-name>
description: >
  <Concise description — WHAT it does and WHEN to use it.>
argument-hint: "<usage hint>"
compatibility: "<requirements>"
metadata:
  author: agentfs
  version: "1.1.0"
  tags: [<relevant-tags>]
  signals: ["<trigger phrase 1>", "<trigger phrase 2>"]
user-invocable: true
disable-model-invocation: false
---
```

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-08 10:55 | v1.1.0 — Added `writes-files` optional field: flags skills that write/modify files outside `.agents/`, signaling critical file templates that must be followed exactly |
| 2026-08-04 23:46 | v1.0.0 — Initial schema: canonical version location (metadata.version), quoted 3-part semver, changelog as Markdown section, anti-patterns table |

