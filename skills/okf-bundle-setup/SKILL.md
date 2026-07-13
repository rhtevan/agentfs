---
name: okf-bundle-setup
description: >
  Create or organize a directory into an OKF-conformant knowledge bundle.
  Scaffolds index.md, log.md, and concept documents with proper YAML
  frontmatter. Handles both fresh bundles and existing directories with
  files — scanning content to derive a semantic bundle name, creating
  concept docs for non-md assets, and recursing into subdirectories as
  sub-bundles. Fully compliant with Open Knowledge Format v0.1.
metadata:
  tags: [agentfs, okf, knowledge, scaffolding, setup]
---

# OKF Bundle Setup

Create, organize, or update a directory as an **Open Knowledge Format
(OKF) v0.1** knowledge bundle.

For the full OKF specification, see
[references/okf-spec-summary.md](references/okf-spec-summary.md).

## Prerequisites

- **bash** available (for scaffolding / scanning scripts)
- Write access to the target directory

## Inputs

The skill accepts an **optional** bundle path argument:

| Input | Example | Behaviour |
|-------|---------|-----------|
| *(none)* | `"set up an okf bundle"` | Use `~/.agents/knowledge/` as the bundle root |
| Explicit path | `"create an okf bundle at docs/data-catalog"` | Use the given path as the bundle root |

---

## Procedure

Execute these phases **in order**. Each phase references a helper
script or gives inline agent instructions.

### Naming Convention — lowercase kebab-case

All bundle and sub-bundle directory names **MUST** follow
**lowercase kebab-case** (`this-style`):

- Only lowercase letters (`a-z`), digits (`0-9`), and hyphens (`-`)
- No underscores, spaces, uppercase, or special characters
- Maximum **25 characters**
- Must not start or end with a hyphen

Examples:
- ✅ `rca-labeled-dataset`, `sales-data`, `ml-training-configs`
- ❌ `rca_labeled_dataset` (underscores), `RCA-Data` (uppercase),
  `my data` (spaces)

When the input directory name violates this convention, the agent
**must rename it** to conform (e.g., `rca_labeled_dataset` →
`rca-labeled-dataset`). The normalization rule is:
lowercase → replace `_` and spaces with `-` → strip non-alphanumeric
except `-` → collapse consecutive hyphens → trim leading/trailing
hyphens → truncate to 25 chars.

Reserved directory names (`assets`, `scripts`, etc.) are exempt from
the length limit but must still be lowercase kebab-case (they already
are by definition).

### Phase 1 — Resolve the bundle root

1. If no path was given, set `BUNDLE_ROOT` to `~/.agents/knowledge/`.
2. If an explicit path was given, set `BUNDLE_ROOT` to that path
   (resolve relative paths against the current working directory).
3. **Normalize the directory name** to lowercase kebab-case. If the
   current name violates the convention, rename it:
   ```bash
   # Example: rca_labeled_dataset → rca-labeled-dataset
   NEW_NAME="$(echo "$DIRNAME" | tr '[:upper:]' '[:lower:]' | \
     sed 's/[_ ]/-/g; s/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//' | \
     cut -c1-25)"
   ```
4. Create the directory if it does not exist:
   ```bash
   mkdir -p "$BUNDLE_ROOT"
   ```

### Phase 2 — Scan existing content

Run the scanning script to inventory what is already in the directory:

```bash
bash <skill-dir>/scripts/scan-files.sh "$BUNDLE_ROOT"
```

This produces a structured report of every file and subdirectory,
grouped by type (markdown, data, code, media, other). Use this report
as input for Phases 3–6.

### Phase 3 — Semantic directory rename (explicit path only)

> **Skip this phase** if no explicit path was given (the default
> `~/.agents/knowledge/` name is intentional) **or** if the directory is empty.

When an explicit path was provided **and** the directory contains files:

1. Review the scan report from Phase 2.
2. Identify the **dominant semantic theme** of the contents — e.g.,
   "api contracts", "sales pipeline data", "ml training configs".
