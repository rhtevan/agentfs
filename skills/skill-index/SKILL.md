---
name: skill-index
description: >
  Create an index.md at the skills root with entries linking to every
  skill's SKILL.md file alongside a short description. Scans all immediate
  subdirectories for SKILL.md files, extracts each skill's name and
  description, and writes a Markdown index. Re-run to refresh the index
  after adding or removing skills. Defaults to USER skills
  (~/.agents/skills/); use PROJECT skills (./.agents/skills/) only when
  the user explicitly signals project scope.
metadata:
  version: "2.3.0"
  tags: [agentfs, skills, index, discovery]
  signals: ["refresh skill index", "index skills", "regenerate skill index"]
---

# Skill Index Generator

Scan the skills root directory for all skills and produce an `index.md`
that links to each skill's `SKILL.md` with a short description.

## Skill Location Selection

| User signal | Skills root used |
|-------------|------------------|
| *(no hint)* — "refresh skill index", "index skills" | **USER**: `~/.agents/skills/` |
| "project skills", "index for project", "local skills", "this project's skills" | **PROJECT**: `./.agents/skills/` |
| Explicit path provided | Use the provided path as-is |

**Default to USER.** When the user triggers this skill without any
hint about location or scope, always use `~/.agents/skills/`. Only
use `./.agents/skills/` when the user specifically calls out project
scope.

## Parameters

| Parameter    | Default                | Description                        |
|--------------|------------------------|------------------------------------|
| `skills_root`| `~/.agents/skills/`    | Root directory containing skills   |

If the user provides an explicit skills root path, use that instead of
the default. If the user signals project scope (see table above), use
`./.agents/skills/` resolved to the current working directory.

## Steps

1. **Resolve the skills root**
   Apply the location selection rules above:
   - No hint → `~/.agents/skills/`
   - Project signal → `./.agents/skills/` (resolved to absolute path)
   - Explicit path → use as provided

2. **Discover skills**
   List every immediate subdirectory of the skills root that contains a
   `SKILL.md` file. Skip the skills root's own `index.md` (the file we
   are generating). Sort entries alphabetically by directory name.

3. **Extract metadata for each skill**
   For each discovered `SKILL.md`:

   a. If the file begins with YAML frontmatter (`---` delimiters), read
      the `name`, `description`, `metadata.tags`, and `metadata.signals`
      fields from it.
      - **Multi-line YAML scalars:** When `description:` is followed by
        a folding/literal indicator (`>`, `|`, `>-`, `|-`), the actual
        text is on the subsequent indented lines. Collect all indented
        continuation lines and join them into a single sentence.
        Shell `sed` one-liners **cannot** handle this — use Python or
        a multi-step approach.
      - **Tags:** Extract the `tags:` field under `metadata:`. Tags are
        typically a YAML list in bracket notation, e.g.,
        `tags: [agentfs, memory, harvest]`. Parse the bracket contents
        and split on commas. Strip whitespace from each tag.
      - **Signals:** Extract the `signals:` field **nested under
        `metadata:`** (i.e., `meta['metadata']['signals']`). Do NOT
        look for signals at the YAML top level — the nesting matters.
        If using a YAML parser, access via
        `meta.get('metadata', {}).get('signals', [])`, not
        `meta.get('signals', [])`.
        Signals are a YAML list of natural-language trigger phrases,
        e.g., `signals: ["sync agentfs", "update agentfs"]`. Parse
        the bracket contents and split on commas. Strip surrounding
        quotes and whitespace from each signal.
      - **Metadata block regex (last-line bug):** When using regex to
        capture the indented block under `metadata:`, the pattern
        `((?:[ \t]+.*\n)*)` fails to capture the last indented line
        if it is not followed by a newline (i.e., it sits immediately
        before the closing `---`). Use `((?:[ \t]+.*(?:\n|$))*)` instead
        to match lines terminated by either newline OR end-of-string.
        Without this fix, `signals:` (often the last metadata field)
        will be silently dropped.
      - **Table generation (blank-line bug):** When joining table lines
        with `\n`, do NOT embed trailing `\n` in any element of the
        lines list. A `\n` suffix on the header separator line produces
        a double newline (blank row) between the header and first data
        row, which breaks Markdown table rendering.
      - Strip surrounding quotes from values if present.

   b. If there is **no** YAML frontmatter, derive the metadata:
      - `name` — the subdirectory name.
      - `description` — the first non-heading, non-blank, non-table,
        non-rule paragraph line in the file. Skip lines starting with
        `#`, `|`, `---`, or `>`.
      - `tags` — empty (no tags available).
      - `signals` — empty (no signals available).

