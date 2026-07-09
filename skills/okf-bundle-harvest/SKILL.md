---
name: okf-bundle-harvest
description: >
  Harvest concepts from MEMORY.md files across one or more projects and
  distill them into OKF-compliant knowledge bundles under ~/.agents/knowledge/.
  Scans default agent and named profile memories, identifies graduation
  candidates (generalizable patterns that transcend a single project),
  creates or merges concept documents, and removes graduated entries from
  source MEMORY.md files. Implements the graduation path defined in
  AgentFS Guardrail #8. Fully compliant with Open Knowledge Format v0.1.
argument-hint: "Optionally specify project paths: 'harvest from ~/projects/foo and ~/projects/bar'"
compatibility: "Requires AgentFS setup (agentfs-setup skill) with MEMORY.md files"
metadata:
  author: agentfs
  version: "1.0"
  tags: [agentfs, okf, knowledge, memory, distillation, graduation]
user-invocable: true
disable-model-invocation: false
---

# OKF Bundle Harvest — Memory-to-Knowledge Distillation

Harvest generalizable concepts from project-scoped `MEMORY.md` files and
distill them into OKF-compliant knowledge bundles under `~/.agents/knowledge/`.

This skill implements the **graduation path** defined in AgentFS Guardrail #8:

> When an observation in `MEMORY.md` matures into cross-project knowledge
> worth preserving, graduate it to an OKF knowledge bundle under
> `~/.agents/knowledge/` and remove the original entry.

## How It Differs from `okf-bundle-gen`

| Aspect | `okf-bundle-gen` | `okf-bundle-harvest` |
|--------|------------------|----------------------|
| **Primary input** | Current chat session context | MEMORY.md files on disk |
| **Scope** | Single session, single project | One or many projects |
| **Pattern source** | Session + memories as side-effect | Memories as primary input |
| **Lifecycle action** | Capture (session → knowledge) | Graduate (memory → knowledge, then prune) |
| **When to use** | End of a productive session | Periodically, to distill accumulated experiences |

## Prerequisites

- At least one project with AgentFS set up (`.agents/` directory)
- MEMORY.md files with `§`-delimited entries
- Write access to `~/.agents/knowledge/`
- The `okf-bundle-setup` skill must be available (scripts reused)

## Fixed Configuration

| Setting | Value |
|---------|-------|
| Knowledge root | `~/.agents/knowledge/` |
| Harvest sub-bundle | `~/.agents/knowledge/harvest-<YYYY-MM-DD>/` |
| OKF version | v0.1 |

---

## Usage

### Harvest from current project

> harvest knowledge from project memories

Scans `./.agents/memories/` and `./.agents/profiles/*/memories/` in
the current working directory.

### Harvest from specific projects

> harvest knowledge from ~/projects/foo and ~/projects/bar

Scans the `.agents/` directory in each specified project root.

### Harvest from all known projects

> harvest knowledge from all my projects

The agent should ask the user to provide project paths, or scan
common locations if the user confirms.

---

## Procedure

Execute these phases **in order**.

### Phase 1 — Determine scope and scan memories

#### 1a. Identify project roots to scan

Based on user input, determine which project roots to scan:

- **Current project** (default): use `$(pwd)`
- **Explicit list**: user provides paths like `~/projects/foo`
- **Multiple projects**: iterate over each provided path

For each project root, verify `.agents/` exists:

```bash
for project in "${PROJECT_ROOTS[@]}"; do
  if [[ ! -d "$project/.agents" ]]; then
    echo "SKIP: $project — no .agents/ directory"
    continue
  fi
fi
```

#### 1b. Scan all MEMORY.md files