3. Derive a new directory name:
   - **Lowercase kebab-case** (`this-style`) — MANDATORY
   - Maximum **25 characters**
   - Descriptive of the content's domain
   - Apply the normalization rule: lowercase → replace `_` and spaces
     with `-` → strip invalid chars → collapse hyphens → trim
4. Rename the directory:
   ```bash
   mv "$BUNDLE_ROOT" "$(dirname "$BUNDLE_ROOT")/<new-name>"
   ```
5. Update `BUNDLE_ROOT` to the new path.

**Do NOT rename** if:
- The directory is empty.
- The current name already accurately describes the content **and**
  already conforms to lowercase kebab-case.
- Renaming would break external references the user depends on (ask
  if uncertain).

**Always rename** if the current name violates lowercase kebab-case
(e.g., contains underscores, uppercase, or spaces), even if the
content is accurately described. In that case, normalize the existing
name rather than deriving a new one — e.g., `rca_labeled_dataset` →
`rca-labeled-dataset`.

### Phase 3b — Absorb README into index.md

> **Eliminates duplication** — a bundle must not have both a README and
> an index.md conveying the same information.

If a `README.md` (or `README.txt`, `README.rst`, `readme.md`, or any
case variation) exists at the bundle root:

1. **Strip YAML frontmatter** from the README if present — `index.md`
   must have no frontmatter (OKF §6).
2. **Convert the README body** into `index.md` format:
   - Preserve the first heading as the bundle title.
   - Append a structured directory listing section (using the
     `* [Title](path) - description` format) if one is not already
     present in the README body.
3. **Write the result as `index.md`**.
4. **Delete the original README file** (it is now fully absorbed).

If `index.md` already exists **and** a README also exists, merge any
unique content from the README into the existing `index.md`, then
delete the README.

If only `index.md` exists (no README), skip this phase.

### Phase 4 — Organize non-markdown files

**Reserved subdirectory names** — the following directory names are
reserved for organizing non-markdown files. They are **not**
sub-bundles and must **never** be treated as sub-bundles (no
`index.md`, no recursive processing, no semantic rename):

| Reserved name | Purpose |
|---------------|---------|
| `assets/` | Images, diagrams, media, and binary attachments |
| `samples/` | Data samples and example files |
| `references/` | External documents, PDFs, archived web pages |
| `scripts/` | Code files, automation, utilities |
| `templates/` | Reusable file templates and boilerplate |
| `archive/` | Superseded or historical content kept for provenance |

These names are reserved **at every level** of the bundle tree — a
sub-bundle may contain its own `assets/` or `scripts/` directory,
but those are always helper directories, never sub-bundles.

**Sub-bundles must not use reserved names.** If a subdirectory happens
to be named with a reserved name but actually contains knowledge
content (concept `.md` files intended as a sub-bundle), rename it to
a non-reserved name before proceeding.

For every non-`.md` file found by the scan, apply these placement rules:

| File category | Placement rule |
|---------------|---------------|
| **Domain schemas** (`.sql`, `.avro`, `.proto`, `.json` schemas) | Co-locate next to the concept `.md` that describes them, or group into an `assets/` sibling directory |
| **Images / diagrams** (`.png`, `.svg`, `.jpg`, `.gif`, `.webp`) | Place in an `assets/` subdirectory at the same level as the referencing concept |
| **Data samples** (`.csv`, `.jsonl`, `.parquet`, `.tsv`) | Co-locate next to the concept `.md`, or group into a `samples/` sibling directory |
| **External docs** (`.pdf`, `.html`, `.txt` reference material) | Place in a `references/` subdirectory per OKF §8 |
| **Code files** (`.py`, `.sh`, `.js`, etc.) | Co-locate next to the concept `.md` if tightly coupled; otherwise group into a `scripts/` sibling directory |
| **Config files** (`.yaml`, `.toml`, `.ini`, etc.) | Co-locate next to the concept `.md` they belong to |
| **Templates** (`.j2`, `.tmpl`, skeleton files) | Place in a `templates/` subdirectory |

When files are moved, preserve the relative directory depth — do not
flatten deeply nested structures.

