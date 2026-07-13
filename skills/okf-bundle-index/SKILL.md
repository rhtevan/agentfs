---
name: okf-bundle-index
description: >
  Check and fix links in index.md files recursively across an OKF
  knowledge bundle. Detects broken links, missing entries, and absent
  index.md files, then repairs them to restore full OKF conformance.
  Fully compliant with Open Knowledge Format v0.1.
metadata:
  tags: [agentfs, okf, knowledge, index, links]
---

# OKF Bundle Index

Audit and repair `index.md` files throughout an **Open Knowledge
Format (OKF) v0.1** knowledge bundle tree.

For the full OKF specification, see
`load_skill(name: "okf-bundle-setup/references/okf-spec-summary.md")`.

## Prerequisites

- **bash** available (for audit / rebuild scripts)
- Write access to the bundle directory

## Inputs

The skill accepts an **optional** bundle root path argument:

| Input | Example | Behaviour |
|-------|---------|-----------|
| *(none)* | `"check my bundle index links"` | Use `~/.agents/knowledge/` as the bundle root |
| Explicit path | `"fix index links in docs/catalog"` | Use the given path as the bundle root |

---

## OKF index.md Rules (reference)

These rules govern every `index.md` in the bundle tree:

- **No YAML frontmatter** — `index.md` is a reserved infrastructure
  file (OKF §6). It must never begin with `---`.
- **Directory listing format** — entries use:
  `* [Title](relative-path) - description`
- Links use **relative paths** (`file.md`, `sub-dir/index.md`, `./file.md`).
- Every concept `.md` file (not `index.md`, not `log.md`) in the
  directory should be listed.
- Every **sub-bundle directory** (non-reserved, non-hidden) should be
  listed.
- **Reserved directories** (`assets/`, `samples/`, `references/`,
  `scripts/`, `templates/`, `archive/`) are NOT sub-bundles and are
  typically **not** listed unless they contain noteworthy reference
  material the author chose to surface.
- `log.md` is **not** listed in `index.md`.

---

## Procedure

Execute these phases **in order**.

### Phase 1 — Resolve the bundle root

1. If no path was given, set `BUNDLE_ROOT` to `~/.agents/knowledge/`.
2. If an explicit path was given, resolve it against the current
   working directory.
3. Verify the directory exists:
   ```bash
   [[ -d "$BUNDLE_ROOT" ]] || { echo "Bundle root not found: $BUNDLE_ROOT"; exit 1; }
   ```

### Phase 2 — Discover all auditable directories

Find every directory in the bundle tree that should have an `index.md`.
This includes the **bundle root** and all **sub-bundle directories**.

**Exclude:**
- Hidden directories (starting with `.`)
- Reserved directories and everything nested beneath them

```bash
find "$BUNDLE_ROOT" -type d \( \
    -name '.*' -o -name assets -o -name samples \
    -o -name references -o -name scripts \
    -o -name templates -o -name archive \
  \) -prune -o -type d -print | sort
```

### Phase 3 — Audit each directory

For each directory found in Phase 2, run:

```bash
bash <skill-dir>/scripts/audit-index.sh "$DIR"
```

#### Output format

```
=== AUDIT: <dir-path> ===
INDEX: EXISTS | MISSING
[WARNING: index.md has YAML frontmatter (violates OKF §6)]

--- BROKEN LINKS ---
<link-path>
(none)

--- MISSING ENTRIES ---
CONCEPT|<filename>|<title>|<description>
SUB-BUNDLE|<dirname>/|<title>|
(none)
```

**Collect all audit results** before proceeding to fixes. This gives
a complete picture and avoids unnecessary re-scans.

### Phase 4 — Fix: Create missing index.md files

For any directory where the audit reports `INDEX: MISSING`, generate
a fresh `index.md` using the rebuild script:

```bash
bash <skill-dir>/scripts/rebuild-index.sh "$DIR" > "$DIR/index.md"
```

The rebuild script:
- Derives a title from the directory name (or an existing heading)
- Lists all concept `.md` files with titles and descriptions
  extracted from their YAML frontmatter
- Lists all sub-bundle directories with titles and descriptions
  extracted from their `index.md` (first paragraph after the heading)
- Outputs a complete, **no-frontmatter** `index.md` to stdout

After generating, review the output and adjust if needed (e.g., add
descriptive prose, reorder entries, group by theme).

**Optional title override:**
```bash
bash <skill-dir>/scripts/rebuild-index.sh "$DIR" "Custom Title" > "$DIR/index.md"
```

### Phase 5 — Fix: Repair broken links

For each broken link found in Phase 3:

1. **Search for the target** — it may have been renamed or moved:
   ```bash
   find "$BUNDLE_ROOT" -name "$(basename "$BROKEN_PATH")" -not -path '*/.*'
   ```
2. **If found at a new location** — update the link path in
   `index.md` to the correct relative path.
3. **If truly deleted** — remove the entire entry line from
   `index.md`.

Use the `edit` tool for surgical link fixes. If many links are broken,
regenerate the entire `index.md` via `rebuild-index.sh` instead.

### Phase 6 — Fix: Add missing entries

