# Filesystem Integrity — Script Delegation

When editing files under `.agents/` or `~/.agents/`, use these scripts
instead of direct edits for managed files.

## Script Delegation Table

| What | Script | Usage |
|------|--------|-------|
| Post-write orchestrator | `post-write.sh` | `bash post-write.sh <file> "<desc>" [--version <ver>]` — single call replaces manual ①②③④ sequence (log, changelog, post-edit, link check) |
| `log.md` (any scope) | `merge-log-entry.sh` | `bash merge-log-entry.sh <path> "<msg>"` — direct `write`/`edit` to `log.md` only permitted when creating a new file (initial entry) |
| `skills/*/CHANGELOG.md` | `merge-changelog-entry.sh` | `bash merge-changelog-entry.sh <path> "<version>" "<description>"` |
| `metadata.version` | *(agent direct edit)* | Edit skill frontmatter YAML `version:` field |
| `skills/index.md` | `post-edit.sh` | Automatic — run after any `.agents/` edit to rebuild indexes |
| `knowledge/` indexes | `rebuild-index.sh` | Via `load_skill(name: "okf-bundle-index")` — audited by `post-edit.sh` |
| `profiles/index.md` | *(via skill)* | `load_skill(name: "agentfs-profile")` |
| Broken links | *(agent direct)* | Agent updates on create/rename/move/delete |

All scripts live in `~/.agents/skills/agentfs-setup/scripts/`.

## Log Entry Format

```
- <Imperative verb> <what changed> (<relative-path>)
```

| Rule | Why |
|---|---|
| Lead with an imperative verb (`Add`, `Fix`, `Update`, `Create`, `Remove`, `Document`, `Rewrite`) | Matches the established convention — 1074 of 1968 entries at the time of writing |
| Do NOT lead with the filename (`restore.sh: …`) | The path suffix already names the file; the prefix duplicates it |
| Do NOT invent tag prefixes (`doc:`, `fix:`) | Zero precedent in the log; the verb carries the same meaning |
| Always end with the relative path | `restore.sh` / `setup.sh` / `SKILL.md` recur across skills — without the path the entry is ambiguous |
| Do NOT start with a date | The `##` heading already carries the timestamp (`merge-log-entry.sh` strips it) |

`post-write.sh` appends the path automatically unless the description
already contains the full relative path.

## Scope Logging Rules

Log to **every scope** you touched in the same task:

| If you edited under… | Update this log |
|-----------------------|-----------------|
| `~/.agents/` (USER) | `~/.agents/log.md` |
| `./.agents/` (PROJECT) | `./.agents/log.md` |
| `~/.agents/knowledge/<bundle>/` | *also* that bundle's `log.md` |
| `~/.agents/knowledge/` (bundle ops) | *also* `~/.agents/knowledge/log.md` |

## Checkpoint Protocol

Before destructive operations (delete, bulk rename, multi-file edit
under `.agents/`):

```bash
bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh create <files>  # before
# ... execute operation ...
bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh clear           # after success
bash ~/.agents/skills/agentfs-setup/scripts/checkpoint.sh check           # on session start
```

Where the checkpoint lives (any cwd works):

| Command | Location |
|---|---|
| `create <files>` | `<root>/.checkpoint`, `<root>` = nearest `.agents` ancestor of each file's absolute path. Files outside any `.agents/` → `./.agents`, else `~/.agents`. Files in several roots → one checkpoint per root. Paths are recorded absolute. |
| `clear`, `check` | Every candidate root: `./.agents` and `~/.agents`. `--root DIR` limits it to one. |

Until the 2026-11-13 fix the root came from the cwd only, so a
`clear` from a project directory could miss a `~/.agents` checkpoint.

## Cross-Skill Script Execution

Scripts are owned by a parent skill but may be called by other skills
(e.g., `agentfs-git-push` calling `agentfs-setup`'s
`merge-log-entry.sh`). When executing a script owned by a different
skill, resolve input conventions in this priority order:

| Priority | Source | Action |
|:--------:|--------|--------|
| 1 | **Calling skill's prose** | If it specifies the format, use it |
| 2 | **Existing output patterns** | Check the target file/resource for established conventions |
| 3 | **Owning skill's prose** | Load the owning SKILL.md if needed |
| 4 | **Script comments** | Last resort — treat as implementation hints, not usage instructions |

**Rationale:** Script comments describe *how the code works
internally*, not *how it should be used*. Input/output format
conventions belong in the owning SKILL.md (Separation of Concerns).
When a calling skill doesn't specify format, the agent should check
ground truth (existing patterns) before falling back to the owning
skill's prose or script comments.

## General Rules

- Prefer incremental edits over full rewrites — full rewrites risk
  dropping sections.
- Use `./` prefix for dot-directory paths.