If a directory already has a sensible organization, **keep it** and
work within the existing structure.

### Phase 5 — Create concept documents for non-md files

For each significant non-md file (or logical group of related files),
create a companion `<concept>.md` in the same directory.

Every concept document **MUST** contain:

```markdown
---
type: <descriptive type>       # REQUIRED — e.g., "SQL Schema", "Dataset",
                               #   "API Spec", "Diagram", "Script", "Config"
title: <human-readable name>   # RECOMMENDED
description: <one-line summary> # RECOMMENDED
tags: [<tag>, ...]             # OPTIONAL
timestamp: <ISO 8601>          # OPTIONAL — use current time for new docs
---

<markdown body describing the asset>
```

**Guidance for the body:**
- Summarize what the file contains and its purpose.
- Link to the non-md file using a relative markdown link:
  `[schema.sql](./schema.sql)` or `![diagram](./assets/arch.png)`.
- Use structural markdown — headings, tables, code blocks.
- Add a `# Citations` section if external sources apply (per OKF §8).
- Cross-link to related concepts using bundle-relative (`/path/to.md`)
  or relative (`./sibling.md`) links.

**Naming conventions:**
- The concept `.md` filename should match or closely mirror the asset
  it describes: `schema.sql` → `schema.md`, `pipeline.py` → `pipeline.md`.
- For a group of related files, use a single descriptive name:
  `training-configs.md` for a set of `.yaml` config files.

### Phase 6 — Scaffold OKF infrastructure files

Run the scaffolding script to create `index.md` and `log.md`:

```bash
bash <skill-dir>/scripts/scaffold-bundle.sh "$BUNDLE_ROOT"
```

This creates skeleton `index.md` and `log.md` at the bundle root.
The script is **idempotent** — it will not overwrite existing files.

After the script runs, **update `index.md`** to reflect the actual
contents discovered in Phases 2–5. The index MUST:

- Have **no YAML frontmatter** (per OKF §6).
- List every subdirectory and root-level concept using this format:
  ```markdown
  # <Section Heading>

  * [Display title](relative-path) - short description
  ```
- Pull descriptions from each concept's `description` frontmatter
  field when available.

### Phase 7 — Process subdirectories (recursive)

**Reserved directory names** are helper directories for non-md files
and must **never** be processed as sub-bundles. The reserved names are:

> `assets/`, `samples/`, `references/`, `scripts/`, `templates/`, `archive/`

For **every subdirectory** under `BUNDLE_ROOT` that is **not** a
reserved name and **not** a hidden directory (starting with `.`):

1. **Guard**: If the subdirectory has a reserved name but contains
   concept `.md` files (i.e., it is really a sub-bundle mislabelled
   with a reserved name), rename it to a non-reserved descriptive
   name before proceeding. For example, `scripts/` containing concept
   docs about scripting → rename to `scripting/`.
2. Treat the subdirectory as a **sub-bundle**.
3. Repeat Phases 2–6 within it (including Phase 3b — absorb any
   README found in the sub-bundle):
   - Scan its contents.
   - Absorb any README into the sub-bundle's `index.md`.
   - Organize any non-md files using Phase 4 rules.
   - Create concept docs per Phase 5.
   - Create/update its own `index.md` (no frontmatter) listing its
     contents.
   - Optionally create a `log.md` if the sub-bundle is substantial.
4. For the semantic rename in sub-bundles: apply the same rules as
   Phase 3 — rename the subdirectory to a descriptive **lowercase
   kebab-case** name (≤25 chars) based on its contents, **unless it
   is empty or already well-named and kebab-case conformant**. The
   new name **must not** collide with a reserved directory name.
   If the current name is descriptive but uses underscores or
   uppercase, simply normalize it (e.g., `My_Reports` → `my-reports`).

**Recursion depth:** Process all levels. There is no depth limit, but
the agent should use judgment — a deeply nested tree of trivial files
does not need per-level `index.md` files.

### Phase 8 — Update the root index

After all subdirectories are processed, **regenerate the root
`index.md`** to reflect the final structure, including any directories
that were renamed in Phase 7.

