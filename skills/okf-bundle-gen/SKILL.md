---
name: okf-bundle-gen
description: >
  Generate an OKF-compliant knowledge bundle from the current chat session
  context AND accumulated agent memories. Writes concept documents into
  ~/.agents/knowledge/ as the bundle root. Scans all MEMORY.md and USER.md
  files under ./.agents/ (default agent + named profiles) to extract
  higher-order patterns into a dedicated agent-patterns/ sub-bundle.
  Session-specific knowledge goes into per-session sub-bundles. Fully
  compliant with Open Knowledge Format v0.1.
---

# OKF Bundle Generation from Session Context

Extract knowledge from the **current chat session** and persist it as an
OKF v0.1 knowledge bundle under `~/.agents/knowledge/`.

Additionally, scan all **accumulated agent memories** (MEMORY.md and
USER.md files under `./.agents/`) to extract higher-order patterns —
abstract concepts that emerge from cross-session episodic observations.
These patterns are written to a dedicated `agent-patterns/` sub-bundle.

This skill is a **knowledge-generation** companion to `okf-bundle-setup`
(which organizes existing files). Here the agent is the knowledge
producer — it reads the conversation and memories, identifies concepts
worth preserving, abstracts patterns from episodic observations, and
writes (or merges) OKF-conformant concept documents.

For the full OKF specification, see
`load_skill(name: "okf-bundle-setup/references/okf-spec-summary.md")`.

## Prerequisites

- Write access to the working directory
- The `okf-bundle-setup` skill must be available (its scripts are
  reused for scaffolding and verification)

## Fixed Configuration

| Setting | Value |
|---------|-------|
| Bundle root | `~/.agents/knowledge/` |
| Session sub-bundle | `~/.agents/knowledge/<session-name>/` |
| Patterns sub-bundle | `~/.agents/knowledge/agent-patterns/` |
| Memories scan root | `./.agents/` |
| OKF version | v0.1 |

The bundle root is **not configurable** — this skill always writes to
`~/.agents/knowledge/` (the user-level knowledge directory).

**Concept documents are never placed directly at the bundle root.**
Each invocation writes into a **session sub-bundle** — a subdirectory
under the bundle root whose name represents the session's identity
(see Phase 1). The root `index.md` and `log.md` serve as the
top-level navigation and changelog across all session sub-bundles.

---

## Procedure

Execute these phases **in order**.

### Phase 1 — Determine session identity and analyze context

#### 1a. Derive the session name

Review the **entire conversation history** and determine a short,
descriptive name that captures the session's dominant topic or purpose.

**Naming rules:**
- **Lowercase kebab-case** (`this-style`) — mandatory
- Maximum **25 characters**
- Descriptive of the session's core theme, not generic (avoid names
  like `session-1`, `chat-2026`, `misc-notes`)

Examples:
- A session about setting up OKF bundles → `okf-bundle-creation`
- A session debugging a Kubernetes deployment → `k8s-deploy-debug`
- A session designing a data pipeline → `data-pipeline-design`

This name becomes the session sub-bundle directory:
`~/.agents/knowledge/<session-name>/`

#### 1b. Identify knowledge to persist

Review the **entire conversation history** in this session and identify
knowledge worth persisting. Look for:

| Knowledge signal | Example |
|------------------|---------|
| **Concepts explained** | What OKF is, how bundles are structured |
| **Decisions made** | Chose kebab-case for directory names |
| **Procedures documented** | Step-by-step setup instructions |
| **Facts and data** | Spec rules, conformance criteria |
| **Patterns and conventions** | Where to place non-md files |
| **Relationships** | How skills reference each other |
| **Configurations** | Fixed paths, tool settings |
| **Troubleshooting** | Bash arithmetic + `set -e` pitfall |

For each identified piece of knowledge, determine:

1. **Concept ID** — a short, descriptive filename in kebab-case
   (e.g., `okf-file-placement.md`, `bundle-conformance.md`).
2. **Type** — a descriptive string (e.g., `Specification`, `Convention`,
   `Procedure`, `Decision`, `Reference`, `Troubleshooting`).
3. **Title** — human-readable display name.
4. **Description** — one-line summary.
5. **Tags** — short categorization strings.
6. **Subdirectory** — which group/category this concept belongs to
   within the session sub-bundle (use kebab-case, ≤25 chars). Concepts
   may live at the session sub-bundle root if they don't fit a natural
   group.