For each valid project root, run the memory scanner:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/scan-memories.sh "$project/.agents"
```

This outputs all `§`-delimited entries from:

| Source | Files |
|--------|-------|
| Default agent | `.agents/memories/MEMORY.md`, `.agents/memories/USER.md` |
| Named profiles | `.agents/profiles/*/memories/MEMORY.md`, `.agents/profiles/*/memories/USER.md` |

Collect the output, tagging each entry with its **source project path**
and **source file** for traceability.

#### 1c. Aggregate and deduplicate

Combine entries from all scanned projects into a single inventory.
Note duplicates (same observation recorded in multiple projects or
profiles) — these are strong graduation candidates.

### Phase 2 — Identify graduation candidates

Analyze the aggregated entries to find knowledge worth graduating.
Not every memory entry should become knowledge — only entries that
meet the graduation criteria.

#### Graduation criteria

An entry (or group of related entries) qualifies for graduation when
it meets **at least one** of these conditions:

| Criterion | Signal | Example |
|-----------|--------|---------|
| **Cross-project recurrence** | Same observation appears in ≥2 projects | "Always pin Go version in Makefile" found in project-A and project-B |
| **Cross-profile recurrence** | Same observation from ≥2 profiles/roles | Both default agent and security-reviewer note the same pattern |
| **Generalizability** | The observation is not tied to a specific codebase | "eBPF programs need CAP_BPF on kernel ≥5.8" — true everywhere |
| **Maturity** | The entry has been stable over time (not a one-time note) | Entry present across multiple sessions without contradiction |
| **Abstraction potential** | Multiple concrete entries can be abstracted into a higher-order pattern | "Prefers label-free ML" + "Favors unsupervised approaches" → design philosophy |

#### Non-graduation criteria (keep as memory)

Do NOT graduate entries that are:

- **Project-specific**: "The `inventory` service uses Redis 7.2.1" — only relevant to that project
- **Ephemeral**: "CI is broken this week due to infra migration" — temporary
- **Personal task reminders**: "TODO: refactor auth module" — action items, not knowledge
- **Already graduated**: Check `~/.agents/knowledge/` to avoid duplicating existing concepts

#### Output of Phase 2

A list of graduation candidates, each with:

1. **Source entries** — which MEMORY.md entries contribute to this concept
   (project path + file + entry content)
2. **Concept ID** — proposed kebab-case filename
3. **Type** — concept type (see table below)
4. **Title** — human-readable name
5. **Description** — one-line summary
6. **Tags** — categorization strings
7. **Category** — which sub-bundle or subdirectory this belongs in

**Concept types for harvested knowledge:**

| Type | When to use |
|------|-------------|
| `Pattern` | Abstracted from multiple entries — a higher-order observation |
| `Lesson` | A concrete, generalizable lesson learned from experience |
| `Convention` | A practice or standard that proved effective |
| `Reference` | A factual reference (tool behavior, API quirk, compatibility info) |
| `Troubleshooting` | A problem/solution pair that applies broadly |

### Phase 3 — Inspect existing knowledge bundle

Check what already exists in `~/.agents/knowledge/` to plan merges:

```bash
if [[ -d "$HOME/.agents/knowledge" ]]; then
  bash ~/.agents/skills/okf-bundle-gen/scripts/list-existing-concepts.sh \
    "$HOME/.agents/knowledge"
fi
```

Also check the `agent-patterns/` sub-bundle specifically:

```bash
if [[ -d "$HOME/.agents/knowledge/agent-patterns" ]]; then
  bash ~/.agents/skills/okf-bundle-gen/scripts/list-existing-concepts.sh \
    "$HOME/.agents/knowledge/agent-patterns"
fi
```

Read existing `index.md` and `log.md` to understand current state.

### Phase 4 — Plan the write (merge strategy)

For each graduation candidate from Phase 2:

#### 4a. Match against existing concepts

Compare each candidate against the existing inventory (Phase 3).
Use **semantic matching**, not just filename comparison.

#### 4b. Decide action and placement

| Situation | Action | Placement |
|-----------|--------|-----------|
| New pattern (abstracted from ≥2 entries) | **Create** | `~/.agents/knowledge/agent-patterns/` |
| New lesson/convention/reference | **Create** | `~/.agents/knowledge/harvest-<date>/` |
| Matches existing concept — adds new info | **Update** | Existing location |
| Matches existing concept — already covered | **Skip** | — |
| Matches existing pattern — new evidence | **Update** | Add to "Derived From" table |

#### 4c. Plan source cleanup

For each graduated entry, record which MEMORY.md file and which
entry content should be removed in Phase 7.

**Output:** A structured write plan, e.g.:

```
CREATE  agent-patterns/go-version-pinning.md     — type: Pattern (from project-A + project-B)
CREATE  harvest-2026-07-09/ebpf-cap-bpf.md       — type: Reference
UPDATE  agent-patterns/design-philosophy.md       — add new evidence
SKIP    (redis version note)                      — project-specific, keep as memory
PRUNE   project-A/.agents/memories/MEMORY.md      — remove entry "Always pin Go version..."
PRUNE   project-B/.agents/memories/MEMORY.md      — remove entry "Pin Go version in Makefile..."
```

### Phase 5 — Scaffold bundles

Ensure the knowledge root and target sub-bundles exist:

```bash
# Knowledge root
mkdir -p ~/.agents/knowledge
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge

