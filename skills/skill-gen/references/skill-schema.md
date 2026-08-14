---
title: SKILL.md Frontmatter Schema
version: "2.1.0"
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
| `description` | top-level | ✅ | Multi-line `>` or `>-` scalar | **Signal phrases** — loaded every session via built-in skills listing. See [Signal Phrase Rules](#signal-phrase-rules) |
| `version` | `metadata.version` | ✅ | Quoted 3-part semver: `"1.0.0"` | See [Version Rules](#version-rules) |
| `tags` | `metadata.tags` | ✅ | Bracket list: `[tag1, tag2]` | A skill without tags is invisible to tag-based discovery |

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

## Signal Phrase Rules

The `description` field serves as the **signal routing surface** — it
contains the trigger phrases that the LLM uses to match user intent to
the correct skill. It is loaded into every session via the built-in
skills listing, making it the only metadata always in the agent's
context.

### Phrase Patterns

Skills support two types of capabilities, each with a distinct pattern:

| Capability Type | Pattern | Structure | Examples |
|----------------|---------|-----------|----------|
| **Command** | `verb + noun(s)` | Action that changes state | `setup agentfs`, `create skill`, `start crc`, `merge skills` |
| **Query** | `noun(s)` | Retrieval, status, inspection | `crc status`, `litellm health`, `skupper model topology` |

**Rules:**

- **Command phrases start with a verb** — `setup`, `create`, `install`,
  `configure`, `start`, `stop`, `fix`, `check`, `audit`, `harvest`,
  `merge`, `scaffold`, `generate`, `refresh`
- **Query phrases are noun-only** — no verb. The implicit verb is
  "show me" / "tell me about"
- **No articles, prepositions, or filler words** — `setup agentfs`
  not `set up the agentfs directory`
- **Lowercase** — signals are case-insensitive matching targets;
  store lowercase
- **2-4 words per phrase** — keep each phrase short
- **Comma-separated** in the YAML scalar

### Quality Principles

Three mandatory qualities, applied in this order:

| # | Principle | Rule | Anti-pattern |
|:-:|-----------|------|--------------|
| 1 | **Concise** | Each phrase is 2-4 words following the Command/Query pattern | `scaffold the agentfs dot-agents directory tree` |
| 2 | **No redundant** | No two phrases that would match the same user intent. If removing a phrase doesn't reduce coverage, remove it | `create skill` + `make skill` — keep one, drop the other |
| 3 | **Complete** | Every functional mode of the skill has at least one Command and/or Query phrase | A skill with `start`, `stop`, `status` modes needs signals for all three |

### Completeness Guidance

- **No hard limit** on signal count — completeness takes priority
  over brevity
- **Recommended range: 5-12 phrases** for a well-scoped skill
- **Smell test:** If a skill requires 15+ signals to be complete,
  this likely reveals a **design issue** — the skill carries too
  much responsibility. Consider decomposition following Separation
  of Concerns and Single Responsibility principles
- **Mode coverage:** Each operational mode (e.g., `setup`, `teardown`,
  `status`, `test`) should have at least one signal phrase
- **Bidirectional phrasing:** Include both `verb noun` and `noun verb`
  only when users genuinely say it both ways (e.g., `check skill` +
  `skill check`). Do not mechanically generate both for every phrase

### Opening Paragraph Requirement

Since the `description` field now contains signal phrases (not prose),
the SKILL.md body **MUST** include a hydrated human-readable paragraph
immediately after the `# Title` heading. This paragraph provides the
rich context that `description` used to carry — what the skill does,
why it exists, and when to use it.

### Progressive Disclosure Model

| Layer | Content | Loaded When |
|-------|---------|-------------|
| **Name** | What category | Every session |
| **Description (=signals)** | When to trigger | Every session |
| **Opening paragraph** | What, why, when (human-readable) | On `load_skill` |
| **Full body + scripts** | How to execute | On `load_skill` + on demand |

## Version Rules

1. **Location:** Always inside `metadata:` block — never at YAML
   top-level. This keeps version grouped with other metadata
   (`tags`, `author`) under a single parse path.

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
   the most recent version in `CHANGELOG.md`.
   If `CHANGELOG.md` says `v2.3.1`, then `metadata.version` must be
   `"2.3.1"`.

## Changelog Rules

1. **Location:** A dedicated `CHANGELOG.md` file in the skill
   directory (sibling to `SKILL.md`). SKILL.md retains a
   `## Changelog` section containing only a reference:
   ```markdown
   ## Changelog

   > See [CHANGELOG.md](./CHANGELOG.md) for version history.
   ```

2. **Format:** The `CHANGELOG.md` file uses a rendered Markdown
   table with reverse chronological order (newest first):
   ```markdown
   # skill-name Changelog

   | Updated | Change |
   |---------|--------|
   | YYYY-MM-DD HH:MM | vX.Y.Z — Description of change |
   ```

3. **Why externalized:** Changelogs grow unbounded and bloat the
   model context window when `load_skill` reads SKILL.md. Keeping
   them external follows the same principle as externalizing scripts.
   The changelog is still accessible via
   `load_skill("skill-name/CHANGELOG.md")` when needed.

4. **Do NOT** put changelog data inside YAML frontmatter as a
   `metadata.changelog` array — this bloats frontmatter that
   index parsers must skip and duplicates information.

5. **Every skill MUST have** a `CHANGELOG.md` with at least one
   entry (the initial `v1.0.0` entry).

## Anti-Patterns

| ❌ Anti-Pattern | ✅ Correct |
|----------------|------------|
| `version: 1.2` (top-level, unquoted, 2-part) | `metadata: version: "1.2.0"` |
| `version: 2` (bare integer) | `metadata: version: "2.0.0"` |
| `version: 1.0.0` (top-level, unquoted) | `metadata: version: "1.1.0"` |
| `changelog:` inside YAML frontmatter | `CHANGELOG.md` as separate file |
| `## Changelog` with full table in SKILL.md | `## Changelog` with reference to `CHANGELOG.md` |
| Version only in changelog text, not in frontmatter | Both `metadata.version` AND changelog entry |
| `metadata.version` says `"1.0"` but changelog says `v1.3` | Must match: `"1.3.0"` in both |
| Prose description explaining what skill does | Signal phrases: `setup agentfs, sync agentfs, verify agentfs` |
| `metadata.signals` as separate field | Signals in `description` field directly |
| Description with articles/filler: `set up the agentfs directory` | Concise: `setup agentfs` |
| 20+ signal phrases in description | Smell test: consider splitting the skill |

## Reference Template

```yaml
---
name: <skill-name>
description: >
  <signal phrase 1>, <signal phrase 2>, <signal phrase 3>,
  <signal phrase 4>, <signal phrase 5>
argument-hint: "<usage hint>"
compatibility: "<requirements>"
metadata:
  author: agentfs
  version: "1.0.0"
  tags: [<relevant-tags>]
user-invocable: true
disable-model-invocation: false
---

# <Skill Title>

<Opening paragraph — human-readable explanation of what this skill does,
why it exists, and when to use it. This is the hydrated context that
the signal-phrase description cannot convey.>
```

## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