7. **Relationships** — which other concepts this one links to.

**Guidance on granularity:**
- One concept per **distinct topic**. Don't create a single monolithic
  doc that covers everything discussed.
- Don't create concepts for trivial exchanges (greetings, clarifying
  questions, simple acknowledgements).
- Combine closely related micro-topics into a single concept rather
  than creating many tiny files.
- Aim for concepts that would be **useful to a future agent or human**
  reading the bundle without access to this conversation.

### Phase 1c — Scan accumulated agent memories

Gather all episodic memory entries from the `./.agents/` directory tree.
This scans both the default agent and any named profiles.

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/scan-memories.sh ./.agents
```

This outputs every `§`-delimited entry from:

| Source | Files |
|--------|-------|
| Default agent | `./.agents/memories/MEMORY.md`, `./.agents/memories/USER.md` |
| Named profiles | `./.agents/profiles/*/memories/MEMORY.md`, `./.agents/profiles/*/memories/USER.md` |

If no memory files exist or all are empty, skip Phase 1d and proceed
to Phase 2. The session-based knowledge extraction (Phase 1b) still
runs independently.

### Phase 1d — Extract higher-order patterns from memories

Analyze the episodic entries gathered in Phase 1c **in aggregate** —
look across entries and across sources for patterns that represent
something more abstract than any single entry.

**What to look for:**

| Pattern type | Signal in entries | Example |
|---|---|---|
| **Reasoning heuristic** | Same preference stated in different contexts or by different agents | "Favors label-free" + "Favors standard over proprietary" → *Design philosophy: generalizable, evidence-based approaches* |
| **Domain bridge** | Two domain-specific entries that connect | "Telecom expert" + "GNN RCA dataset" → *Cross-domain synthesis: maps network operations to graph ML structures* |
| **Meta-cognitive pattern** | Entries about *how* the user thinks | "Challenges conventional approaches" + "Thinks at meta level" → *Reasoning style: first-principles, questions assumptions* |
| **Workflow convention** | Repeated tool/format preferences | "OKF bundles, kebab-case" + "AGENTS.md conventions" → *Standardization bias: prefers portable, cross-agent conventions* |
| **Interaction contract** | Communication/depth preferences | "Prefers deep responses with diagrams" + "Challenges conventional approaches" → *Expects rigorous technical depth as engagement* |

**Filtering rules:**

- Only create a pattern concept when the abstraction is **genuinely
  new** — not already covered by an existing concept in
  `~/.agents/knowledge/agent-patterns/`.
- A pattern must be derived from **at least two** distinct episodic
  entries (single-entry observations stay as memory, not patterns).
- A pattern must be **stable** — it should represent a durable trait,
  not a one-time preference.
- Do **not** create patterns that merely restate a memory entry at
  the same level of abstraction.

For each identified pattern, determine:

1. **Concept ID** — kebab-case filename (e.g., `design-philosophy.md`,
   `reasoning-style.md`).
2. **Type** — always `Pattern`.
3. **Title** — human-readable display name.
4. **Description** — one-line summary.
5. **Tags** — short categorization strings.
6. **Source entries** — which episodic entries (by source + content
   summary) this pattern was derived from. These go into the concept
   body as a "Derived From" section.

**Output:** Add the identified patterns to the write plan alongside
the session-based concepts from Phase 1b. Patterns always target
`~/.agents/knowledge/agent-patterns/`, never a session sub-bundle.

### Phase 2 — Inspect the existing bundle and session sub-bundle

Check whether the **session sub-bundle** already exists:

```bash
BUNDLE_ROOT="$HOME/.agents/knowledge"
SESSION_DIR="$BUNDLE_ROOT/<session-name>"

if [[ -d "$SESSION_DIR" ]] && [[ -n "$(ls -A "$SESSION_DIR" 2>/dev/null)" ]]; then
  echo "Session sub-bundle exists — merge mode"
else
  echo "Session sub-bundle does not exist — fresh mode"
fi
```

**If the session sub-bundle is non-empty**, run the concept inventory
script against it:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/list-existing-concepts.sh "$SESSION_DIR"
```

This lists every existing concept with its path, type, title, and
description. Use this inventory in Phase 3 for merge planning.

Also **read the existing session sub-bundle `index.md`** and the
**root `index.md`** and **`log.md`** so you know the current state of
the bundle's navigation and history.