# Harvest sub-bundle (if any non-pattern concepts)
HARVEST_DIR="$HOME/.agents/knowledge/harvest-$(date +%Y-%m-%d)"
mkdir -p "$HARVEST_DIR"
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh "$HARVEST_DIR"

# Agent-patterns sub-bundle (if any patterns)
mkdir -p ~/.agents/knowledge/agent-patterns
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge/agent-patterns
```

### Phase 6 — Write concept documents

Execute the write plan from Phase 4.

#### Creating a new concept

Write OKF-conformant concept documents:

```markdown
---
type: <Type>
title: <Title>
description: <One-line summary>
tags: [<tag1>, <tag2>]
timestamp: <current ISO 8601 datetime>
---

<Markdown body — distilled, self-contained, structured>

## Harvested From

| Project | Source | Entry |
|---------|--------|-------|
| ~/projects/foo | default-agent/MEMORY | "Always pin Go version in Makefile" |
| ~/projects/bar | default-agent/MEMORY | "Pin Go version — CI broke when auto-updated" |

## Implications

<What this means for future work, how agents should apply this knowledge>
```

**Body writing guidelines:**

- Write for a **future reader** with no access to the original context
- Use **structural markdown** — headings, bullet lists, tables, code blocks
- **Distill**, don't copy — abstract the underlying principle from the
  concrete observations
- Include the **"Harvested From" table** (mandatory) — provides
  traceability back to source entries
- Cross-link to related concepts using relative paths
- Do NOT include project-specific details that don't generalize

#### Creating a pattern concept

Pattern concepts (in `agent-patterns/`) follow the structure defined
in `okf-bundle-gen` SKILL.md — include `Derived From` table,
`Manifestations`, and `Implications` sections.

#### Updating an existing concept

1. Read the existing file completely
2. Append new evidence to the "Harvested From" or "Derived From" table
3. Extend sections with new information
4. Update the `timestamp` field
5. Add new `tags` (merge, don't replace)
6. Preserve existing content that's still accurate

### Phase 7 — Prune graduated entries from MEMORY.md

For each graduated entry, remove it from its source MEMORY.md file.

```bash
bash ~/.agents/skills/okf-bundle-harvest/scripts/prune-memory.sh \
  <MEMORY_FILE> \
  "<entry-content-to-remove>"
```

The prune script:
1. Reads the MEMORY.md file
2. Finds the `§`-delimited entry matching the content
3. Removes it (including the `§` delimiter)
4. Writes the file back
5. Reports what was removed

**Safety rules:**

- Only remove entries that were actually graduated (written to knowledge)
- Never remove ALL entries — if a MEMORY.md would become empty, leave
  it with just the file header or a note
- Create a backup before modifying: `cp MEMORY.md MEMORY.md.bak.<timestamp>`
- If a project root is read-only, skip pruning for that project and warn

### Phase 8 — Update indexes and logs

#### 8a. Sub-bundle index files

Rewrite `index.md` for each sub-bundle that received new concepts:

```markdown
# Harvest 2026-07-09

Knowledge graduated from project memories on 2026-07-09.

* [eBPF CAP_BPF](ebpf-cap-bpf.md) - eBPF requires CAP_BPF on kernel ≥5.8
* [Go Module Tidying](go-module-tidy.md) - Always run go mod tidy before commit
```

#### 8b. Agent-patterns index

Update `~/.agents/knowledge/agent-patterns/index.md` with complete
listing of all pattern concepts (not just new ones).

#### 8c. Knowledge root index

Update `~/.agents/knowledge/index.md` to include entries for all
sub-bundles. Preserve existing entries.

#### 8d. Log files

Update log files at both levels:

```bash
# Root log
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/knowledge/log.md \
  "* **Harvest**: Graduated N concepts from M project(s). Created harvest-<date>/ sub-bundle.
* **Prune**: Removed N graduated entries from source MEMORY.md files.
* **Update**: Updated root index.md."

# Sub-bundle log
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/knowledge/harvest-<date>/log.md \
  "* **Creation**: Harvested N concepts from project memories.
* **Sources**: <list of project paths scanned>"
```

#### 8e. Update USER-scope log

Since knowledge is USER-scoped, update `~/.agents/log.md`:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/log.md \
  "* **Harvest**: Graduated N concepts from MEMORY.md files across M project(s) into knowledge bundles"
```

### Phase 9 — Verify conformance

Run verification against the full knowledge bundle:

```bash
bash ~/.agents/skills/okf-bundle-setup/scripts/verify-bundle.sh ~/.agents/knowledge
```

