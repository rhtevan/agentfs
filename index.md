# .agents — System Directory Index

> Progressive-disclosure entry point. Browse folders before opening files.
> Shared skills and knowledge visible across projects and agents.

| Layer      | Path                             | Purpose                                      |
| ---------- | -------------------------------- | -------------------------------------------- |
| Capability | [skills/](./skills/index.md)       | Shared agent workflows (Agent Skills format) |
| Knowledge  | [knowledge/](./knowledge/index.md) | Shared knowledge base (OKF format)           |

See [log.md](./log.md) for recent activity.

## AgentFS Structural Guardrails

These guardrails ensure the consistency and integrity of the AgentFS
directory structure. Every agent operating with system-level AgentFS
(`~/.agents/`) MUST follow them.

### 1. Link Integrity

- **No broken links.** Every markdown link in `index.md`, `SKILL.md`,
  concept docs, and other `.md` files under `.agents/` MUST resolve to
  an existing file or directory.
- **No obsolete links.** When a file is renamed, moved, or deleted,
  update ALL links that reference it — in `index.md` files, cross-links
  in concept docs, and any referencing `.md` file.
- **No missing links.** When a new file, skill, concept, or sub-bundle
  is created, add a link to the appropriate `index.md` immediately.

### 2. Log Currency (`log.md`)

- **Reverse chronological order** — newest entries FIRST, directly under
  the `# Directory Update Log` heading.
- **ISO 8601 date headings** — group entries under `## YYYY-MM-DD`.
  If today's heading exists, append under it; otherwise insert a new
  heading above all existing ones.
- **Log every material change** — file creation, renames, reorganization,
  deletions, and structural updates.
- **Never modify or delete** existing log entries.
- This applies to `log.md` at every level: `.agents/log.md`,
  `.agents/knowledge/log.md`, and any sub-bundle `log.md`.

### 3. Content File Currency (Changelog)

- **Every content file with a `Changelog` section** (e.g., `SKILL.md`,
  design specs, reference docs) MUST maintain it in **reverse
  chronological order** — newest entries first.
- When updating a content file, **append a changelog entry** at the TOP
  of the changelog table with today's date and a concise description.
- **Never remove** existing changelog entries.

### 4. Progressive Disclosure

- **Browse `index.md` first** before opening individual documents.
- Use `index.md` files as navigation hubs — they list and describe
  everything in their directory.
- Follow links from `index.md` → concept docs → referenced assets,
  rather than scanning directories directly.
