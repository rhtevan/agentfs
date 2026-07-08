---
type: Reference
title: OKF v0.1 Specification Summary
description: >
  Condensed reference of Open Knowledge Format v0.1 rules for quick
  consultation during bundle setup. Derived from the full SPEC.md.
tags: [okf, specification, reference]
timestamp: 2026-06-25T00:00:00Z
---

# Open Knowledge Format v0.1 — Quick Reference

Source: [OKF SPEC.md](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)

---

## Core Idea

A **knowledge bundle** is a directory tree of **markdown files** with
**YAML frontmatter**. No tooling required — `cat` to read, `git` to
version.

---

## Directory Naming Convention

All bundle and sub-bundle directory names **MUST** use **lowercase
kebab-case**:

- Only lowercase letters (`a-z`), digits (`0-9`), and hyphens (`-`)
- No underscores, spaces, uppercase, or special characters
- Maximum **25 characters**
- Must not start or end with a hyphen

```
✅  rca-labeled-dataset    sales-data    ml-training-configs
❌  rca_labeled_dataset    RCA-Data      my data    My_Reports
```

Normalization: lowercase → replace `_` and spaces with `-` → strip
invalid characters → collapse consecutive hyphens → trim edges →
truncate to 25 chars.

Reserved directory names (`assets`, `scripts`, `samples`, `references`,
`templates`, `archive`) are exempt from the 25-char limit but still
conform to lowercase kebab-case by definition.

---

## Bundle Structure

```
bundle/
├── index.md              # Directory listing — NO frontmatter (§6)
├── log.md                # Update history — NO frontmatter (§7)
├── <concept>.md          # Concept at the root level
└── <subdirectory>/       # Group of concepts
    ├── index.md
    ├── <concept>.md
    └── <subdirectory>/
        └── …
```

### Reserved Filenames

| Filename   | Purpose                        | Frontmatter? |
|------------|--------------------------------|:------------:|
| `index.md` | Directory listing (§6)        | **NO**       |
| `log.md`   | Chronological update log (§7) | **NO**       |

All other `.md` files are **concept documents**.

### README Absorption Rule

A bundle must **not** have both a `README.md` (or any case/extension
variant: `readme.md`, `README.txt`, `README.rst`, etc.) and an
`index.md`. If a README exists when the bundle is set up, its body
(frontmatter stripped) becomes `index.md` and the README is removed.
This eliminates the common duplication where both files describe the
same directory.

### Reserved Directory Names

The following names are reserved for organizing non-markdown helper
files. They are **not** sub-bundles — they receive no `index.md`, no
recursive processing, and must not be semantically renamed:

| Name | Purpose |
|------|---------|
| `assets/` | Images, diagrams, media, binary attachments |
| `samples/` | Data samples and example files |
| `references/` | External documents, PDFs, archived web pages |
| `scripts/` | Code files, automation, utilities |
| `templates/` | Reusable file templates and boilerplate |
| `archive/` | Superseded or historical content kept for provenance |

These names are reserved **at every level** of the bundle tree.
Sub-bundles must not use these names — if a directory with a reserved
name actually contains concept `.md` files, it must be renamed.

---

## Concept Documents (§4)

Every concept `.md` file has:

1. **YAML frontmatter** — delimited by `---`
2. **Markdown body** — free-form content

### Frontmatter Fields

| Field | Required? | Description |
|-------|:---------:|-------------|
| `type` | **YES** | Kind of concept (e.g., `BigQuery Table`, `Metric`, `Playbook`). Not centrally registered. |
| `title` | recommended | Human-readable display name. |
| `description` | recommended | One-line summary. |
| `resource` | recommended | Canonical URI for the underlying asset (omit for abstract concepts). |
| `tags` | optional | YAML list of short strings. |
| `timestamp` | optional | ISO 8601 datetime of last meaningful change. |

Extra keys are allowed; consumers must preserve unknown keys.

### Body Conventions

| Heading | Conventional meaning |
|---------|---------------------|
| `# Schema` | Columns / fields of an asset |
| `# Examples` | Concrete usage examples |
| `# Citations` | External sources (see §8) |

Use structural markdown (headings, tables, code blocks) over prose.

---

## Index Files (§6)

- **No YAML frontmatter.**
- List contents with links and descriptions:

```markdown
# Section Heading

* [Title](relative-path.md) - short description
* [Subdirectory](subdir/index.md) - short description
```

---

## Log Files (§7)

- **No YAML frontmatter.**
- **Reverse chronological order** — newest entries **first**, oldest
  last. The most recent `## YYYY-MM-DD` section must appear
  immediately after the `# Directory Update Log` heading.
- Grouped under **ISO 8601 date headings** (`## YYYY-MM-DD`).
- Each entry is a bullet point with a boldface action tag.
- The `okf-bundle-setup` skill **must** log every material change it
  makes (renames, file moves, concept doc creation, index updates).

```markdown
# Directory Update Log

## 2026-06-25
* **Reorganization**: Moved 7 data files → `samples/`, 1 script → `scripts/`.
* **Update**: Regenerated root index.md with final structure.
* **Creation**: Created 8 concept documents for data assets.

## 2026-06-20
* **Initialization**: Created OKF knowledge bundle structure.
```

Action tags: `**Initialization**`, `**Rename**`, `**Reorganization**`,
`**Creation**`, `**Update**`, `**Absorption**`, `**Deletion**`.

---

## Cross-linking (§5)

Two forms:

| Form | Syntax | Notes |
|------|--------|-------|
| Bundle-relative | `[text](/path/to/concept.md)` | Starts with `/`, relative to bundle root. **Recommended.** |
| Relative | `[text](./sibling.md)` or `[text](../other.md)` | Standard relative paths. |

Links express relationships; the kind of relationship is conveyed by
surrounding prose, not by the link syntax.

Consumers **must tolerate broken links** — they may point to
not-yet-written knowledge.

---

## Citations (§8)

List external sources under `# Citations`, numbered:

```markdown
# Citations

[1] [Source title](https://example.com/page)
[2] [Internal reference](/references/guide.md)
```

Citations may link into a `references/` subdirectory that mirrors
external material as first-class OKF concepts.

---

## Non-Markdown File Placement

OKF does not prescribe rules for non-`.md` files — they are invisible
to conformance checks. Recommended conventions:

| File type | Placement |
|-----------|-----------|
| Domain schemas (`.sql`, `.proto`, `.json` schema) | Co-locate next to the concept `.md` that describes them |
| Images / diagrams (`.png`, `.svg`) | `assets/` subdirectory at the same level as the referencing concept |
| Data samples (`.csv`, `.jsonl`) | Co-locate next to the concept `.md`, or in a `samples/` subdirectory |
| External docs (`.pdf`, `.html`) | `references/` subdirectory (per §8) |
| Code (`.py`, `.sh`, `.js`) | Co-locate if tightly coupled; `scripts/` subdirectory otherwise |
| Config (`.yaml`, `.toml`) | Co-locate next to the concept `.md` they belong to |

Link to non-md files from concept documents using standard markdown:
- Files: `[schema.sql](./schema.sql)`
- Images: `![diagram](./assets/arch.png)`

---

## Conformance (§9)

A bundle is **OKF v0.1 conformant** when:

1. Every non-reserved `.md` has parseable YAML frontmatter.
2. Every frontmatter has a non-empty `type` field.
3. Reserved files (`index.md`, `log.md`) follow §6 / §7 format.

Consumers must **not** reject a bundle for:
- Missing optional fields
- Unknown `type` values
- Unknown extra frontmatter keys
- Broken cross-links
- Missing `index.md` files