Fix any `[✗]` items and re-run until fully conformant.

---

## Quality Checklist

Before completing, verify:

- [ ] Only entries meeting graduation criteria were harvested
- [ ] Every concept has a **"Harvested From" table** with source traceability
- [ ] Pattern concepts have a **"Derived From" table** (≥2 source entries)
- [ ] Project-specific details were NOT included in concept bodies
- [ ] Graduated entries were **removed** from source MEMORY.md files
- [ ] MEMORY.md backups were created before pruning
- [ ] Every concept `.md` has YAML frontmatter with required `type` field
- [ ] `index.md` files updated at all levels (no YAML frontmatter)
- [ ] `log.md` files updated at all levels (newest first)
- [ ] `~/.agents/log.md` updated to reflect the harvest

- [ ] `verify-bundle.sh` passes with zero failures
- [ ] No broken cross-links in concept documents
- [ ] All directory names are lowercase kebab-case, ≤25 characters

---

## Example Scenario

Given two projects with these MEMORY.md entries:

**Project A** (`.agents/memories/MEMORY.md`):
```
§ Always pin Go version in Makefile — CI broke when Go auto-updated from 1.22 to 1.23
§ The inventory service requires Redis 7.2.1 specifically
§ eBPF programs need CAP_BPF capability on kernel ≥5.8
```

**Project B** (`.agents/memories/MEMORY.md`):
```
§ Pin Go version in go.mod AND Makefile — learned this the hard way
§ NetworkPolicy CRDs must be applied before deploying pods
```

**Harvest result:**

| Entry | Action | Reason |
|-------|--------|--------|
| Go version pinning (A+B) | **Graduate** → `agent-patterns/go-version-pinning.md` | Cross-project recurrence, generalizable |
| eBPF CAP_BPF (A) | **Graduate** → `harvest-2026-07-09/ebpf-cap-bpf.md` | Generalizable reference, not project-specific |
| Redis 7.2.1 (A) | **Keep** in MEMORY.md | Project-specific — only relevant to project A |
| NetworkPolicy ordering (B) | **Graduate** → `harvest-2026-07-09/netpol-ordering.md` | Generalizable Kubernetes lesson |

After harvest:
- Project A `MEMORY.md`: only Redis entry remains
- Project B `MEMORY.md`: empty (or header only)
- `~/.agents/knowledge/agent-patterns/go-version-pinning.md`: created
- `~/.agents/knowledge/harvest-2026-07-09/`: 2 new concepts

---

## Pitfalls

1. **Over-harvesting** — Not every memory deserves graduation. If in
   doubt, leave it as memory. Knowledge bundles should contain
   high-quality, generalizable content.

2. **Under-pruning** — After graduating an entry, always remove it
   from the source MEMORY.md. Leaving graduated entries as memories
   creates the same duplicate-storage problem that memory collision
   avoidance tries to solve.

3. **Single-entry patterns** — A pattern must be derived from ≥2
   distinct entries. A single observation restated at a higher level
   of abstraction is a `Lesson`, not a `Pattern`.

4. **Project-specific knowledge leaking** — When distilling, strip
   project-specific details. "Redis 7.2.1 is required by inventory
   service" stays as memory. "Redis 7.x has breaking changes in
   cluster mode ACLs" could be knowledge.

5. **Read-only projects** — If a project root is on a read-only
   filesystem, skip the prune step for that project. Warn the user
   and list the entries that should be manually removed.

## Supporting Files

Skill directory: `~/.agents/skills/okf-bundle-harvest`

- `scripts/prune-memory.sh` — Remove graduated entries from MEMORY.md
- `scripts/harvest-summary.sh` — Generate a summary report of harvest candidates

Dependencies (from `okf-bundle-gen`):
- `scripts/scan-memories.sh` — Scan and display MEMORY.md entries
- `scripts/list-existing-concepts.sh` — Inventory existing concepts
- `scripts/merge-log-entry.sh` — Append entries to log.md

Dependencies (from `okf-bundle-setup`):
- `scripts/scaffold-bundle.sh` — Create OKF bundle structure
- `scripts/verify-bundle.sh` — Verify OKF conformance
- `references/okf-spec-summary.md` — OKF v0.1 quick reference

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 01:40 | v1.1 — Removed Phase 9 (SOUL.md pattern link injection); knowledge discovery now via global .goosehints progressive loading |
| 2026-07-09 00:53 | v1.0 — Initial skill: multi-project memory scanning, graduation criteria, concept distillation, MEMORY.md pruning, OKF-compliant output |
