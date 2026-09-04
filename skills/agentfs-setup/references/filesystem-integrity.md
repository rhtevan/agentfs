# Filesystem Integrity — Script Delegation

When editing files under `.agents/` or `~/.agents/`, use these scripts
instead of direct edits for managed files.

## Script Delegation Table

| What | Script | Usage |
|------|--------|-------|
| `log.md` (any scope) | `merge-log-entry.sh` | `bash merge-log-entry.sh <path> "<msg>"` — direct `write`/`edit` to `log.md` only permitted when creating a new file (initial entry) |
| `skills/*/CHANGELOG.md` | `merge-changelog-entry.sh` | `bash merge-changelog-entry.sh <path> "<version>" "<description>"` |
| `metadata.version` | *(agent direct edit)* | Edit skill frontmatter YAML `version:` field |
| `skills/index.md` | `post-edit.sh` | Automatic — run after any `.agents/` edit to rebuild indexes |
| `knowledge/` indexes | `rebuild-index.sh` | Via `load_skill(name: "okf-bundle-index")` — audited by `post-edit.sh` |
| `profiles/index.md` | *(via skill)* | `load_skill(name: "agentfs-profile")` |
| Broken links | *(agent direct)* | Agent updates on create/rename/move/delete |

All scripts live in `~/.agents/skills/agentfs-setup/scripts/`.

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