4. **Validate name-directory consistency**
   For each skill, verify that the `name` field from the YAML
   frontmatter exactly matches the parent directory name. This is
   required by the Agent Skills open standard
   ([agentskills.io/specification](https://agentskills.io/specification)).

   - If `name` does NOT match the directory name, emit a warning:
     `WARNING: name mismatch — dir=[<dir>] name=[<name>]`
   - Still include the skill in the index (using the frontmatter
     `name`), but the warning alerts the user to fix it.
   - If the skill has no `name` field, emit:
     `WARNING: missing name field — dir=[<dir>]`
   - If the skill has no `metadata.version` field, emit:
     `WARNING: missing metadata.version — dir=[<dir>]`
     (Version is required per the canonical schema:
     [`skill-gen/references/skill-schema.md`](~/.agents/skills/skill-gen/references/skill-schema.md))

5. **Extract timestamp for each skill**
   Use the last-modified timestamp of each `SKILL.md` file
   (`stat --format='%Y' <file>` on Linux) and format it as
   `YYYY-MM-DD HH:MM`.

6. **Sort skills**
   Sort the collected entries in **reverse chronological order**
   (newest first) by the date obtained in step 4.

7. **Generate `index.md`**
   Write `<skills_root>/index.md` with the following structure:

   ```markdown
   # Skills Index

   > <N> skills | Sorted by reverse chronological order (newest first).

   | Skill | Tags | Signals | Updated |
   |-------|------|---------|---------|
   | [<name>](./<dir>/SKILL.md) | tag1, tag2, … | signal1, signal2, … | YYYY-MM-DD HH:MM |
   …
   ```

   Where `<N>` is the total number of skill entries in the table.

   - `<name>` is the skill name from the frontmatter (or directory name).
   - `<dir>` is the subdirectory name (relative link).
   - `Tags` is a comma-separated list of tags from `metadata.tags`
     (empty cell if no tags found).
   - `Signals` is a comma-separated list of trigger phrases from
     `metadata.signals` (empty cell if no signals found).
   - `Updated` is the last-modified timestamp of the `SKILL.md` file.

   **Note:** The Description column is intentionally omitted — skill
   descriptions are already loaded into the agent's context via the
   built-in skills listing. Including them here would duplicate tokens.

8. **Report**
   Print the number of skills indexed and the path to the generated file.

## Verification

- [ ] `index.md` exists at the skills root.
- [ ] Every subdirectory containing a `SKILL.md` has a corresponding row.
- [ ] Each link resolves to the correct `SKILL.md` file.
- [ ] No Description column is present (descriptions are in built-in skills listing).
- [ ] A `Tags` column is present showing each skill's metadata tags (comma-separated, or empty if none).
- [ ] A `Signals` column is present showing each skill's metadata signals (comma-separated, or empty if none).
- [ ] An `Updated` column is present showing each skill's last-modified timestamp (`YYYY-MM-DD HH:MM`).
- [ ] Rows are sorted newest-first (reverse chronological order).
- [ ] **Name consistency** — No warnings about `name` vs directory mismatches.
      If warnings were emitted, they should be reported to the user.
- [ ] **Version presence** — No warnings about missing `metadata.version`.
      If warnings were emitted, they should be reported to the user.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-08-04 23:52 | v2.3.0 — Added `metadata.version` presence validation; emits warning for skills missing `metadata.version`; references canonical schema (`skill-gen/references/skill-schema.md`) |
| 2026-08-04 19:20 | v2.2 — Documented two implementation bugs: (1) metadata block regex must use `(?:\n|$)` not just `\n` to capture last-line signals before closing `---`; (2) table generation must not embed trailing `\n` in lines list elements to avoid blank-row between header and data |
| 2026-08-04 19:10 | v2.1 — Clarified that signals MUST be extracted from `metadata.signals` (nested), NOT top-level `signals` — the YAML nesting matters; previous ambiguity caused empty Signals columns during index generation |
| 2026-07-27 18:25 | v2.0 — Removed Description column from generated index (already in built-in skills listing; avoids token duplication); Signals column now primary discovery mechanism; every skill MUST have signals |
| 2026-07-27 17:15 | v1.9 — Added Signals column to generated index; extract `metadata.signals` from YAML frontmatter; supports signal-based skill discovery for non-obvious intent routing |
| 2026-07-14 14:56 | v1.8 — Added name-directory consistency validation (step 4): warns when `name` field doesn't match directory name per Agent Skills open standard (agentskills.io/specification). Added verification check. Fixed step numbering. |
| 2026-07-13 13:30 | v1.7 — Added Tags column to generated index; extract `metadata.tags` from YAML frontmatter; supports tag-based skill discovery for Guardrail #9 fallback routing |
| 2026-07-08 22:42 | v1.6 — Clarified multi-line YAML scalar handling (description: > requires collecting indented continuation lines; sed cannot do this); improved fallback to skip table/rule/blockquote lines |
| 2026-07-01 00:07 | v1.5 — Generated index now shows total skill count in summary line (`> N skills | Sorted by…`) |
| 2026-06-30 23:36 | v1.4 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v1.3 — Renamed column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM` |
| 2026-06-30 23:16 | v1.2 — Renamed `Date` column to `Added`; added `> Sorted by reverse chronological order` header to generated index; aligns with Index Currency guardrail (AGENTS.md §6) |
| 2026-06-30 16:46 | v1.1 — Added skill location selection: default to USER (`~/.agents/skills/`), PROJECT (`./.agents/skills/`) only when user explicitly signals project scope |
| 2026-06-25 22:52 | v1.0 — Initial skill: scan, extract metadata, generate index.md |
