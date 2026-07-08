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
      the `name` and `description` fields from it.
      - For multi-line YAML scalars (e.g., `description: >`), join the
        continuation lines into a single sentence.
      - Strip surrounding quotes from values if present.

   b. If there is **no** YAML frontmatter, derive the metadata:
      - `name` — the subdirectory name.
      - `description` — the first non-heading, non-blank paragraph line
        in the file.

4. **Extract timestamp for each skill**
   Use the last-modified timestamp of each `SKILL.md` file
   (`stat --format='%Y' <file>` on Linux) and format it as
   `YYYY-MM-DD HH:MM`.

5. **Sort skills**
   Sort the collected entries in **reverse chronological order**
   (newest first) by the date obtained in step 4.

6. **Generate `index.md`**
   Write `<skills_root>/index.md` with the following structure:

   ```markdown
   # Skills Index

   > <N> skills | Sorted by reverse chronological order (newest first).

   | Skill | Description | Updated |
   |-------|-------------|---------|
   | [<name>](./<dir>/SKILL.md) | <short description> | YYYY-MM-DD HH:MM |
   …
   ```

   Where `<N>` is the total number of skill entries in the table.

   - `<name>` is the skill name from the frontmatter (or directory name).
   - `<dir>` is the subdirectory name (relative link).
   - `<short description>` is a single-line summary (truncated to ~200
     characters if needed, ending with `…`).
   - `Updated` is the last-modified timestamp of the `SKILL.md` file.

7. **Report**
   Print the number of skills indexed and the path to the generated file.

## Verification

- [ ] `index.md` exists at the skills root.
- [ ] Every subdirectory containing a `SKILL.md` has a corresponding row.
- [ ] Each link resolves to the correct `SKILL.md` file.
- [ ] Descriptions are concise single-line summaries.
- [ ] An `Updated` column is present showing each skill's last-modified timestamp (`YYYY-MM-DD HH:MM`).
- [ ] Rows are sorted newest-first (reverse chronological order).

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-01 00:07 | v1.5 — Generated index now shows total skill count in summary line (`> N skills | Sorted by…`) |
| 2026-06-30 23:36 | v1.4 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 23:31 | v1.3 — Renamed column `Added` → `Updated`; timestamp precision `YYYY-MM-DD HH:MM` |
| 2026-06-30 23:16 | v1.2 — Renamed `Date` column to `Added`; added `> Sorted by reverse chronological order` header to generated index; aligns with Index Currency guardrail (AGENTS.md §6) |
| 2026-06-30 16:46 | v1.1 — Added skill location selection: default to USER (`~/.agents/skills/`), PROJECT (`./.agents/skills/`) only when user explicitly signals project scope |
| 2026-06-25 22:52 | v1.0 — Initial skill: scan, extract metadata, generate index.md |