### Phase 3 — Plan the write (merge strategy)

Build a **write plan** — a list of actions the agent will take. For
each concept identified in Phase 1:

#### 3a. Match against existing concepts

Compare each new concept against the existing inventory (Phase 2).
A concept **matches** if:

- Its topic is substantially the same as an existing concept (even if
  the filename or title differs), OR
- It would naturally extend or update an existing concept document.

Use semantic understanding, not just filename matching. For example,
a new concept about "OKF conformance rules" matches an existing
`bundle-conformance.md` even if the titles differ.

#### 3b. Decide the action

| Situation | Action |
|-----------|--------|
| No match — new topic | **Create** a new concept `.md` file |
| Match — existing concept covers a subset | **Update** the existing file — append new sections, update frontmatter timestamp |
| Match — existing concept already covers everything | **Skip** — no change needed |
| Match — conflict (new info contradicts existing) | **Update** the existing file — revise the conflicting section, note the change |

#### 3c. Plan subdirectory structure

- Group related concepts into subdirectories (sub-bundles).
- Reuse existing subdirectory names when the new concepts fit.
- Create new subdirectories only when a clear new category emerges.
- All directory names: **lowercase kebab-case**, ≤25 characters.
- Never use reserved directory names (`assets`, `samples`,
  `references`, `scripts`, `templates`, `archive`) for sub-bundles.

**Output of this phase** (internal to the agent — not written to disk):

A structured plan, e.g.:

```
CREATE  specifications/okf-overview.md        — type: Specification
CREATE  specifications/bundle-structure.md     — type: Specification
UPDATE  conventions/file-placement.md          — append non-md rules
CREATE  troubleshooting/bash-arithmetic.md     — type: Troubleshooting
SKIP    conventions/naming.md                  — already covered
```

### Phase 4 — Scaffold the bundle root and session sub-bundle

Ensure the **bundle root** and OKF infrastructure exist:

```bash
mkdir -p ~/.agents/knowledge
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge
```

This creates root `index.md` and `log.md` if they don't exist
(idempotent).

Then scaffold the **session sub-bundle**:

```bash
mkdir -p ~/.agents/knowledge/<session-name>
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge/<session-name>
```

Then scaffold the **patterns sub-bundle** (if Phase 1d identified any
new patterns):

```bash
mkdir -p ~/.agents/knowledge/agent-patterns
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge/agent-patterns
```

For any **nested subdirectories** within the session sub-bundle (as
determined by the write plan), create and scaffold each one:

```bash
mkdir -p ~/.agents/knowledge/<session-name>/<subdir>
bash ~/.agents/skills/okf-bundle-setup/scripts/scaffold-bundle.sh ~/.agents/knowledge/<session-name>/<subdir>
```

### Phase 5 — Write concept documents

Execute the write plan from Phase 3. All concept documents are written
into the **session sub-bundle** (`~/.agents/knowledge/<session-name>/`),
never directly at the bundle root.

#### Creating a new concept

Write a new `.md` file with proper OKF frontmatter and body:

```markdown
---
type: <Type>
title: <Title>
description: <One-line summary>
tags: [<tag1>, <tag2>]
timestamp: <current ISO 8601 datetime>
---

<Markdown body — structured with headings, tables, code blocks>

# Citations

[1] [Source](url-or-path) — if applicable
```

**Body writing guidelines:**

- Write for a **future reader** who has no access to this conversation.
  Include enough context to be self-contained.
- Use **structural markdown** — headings, bullet lists, tables, fenced
  code blocks — not wall-of-text prose.
- Include **concrete examples** where the conversation produced them.
- **Cross-link** to related concepts using relative paths:
  `[related concept](./related.md)` or `[other dir](../other/concept.md)`.
- Do **not** include conversational artifacts ("the user asked…",
  "I suggested…"). Write in an objective, reference-document voice.
- Do **not** copy-paste large verbatim blocks from the conversation.
  Distill and restructure the knowledge.

#### Writing a pattern concept (agent-patterns/ sub-bundle)

Pattern concepts have a specific body structure:

