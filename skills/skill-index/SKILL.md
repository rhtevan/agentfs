---
name: skill-index
description: >
  refresh skill index, index skills, regenerate skill index
metadata:
  version: "3.0.0"
  tags: [agentfs, skills, index, discovery]
user-invocable: true
disable-model-invocation: false
---

# Skill Index Generator

Scan the skills root directory for all skills and produce an `index.md`
that links to each skill's `SKILL.md` with its signal phrases and tags.
Re-run to refresh the index after adding or removing skills. Defaults to
USER skills (`~/.agents/skills/`); use PROJECT skills (`./.agents/skills/`)
only when the user explicitly signals project scope.

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
|--------------|------------------------|------------------------------------||
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
      the `name`, `description`, and `metadata.tags` fields from it.
      - **Multi-line YAML scalars:** When `description:` is followed by
        a folding/literal indicator (`>`, `|`, `>-`, `|-`), the actual
        text is on the subsequent indented lines. Collect all indented
        continuation lines and join them into a single line.
        Shell `sed` one-liners **cannot** handle this — use Python or
        a multi-step approach.
      - **Description field:** The `description` field contains signal
        phrases (comma-separated trigger phrases), NOT prose. Extract
        the full value as-is for the Description column in the index.
      - **Tags:** Extract the `tags:` field under `metadata:`. Tags are
        typically a YAML list in bracket notation, e.g.,
        `tags: [agentfs, memory, harvest]`. Parse the bracket contents
        and split on commas. Strip whitespace from each tag.
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

5. **Check for legacy `metadata.signals` field**
   If any SKILL.md still contains a `metadata.signals` field (removed
   in schema v2.0.0), emit a warning:
   `WARNING: legacy metadata.signals found — dir=[<dir>] — signals should be in description field`

   This helps track migration progress. Do NOT extract or use the
   legacy field — the Description column is populated solely from
   the `description` frontmatter field.

6. **Extract timestamp for each skill**
   Use the last-modified timestamp of each `SKILL.md` file
   (`stat --format='%Y' <file>` on Linux) and format it as
   `YYYY-MM-DD HH:MM`.

7. **Sort skills**
   Sort the collected entries in **reverse chronological order**
   (newest first) by the date obtained in step 6.

8. **Generate `index.md`**
   Write `<skills_root>/index.md` with the following structure:

   ```markdown
   # Skills Index

   > <N> skills | Sorted by reverse chronological order (newest first).

   | Skill | Tags | Description | Updated |
   |-------|------|-------------|----------|
   | [<name>](./<dir>/SKILL.md) | tag1, tag2, … | signal phrase 1, signal phrase 2, … | YYYY-MM-DD HH:MM |
   …
   ```

   Where `<N>` is the total number of skill entries in the table.

   - `<name>` is the skill name from the frontmatter (or directory name).
   - `<dir>` is the subdirectory name (relative link).
   - `Tags` is a comma-separated list of tags from `metadata.tags`
     (empty cell if no tags found).
   - `Description` is the signal phrases from the `description`
     frontmatter field (empty cell if no description found).
   - `Updated` is the last-modified timestamp of the `SKILL.md` file.

9. **Report**
   Print the number of skills indexed, the path to the generated file,
   and any warnings emitted during processing.

## Verification

- [ ] `index.md` exists at the skills root.
- [ ] Every subdirectory containing a `SKILL.md` has a corresponding row.
- [ ] Each link resolves to the correct `SKILL.md` file.
- [ ] A `Tags` column is present showing each skill's metadata tags
      (comma-separated, or empty if none).
- [ ] A `Description` column is present showing each skill's signal
      phrases from the `description` frontmatter field.
- [ ] An `Updated` column is present showing each skill's last-modified
      timestamp (`YYYY-MM-DD HH:MM`).
- [ ] Rows are sorted newest-first (reverse chronological order).
- [ ] **Name consistency** — No warnings about `name` vs directory
      mismatches. If warnings were emitted, they should be reported
      to the user.
- [ ] **Version presence** — No warnings about missing
      `metadata.version`. If warnings were emitted, they should be
      reported to the user.
- [ ] **No legacy signals** — No warnings about `metadata.signals`
      still present in any SKILL.md.


## Changelog

> See [CHANGELOG.md](./CHANGELOG.md) for version history.