For each missing entry reported in Phase 3, add a properly formatted
line to the directory's `index.md`.

**Concept files** — use the title and description from the audit
output:
```markdown
* [<title>](<filename>) - <description>
```
If no description was reported, either omit the ` - <description>`
suffix or generate a brief one by reading the file's content.

**Sub-bundle directories** — use the title from the audit output:
```markdown
* [<title>](<dirname>/index.md)
```

#### Insertion position

- If the `index.md` already groups concepts and sub-bundles into
  separate sections, insert into the correct section.
- Within a section, prefer **alphabetical order** unless an existing
  thematic ordering is apparent.
- If in doubt, append to the end of the listing.

### Phase 7 — Re-audit to verify

Re-run the audit script on **every directory that had issues**:

```bash
bash <skill-dir>/scripts/audit-index.sh "$DIR"
```

All directories should now report:
- `INDEX: EXISTS`
- `--- BROKEN LINKS ---` → `(none)`
- `--- MISSING ENTRIES ---` → `(none)`

If any issues remain, repeat Phases 5–6 for those directories.

### Phase 8 — Log changes

If any changes were made, record them in the bundle root's `log.md`.

**Preferred** — use the `merge-log-entry.sh` script from
`okf-bundle-gen`:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  "$BUNDLE_ROOT/log.md" \
  "* **Update**: Audited index.md files — fixed N broken link(s), added M missing entry/entries, created K new index file(s)."
```

**Manual alternative** (if `okf-bundle-gen` is not available) —
prepend a dated entry to `log.md` in reverse chronological order
(newest `## YYYY-MM-DD` section first):

```bash
TODAY="$(date +%Y-%m-%d)"
{
  head -2 "$BUNDLE_ROOT/log.md"              # preserve heading + blank line
  echo "## $TODAY"
  echo ""
  echo "* **Update**: Audited index.md files — fixed N broken link(s), added M missing entry/entries, created K new index file(s)."
  echo ""
  tail -n +3 "$BUNDLE_ROOT/log.md"           # existing entries
} > "$BUNDLE_ROOT/log.md.tmp"
mv "$BUNDLE_ROOT/log.md.tmp" "$BUNDLE_ROOT/log.md"
```

If no changes were made (all audits clean), skip logging.

---

## Quality Checklist

After completing all phases, confirm:

- [ ] Every sub-bundle directory has an `index.md`
- [ ] No `index.md` contains YAML frontmatter
- [ ] Every link in every `index.md` resolves to an existing target
- [ ] Every concept `.md` file is listed in its parent directory's
      `index.md`
- [ ] Every sub-bundle directory is listed in its parent directory's
      `index.md`
- [ ] Reserved directories are not listed as sub-bundles
- [ ] `log.md` entry recorded (if any changes were made)

---

## Example

### Before

```
~/.agents/knowledge/
├── index.md              ← links to deleted-concept.md (broken)
│                           missing entry for new-concept.md
├── new-concept.md        ← not listed in index.md
├── log.md
└── session-alpha/        ← sub-bundle
    ├── index.md          ← missing entry for design.md
    ├── overview.md
    └── design.md         ← not listed in session-alpha/index.md
```

### Audit output

```
=== AUDIT: ~/.agents/knowledge ===
INDEX: EXISTS

--- BROKEN LINKS ---
deleted-concept.md

--- MISSING ENTRIES ---
CONCEPT|new-concept.md|New Concept|A recently added concept

=== AUDIT: ~/.agents/knowledge/session-alpha ===
INDEX: EXISTS

--- BROKEN LINKS ---
(none)

--- MISSING ENTRIES ---
CONCEPT|design.md|Design|System design decisions
```

### After

```
~/.agents/knowledge/
├── index.md              ← broken link removed, new-concept.md added
├── new-concept.md
├── log.md                ← updated with audit entry
└── session-alpha/
    ├── index.md          ← design.md entry added
    ├── overview.md
    └── design.md
```

---

## Supporting Files

Skill directory: ~/.agents/skills/okf-bundle-index

- scripts/audit-index.sh → `load_skill(name: "okf-bundle-index/scripts/audit-index.sh")`
- scripts/rebuild-index.sh → `load_skill(name: "okf-bundle-index/scripts/rebuild-index.sh")`

### Cross-skill dependencies

- `okf-bundle-gen` scripts: `merge-log-entry.sh` (Phase 8 logging)
- `okf-bundle-setup` scripts: `verify-bundle.sh` (optional full
  conformance check after index repair)

### Recommended workflow

Run `okf-bundle-index` after `okf-bundle-gen` or `okf-bundle-harvest`
to ensure all index entries are present and links are valid in
`~/.agents/knowledge/`. This catches gaps such as a new sub-bundle
not listed in the root `index.md`, or concept files added without
corresponding index entries.

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 02:09 | v1.3 — `rebuild-index.sh` now extracts sub-bundle descriptions from their `index.md` (first paragraph after heading), truncated to 120 chars |
| 2026-07-09 01:55 | v1.2 — Fixed default path to `~/.agents/knowledge/` (USER scope), removed obsolete `okf-bundle-merge` reference |
| 2026-06-25 23:20 | v1.0 — Initial skill |