```markdown
---
type: Pattern
title: <Title>
description: <One-line summary>
tags: [<tag1>, <tag2>]
timestamp: <current ISO 8601 datetime>
---

<Abstract description of the pattern — what it means, why it matters,
how it manifests in practice.>

## Manifestations

<Concrete examples of how this pattern shows up in interactions,
decisions, or preferences.>

## Derived From

| Source | Entry |
|--------|-------|
| default-agent/USER | "Favors GNN+DRL (label-free) over supervised" |
| default-agent/MEMORY | "Agent-fs uses standard conventions across agents" |

## Implications

<What this pattern means for how agents should interact with this
user, or how solutions should be designed.>
```

The "Derived From" table is **mandatory** for pattern concepts — it
provides traceability back to the episodic entries that generated the
abstraction.

#### Updating an existing concept

1. **Read** the existing file completely.
2. **Identify** which sections need new content, which need revision.
3. **Preserve** existing content that is still accurate.
4. **Append** new sections or extend existing ones.
5. **Update** the `timestamp` field in frontmatter to the current time.
6. **Add** any new `tags` (merge with existing, don't replace).
7. Do **not** remove or rewrite content that hasn't changed — minimize
   the diff.

### Phase 6 — Update all index.md files

After all concept documents are written/updated, update **three
levels** of index files:

#### 6a. Nested subdirectory index files (within session sub-bundle)

For each subdirectory inside the session sub-bundle that received new
or updated concepts, rewrite its `index.md` to list **all** concepts
in that directory:

```markdown
# <Section Title>

* [Concept Title](concept-file.md) - description from frontmatter
* [Another Concept](another.md) - its description
```

- **No YAML frontmatter** (OKF §6).
- Pull the description from each concept's `description` frontmatter.
- Include links to sub-subdirectories if any.
- **Preserve** any hand-written narrative already in the index —
  append the listing section if narrative exists.

#### 6b. Session sub-bundle index.md

Rewrite `~/.agents/knowledge/<session-name>/index.md` to list:
- All concepts at the session sub-bundle root
- All subdirectories within the session sub-bundle (with links)

#### 6c. Bundle root index.md

Update `~/.agents/knowledge/index.md` to include entries for **both**
the session sub-bundle and the patterns sub-bundle. **Do not discard**
existing entries for other session sub-bundles.

```markdown
# Knowledge

* [Agent Patterns](agent-patterns/index.md) - Higher-order patterns abstracted from accumulated agent memories
* [Session Topic Name](<session-name>/index.md) - one-line summary of what this session captured
* [Other Session](other-session/index.md) - existing entry preserved
```

The `agent-patterns/` entry should always appear **first** in the
listing (it's the meta-level knowledge). If it already exists, update
its description if the content has changed.

If the session sub-bundle entry already exists (from a prior run),
update its description if the content has changed.

### Phase 7 — Update log.md (both levels)

#### 7a. Session sub-bundle log.md

Record the details of what was generated/merged inside the session:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/knowledge/<session-name>/log.md \
  "* **Creation**: Generated N concept docs from session context.
* **Update**: Updated M existing concepts with new information.
* **Update**: Regenerated index.md for affected directories."
```

Replace `N` and `M` with actual counts. Add detail as appropriate:

- Which concepts were created (list filenames).
- Which concepts were updated (list filenames).
- Which nested subdirectories were created.

#### 7b. Bundle root log.md

Record a summary-level entry at the bundle root:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/knowledge/log.md \
  "* **Creation**: Added session sub-bundle \`<session-name>/\` with N concept(s).
* **Update**: Updated root index.md."
```

Or, if merging into an existing session sub-bundle:

```bash
bash ~/.agents/skills/okf-bundle-gen/scripts/merge-log-entry.sh \
  ~/.agents/knowledge/log.md \
  "* **Update**: Merged new knowledge into \`<session-name>/\` — N created, M updated.
* **Update**: Updated root index.md."
```

Both entries are automatically prepended under today's date heading in
reverse chronological order.

### Phase 8 — Verify conformance

Run the verification script against the **full bundle** (which
includes all session sub-bundles):

```bash
bash ~/.agents/skills/okf-bundle-setup/scripts/verify-bundle.sh ~/.agents/knowledge
```

All items should show `[✓]`. Fix any `[✗]` items:

| Common failure | Fix |
|----------------|-----|
| Missing `type` field | Add `type:` to frontmatter |
| Frontmatter on `index.md` | Remove the `---` block |
| Broken link | Fix the relative path or create the missing target |
| Non-kebab-case directory | Rename to lowercase kebab-case |

Re-run verification after fixes until the bundle is fully conformant.

---

## Merge Semantics — Detailed Rules

When the bundle already has content, the merge must be **additive and
non-destructive**. These rules govern how conflicts are resolved:

### Session sub-bundle scoping

- Merges are scoped to the **session sub-bundle** directory. A new
  invocation only modifies concepts inside its own
  `~/.agents/knowledge/<session-name>/` directory.
- Concepts in **other** session sub-bundles are never modified.
- **Exception: `agent-patterns/`** — pattern concepts derived from
  memories are always written to the dedicated
  `~/.agents/knowledge/agent-patterns/` sub-bundle, which accumulates
  patterns across all sessions. Pattern merges follow the same
  concept-level merge rules below.
- The **root** `index.md` and `log.md` are updated to reflect the
  new or changed session sub-bundle and patterns sub-bundle, but
  existing entries for other sessions are preserved.
- If the same session name is reused (e.g., the user continues a
  topic across multiple invocations), new knowledge is merged into
  the existing session sub-bundle.

### Concept-level merge (within a session sub-bundle)

| Scenario | Rule |
|----------|------|
| Same topic, same file | Append new sections; update `timestamp` and `tags` |
| Same topic, different file | Merge into the existing file; remove the duplicate if you created it |
| Overlapping topics | Cross-link the two concepts; don't merge if they have distinct angles |
| Contradictory information | Update the existing concept with corrected info; add a note about what changed |

### Index-level merge

- **Never discard** existing index entries at any level.
- **Append** new entries for new concepts or session sub-bundles.
- **Update** descriptions if a concept's `description` frontmatter changed.
- **Remove** entries only if the corresponding concept file was deleted
  (which this skill does not do — it only creates or updates).

### Log-level merge

- **Always prepend** new entries (reverse chronological) at both the
  session sub-bundle and root levels.
- **Never modify or delete** existing log entries.
- Each run of this skill produces **one log entry group** under today's
  date at each level. Multiple runs on the same day accumulate under
  the same `## YYYY-MM-DD` heading.

---

## Quality Checklist

Before completing, verify:

- [ ] **No concept docs at bundle root** — all concepts live inside
      the session sub-bundle or `agent-patterns/`.
- [ ] Session sub-bundle directory name is **lowercase kebab-case**,
      ≤25 characters, and descriptive of the session topic.
- [ ] Every generated concept `.md` has YAML frontmatter with `type`
      (required), `title`, `description` (recommended).
- [ ] Concept bodies are **self-contained** — readable without the
      conversation.
- [ ] Concept bodies use **structural markdown** (headings, lists,
      tables, code blocks).
- [ ] Cross-links between related concepts are present and resolve.
- [ ] `index.md` files at **all levels** (root, session sub-bundle,
      agent-patterns, nested subdirs) list their contents, with no
      YAML frontmatter.
- [ ] `log.md` updated at **both levels** — root (summary) and session
      sub-bundle (detailed), newest first.
- [ ] `verify-bundle.sh` passes with zero failures.
- [ ] No conversational artifacts in concept bodies ("the user said",
      "I replied", "as discussed above").
- [ ] All directory names are lowercase kebab-case, ≤25 characters.
- [ ] **Pattern concepts** in `agent-patterns/` have a "Derived From"
      table tracing back to source episodic entries.
- [ ] **Pattern concepts** are derived from ≥2 distinct episodic entries
      (not single-entry restating).


---

## Example Output

After extracting knowledge from a session about OKF and skill creation,
plus abstracting patterns from accumulated memories:

```
~/.agents/knowledge/
├── index.md                           ← root listing (links to all sub-bundles)
├── log.md                             ← root log (summary entries for this run)
├── agent-patterns/                    ← dedicated patterns sub-bundle
│   ├── index.md                       ← lists all pattern concepts
│   ├── log.md                         ← pattern generation log
│   ├── design-philosophy.md           ← type: Pattern
│   ├── reasoning-style.md             ← type: Pattern
│   └── domain-synthesis.md            ← type: Pattern
└── okf-skill-creation/                ← session sub-bundle
    ├── index.md                       ← session-level listing
    ├── log.md                         ← session-level log
    ├── specifications/
    │   ├── index.md
    │   ├── okf-overview.md            ← type: Specification
    │   └── bundle-structure.md        ← type: Specification
    └── conventions/
        ├── index.md
        └── file-placement.md          ← type: Convention
```

After a **second session**, the bundle grows with a new session
sub-bundle, and `agent-patterns/` may gain new patterns or have
existing ones updated:

```
~/.agents/knowledge/
├── index.md                           ← now lists all three sub-bundles
├── log.md                             ← has entries for both runs
├── agent-patterns/                    ← accumulates across sessions
│   ├── design-philosophy.md           ← may be updated with new evidence
│   └── ...
├── okf-skill-creation/                ← first session (untouched)
│   └── ...
└── k8s-deploy-debug/                  ← second session sub-bundle
    └── ...
```

## Pitfalls

1. **scaffold-bundle.sh auto-renames directories** — The scaffold
   script normalizes directory names to lowercase kebab-case. If you
   pass a session name with underscores (e.g., `my_session`), the
   directory will be silently renamed to `my-session`. Always use
   kebab-case session names from the start to avoid path mismatches
   in subsequent phases.

2. **Nested sub-bundle log.md files** — The scaffold script creates
   a `log.md` in every scaffolded directory (including nested
   subdirectories like `specifications/`). These sub-sub-bundle logs
   are usually left at their initialization state. Only the session
   sub-bundle level and root level logs need active maintenance.

3. **Pattern over-extraction** — Not every pair of related memory
   entries warrants a pattern concept. Require at least two distinct
   episodic entries as sources, and ensure the abstraction is at a
   genuinely higher level than either entry alone. "User likes Python
   AND user likes TypeScript" → bad (just a list). "User prefers
   typed languages with strong tooling ecosystems" → good (abstraction).

4. **Empty memories directory** — If `./.agents/memories/` doesn't
   exist yet (e.g., fresh PROJECT mode setup hasn't been run), Phase
   1c produces no entries. This is fine — skip Phase 1d and proceed
   with session-only knowledge extraction. Don't fail or warn loudly.

## Supporting Files

Skill directory: ~/.agents/skills/okf-bundle-gen

- scripts/list-existing-concepts.sh → load_skill(name: "okf-bundle-gen/scripts/list-existing-concepts.sh")
- scripts/merge-log-entry.sh → load_skill(name: "okf-bundle-gen/scripts/merge-log-entry.sh")
- scripts/scan-memories.sh → load_skill(name: "okf-bundle-gen/scripts/scan-memories.sh")
Dependencies (from `okf-bundle-setup`):
- scaffold-bundle.sh → load_skill(name: "okf-bundle-setup/scripts/scaffold-bundle.sh")
- verify-bundle.sh → load_skill(name: "okf-bundle-setup/scripts/verify-bundle.sh")
- OKF spec reference → load_skill(name: "okf-bundle-setup/references/okf-spec-summary.md")

## Changelog

| Updated | Change |
|---------|--------|
| 2026-07-09 01:38 | v3.1 — Removed Phase 9 (SOUL.md pattern link injection) and update-soul-links.sh dependency; knowledge discovery now handled via global .goosehints progressive loading instead of SOUL.md markers |
| 2026-07-08 14:19 | v3.0 — Memory redesign: bundle root changed from `./.agents/knowledge/` (project-local staging) to `~/.agents/knowledge/` (user-level); removed project-local staging concept; memory scan is PROJECT-only (no `~/.agents/memories/`); `okf-bundle-merge` is now obsolete |
| 2026-06-30 23:49 | v2.2 — `merge-log-entry.sh` updated: `YYYY-MM-DD HH:MM` timestamps, `<!-- Append-only -->` comment, `- ` entry style |
| 2026-06-30 23:36 | v2.1 — Changelog table uses `Updated` header and `YYYY-MM-DD HH:MM` timestamps, aligned with guardrail §3 |
| 2026-06-30 16:46 | v2.0 — Memory scanning + pattern extraction + multi-agent SOUL.md linking. New phases: 1c (scan-memories.sh), 1d (pattern extraction to agent-patterns/ sub-bundle), 9 (update-soul-links.sh across default + profile SOUL.md files). New scripts: scan-memories.sh, update-soul-links.sh. Relative link depth auto-adjusted per SOUL.md location. |
| 2026-06-25 22:52 | v1.0 — Initial skill: session-based knowledge extraction to OKF bundle with merge semantics, per-session sub-bundles, list-existing-concepts.sh, merge-log-entry.sh. |