### Phase 9 — Log all changes to log.md

**Every run of the `okf-bundle-setup` skill MUST leave a trace in
`log.md`.** After completing Phases 1–8, append a log entry that
records what was done.

#### Log format rules

- **No YAML frontmatter** — `log.md` is a reserved file (OKF §7).
- **Reverse chronological order** — newest entries **first**, directly
  after the `# Directory Update Log` heading. Older entries follow
  below.
- **ISO 8601 date headings** — each entry group is under an
  `## YYYY-MM-DD` heading.
- If today's date heading already exists at the top, append the new
  bullet points under it. If it does not exist, insert a new
  `## YYYY-MM-DD` section **above** all existing date sections.
- Use boldface action tags: `**Initialization**`, `**Rename**`,
  `**Reorganization**`, `**Creation**`, `**Update**`, `**Absorption**`,
  `**Deletion**`.

#### What to log

Record every material change the skill made. Common entries:

| Action | Example log entry |
|--------|-------------------|
| Bundle created | `* **Initialization**: Created OKF bundle structure.` |
| Directory renamed | `* **Rename**: `old-name` → `new-name` (kebab-case normalization).` |
| README absorbed | `* **Absorption**: README.md absorbed into index.md.` |
| Files organized | `* **Reorganization**: Moved 7 data files → `samples/`, 1 script → `scripts/`.` |
| Concept docs created | `* **Creation**: Created 8 concept documents for data assets.` |
| Sub-bundles processed | `* **Update**: Processed 3 sub-bundles, created index.md in each.` |
| Index regenerated | `* **Update**: Regenerated root index.md with final structure.` |

#### Inserting at the top (reverse chronological)

**Preferred**: Use the `merge-log-entry.sh` script from the
`okf-bundle-gen` skill — it handles today-heading dedup and
reverse-chronological insertion automatically:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  "$BUNDLE_ROOT/log.md" \
  "* **Reorganization**: Moved N files into reserved directories.
* **Update**: Regenerated index.md."
```

**Manual alternative** (if `okf-bundle-gen` is not available):

```bash
TODAY="$(date +%Y-%m-%d)"
NEW_ENTRY="## ${TODAY}
* **Reorganization**: Moved N files into reserved directories.
* **Update**: Regenerated index.md.
"
{
  echo "# Directory Update Log"
  echo ""
  echo "$NEW_ENTRY"
  tail -n +3 "$BUNDLE_ROOT/log.md"
} > "$BUNDLE_ROOT/log.md.tmp"
mv "$BUNDLE_ROOT/log.md.tmp" "$BUNDLE_ROOT/log.md"
```

If the agent manages log.md directly (not via scripts), it must still
ensure the newest `## YYYY-MM-DD` section is at the top — never
appended to the bottom.

### Phase 10 — Verify conformance

Run the verification script:

```bash
bash <skill-dir>/scripts/verify-bundle.sh "$BUNDLE_ROOT"
```

This checks:
- Every non-reserved `.md` file has parseable YAML frontmatter.
- Every frontmatter block contains a non-empty `type` field.
- Reserved files (`index.md`, `log.md`) have no frontmatter.
- All internal markdown links resolve to existing files.

All items should show `[✓]`. Fix any `[✗]` items before finishing.

---

## OKF Conformance Checklist

Per OKF v0.1 §9, a bundle is conformant when:

- [ ] Every non-reserved `.md` file has a YAML frontmatter block with a
      non-empty `type` field.
- [ ] `index.md` files contain **no** YAML frontmatter and follow the
      directory-listing format (§6).
- [ ] `log.md` files use ISO 8601 date headings in **reverse
      chronological order** (newest first) and have no frontmatter (§7).
- [ ] Cross-links use bundle-relative (`/path/to.md`) or relative
      (`./sibling.md`) paths (§5).
- [ ] No `README.md` (or variant) co-exists alongside `index.md` — any
      README has been absorbed into the index.
- [ ] Reserved directory names (`assets/`, `samples/`, `references/`,
      `scripts/`, `templates/`, `archive/`) are used only for
      non-markdown helper files, never as sub-bundles.
- [ ] All bundle and sub-bundle directory names follow lowercase
      kebab-case: only `a-z`, `0-9`, `-`, max 25 chars, no underscores
      or uppercase.

---

## Example: Fresh bundle (no path given)

```
~/.agents/knowledge/            ← created as bundle root
├── index.md                    ← directory listing, no frontmatter
└── log.md                      ← initialized with today's date
```

## Example: Existing directory with files

Before:
```
./my-data/
├── README.md                   ← will be absorbed into index.md
├── orders.csv
├── customers.csv
├── schema.sql
└── reports/
    ├── q1-revenue.png
    └── summary.pdf
```

After (`BUNDLE_ROOT` renamed to `./sales-data/`):
```
./sales-data/
├── index.md                    ← README.md absorbed here (no frontmatter)
├── log.md                      ← initialized with today's date
├── orders.md                   ← concept doc for orders.csv
├── customers.md                ← concept doc for customers.csv
├── schema.md                   ← concept doc for schema.sql
├── samples/                    ← reserved: data files
│   ├── orders.csv
│   └── customers.csv
├── assets/                     ← reserved: schemas, binaries
│   └── schema.sql
└── reports/                    ← sub-bundle (not a reserved name)
    ├── index.md                ← sub-bundle index
    ├── q1-revenue.md           ← concept doc for the chart
    ├── assets/                 ← reserved helper dir (not a sub-bundle)
    │   └── q1-revenue.png      ← image in assets/
    └── summary.md              ← concept doc for the PDF
        (summary.pdf co-located or in assets/)
```

Note: `assets/` and `samples/` are **reserved directories** — they
hold non-md files, not concepts. They get no `index.md` and are
never processed as sub-bundles.

## Pitfalls

1. **`.venv/`, `.git/`, `node_modules/` pollution** — The scan and
   verify scripts must prune hidden directories. If the scan report
   shows thousands of files from package managers, the find commands
   are missing `-name '.*' -prune`. All three scripts (`scan-files.sh`,
   `scaffold-bundle.sh`, `verify-bundle.sh`) now handle this, but
   watch for regressions.

2. **Moving files breaks script paths** — When Phase 4 moves data
   files into `samples/` or code into `scripts/`, any hardcoded
   relative paths inside those files must be updated. For Python
   scripts, the typical fix is changing `Path(__file__).parent` to
   `Path(__file__).parent.parent / 'samples'`.

3. **Concept doc links must track file moves** — After Phase 4,
   every concept `.md` that references a moved file needs its links
   updated (e.g., `./data.csv` → `./samples/data.csv`). Also update
   the `index.md`. Missing this causes link resolution failures in
   Phase 9.

4. **README with frontmatter** — When absorbing a README that has
   YAML frontmatter, the frontmatter MUST be stripped. `index.md`
   is a reserved file and must have no frontmatter. The scaffold
   script handles this via awk, but if you manually merge, remember
   to strip it.

5. **Co-locate vs. reserved dir decision** — Phase 4 allows
   co-locating small files next to their concept doc OR grouping into
   reserved dirs. For bundles with many data files, prefer reserved
   dirs (`samples/`, `scripts/`) to keep the root clean. For bundles
   with 1-2 tightly coupled files, co-location is fine.

## Supporting Files

Skill directory: ~/.agents/skills/okf-bundle-setup

- scripts/scaffold-bundle.sh → load_skill(name: "okf-bundle-setup/scripts/scaffold-bundle.sh")
- scripts/scan-files.sh → load_skill(name: "okf-bundle-setup/scripts/scan-files.sh")
- scripts/verify-bundle.sh → load_skill(name: "okf-bundle-setup/scripts/verify-bundle.sh")
- references/okf-spec-summary.md → load_skill(name: "okf-bundle-setup/references/okf-spec-summary.md")

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 01:55 | v1.1 — Fixed default path to `~/.agents/knowledge/` (USER scope), updated examples |
| 2026-06-25 22:52 | v1.0 — Initial skill |
