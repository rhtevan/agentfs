#!/usr/bin/env bash
# seed-agents-md.sh — Create or update the root AGENTS.md workspace file.
#
# Usage: bash seed-agents-md.sh [PROJECT_ROOT]
#   PROJECT_ROOT defaults to the current working directory.
#
# This script is for PROJECT mode only. USER mode does not create AGENTS.md.
#
# If AGENTS.md already exists it is left untouched to preserve user edits.
# The script ensures SPECKIT markers are present so Spec-kit's agent-context
# extension can manage the active-plan reference automatically.

set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
TARGET="$ROOT/AGENTS.md"

if [[ -f "$TARGET" ]]; then
  echo "[agentfs-setup] AGENTS.md already exists — skipping."
  # Ensure SPECKIT markers exist even in a pre-existing file
  if ! grep -q '<!-- SPECKIT START -->' "$TARGET"; then
    printf '\n<!-- SPECKIT START -->\n<!-- SPECKIT END -->\n' >> "$TARGET"
    echo "  ✓ Appended SPECKIT markers to existing AGENTS.md"
  fi
  # Ensure Agent Profiles table exists even in a pre-existing file
  if ! grep -q '## Agent Profiles' "$TARGET"; then
    # Insert before SPECKIT markers if they exist, otherwise append
    if grep -q '<!-- SPECKIT START -->' "$TARGET"; then
      sed -i '/<!-- SPECKIT START -->/i ## Agent Profiles\n\n| Agent | Identity | Memories |\n|-------|----------|----------|\n| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |\n' "$TARGET"
    else
      printf '\n## Agent Profiles\n\n| Agent | Identity | Memories |\n|-------|----------|----------|\n| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |\n' >> "$TARGET"
    fi
    echo "  ✓ Added Agent Profiles table to existing AGENTS.md"
  fi
  exit 0
fi

cat > "$TARGET" << 'AGENTSEOF'
# AGENTS.md — Workspace Entry Point

> This file is the universal entry point for any AI agent operating in this
> project. It provides structural guardrails for maintaining the AgentFS
> directory (`.agents/`) and points toward deeper context layers.

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Reverse-chronological change history |

## AgentFS Structural Guardrails

These guardrails ensure the consistency and integrity of the AgentFS
directory structure — both at the project level (`./.agents/`) and the
user level (`~/.agents/`). Every agent operating in this project
MUST follow them.

### 1. Link Integrity

- **No broken links.** Every markdown link in `index.md`, `SKILL.md`,
  concept docs, and other `.md` files under `.agents/` MUST resolve to
  an existing file or directory.
- **No obsolete links.** When a file is renamed, moved, or deleted,
  update ALL links that reference it — in `index.md` files, cross-links
  in concept docs, and this file (`AGENTS.md`).
- **No missing links.** When a new file, skill, concept, or sub-bundle
  is created, add a link to the appropriate `index.md` immediately.
- **Use `./` prefix** for dot-directory paths (e.g., `./.agents/...`,
  `./.specify/...`) to ensure correct rendering across markdown viewers.

### 2. Log Currency (`log.md`)

- **Reverse chronological order** — newest entries FIRST, directly under
  the `# Directory Update Log` heading.
- **ISO 8601 timestamp headings** — group entries under
  `## YYYY-MM-DD HH:MM`. If a heading for the current timestamp exists,
  append under it; otherwise insert a new heading above all existing ones.
- **Log every material change** — file creation, renames, reorganization,
  deletions, and structural updates. This includes changes to skills
  (SKILL.md creation, modification, or deletion) and knowledge concept
  files.
- **Never modify or delete** existing log entries.
- **Scope:** This applies to `log.md` at EVERY level and in BOTH scopes:
  - **USER** `~/.agents/log.md` — when USER-scope skills or knowledge
    change (e.g., creating, editing, or merging skills under
    `~/.agents/skills/`)
  - **PROJECT** `./.agents/log.md` — when PROJECT-scope files change
  - **Sub-bundles** `.agents/knowledge/<bundle>/log.md` — when concept
    files within a knowledge bundle change
- **Consistent format:** All `log.md` files MUST use:
  - Title: `# Directory Update Log`
  - Comment: `<!-- Append-only. Newest entries at top. -->`
  - Headings: `## YYYY-MM-DD HH:MM`
  - Entries: `- ` (dash prefix, plain text or inline code)

### 3. Content File Currency (Changelog)

- **Every content file with a `Changelog` section** (e.g., `SKILL.md`,
  design specs, reference docs) MUST maintain it in **reverse
  chronological order** — newest entries first.
- When updating a content file, **append a changelog entry** at the TOP
  of the changelog table with the current ISO 8601 timestamp
  (`YYYY-MM-DD HH:MM`) and a concise description.
- **Never remove** existing changelog entries.

### 4. Progressive Disclosure

- **Browse `index.md` first** before opening individual documents.
- Use `index.md` files as navigation hubs — they list and describe
  everything in their directory.
- Follow links from `index.md` → concept docs → referenced assets,
  rather than scanning directories directly.

### 5. Skill Placement

- **Default to USER.** When the user asks to create a skill without
  specifying a location or scope, place it under the USER skills
  folder: `~/.agents/skills/<skill-name>/`.
- **Project only when explicit.** Only place a skill under the PROJECT
  skills folder (`./.agents/skills/<skill-name>/`) when the user
  specifically says "project skill", "for this project", "local skill",
  or similar project-scoping language.
- Skills in `~/.agents/skills/` are shared across all projects and
  agents. Skills in `./.agents/skills/` are scoped to this project only.

### 6. Index Currency (`skills/index.md` and `profiles/index.md`)

- **`skills/index.md` MUST stay current.** Whenever a skill is created,
  renamed, moved, deleted, or its content is modified (e.g., SKILL.md
  description, scripts, references) — in EITHER scope (USER
  `~/.agents/skills/` or PROJECT `./.agents/skills/`) — the
  corresponding `skills/index.md` MUST be regenerated immediately.
- **`profiles/index.md` MUST stay current.** Whenever a profile is
  created or removed under `.agents/profiles/`, update
  `.agents/profiles/index.md` immediately.
- **Entries MUST include a timestamp** in ISO 8601 format
  (`YYYY-MM-DD HH:MM`) recording when the entry was created or last
  modified.
- **Entries MUST be sorted in reverse chronological order** — newest
  first — by their timestamp field.
- **Automation:** Scripts that create skills or profiles (e.g.,
  `create-profile.sh`, `skill-index` skill, `skill-merge` skill) MUST
  update the relevant `index.md` as part of their execution. The
  `skill-index` skill can be invoked to regenerate `skills/index.md`
  from scratch at any time.
- **Use `skill-index`, not manual edits.** When a SKILL.md is created,
  modified, or deleted, the agent MUST invoke the `skill-index` skill
  to regenerate the full `skills/index.md` — do NOT manually edit
  individual rows or timestamps. This applies to BOTH USER
  (`~/.agents/skills/`) and PROJECT (`./.agents/skills/`) scopes,
  regardless of the agent's current working directory.
- **Update `log.md` at the correct scope.** When USER-scope files
  change (e.g., skills under `~/.agents/skills/`), update
  `~/.agents/log.md`. When PROJECT-scope files change, update
  `./.agents/log.md`. Both logs MUST be updated when a change
  affects both scopes (e.g., `skill-merge`).

### 7. Cross-Agent Context Discovery

When starting a session in this project, check for and read these files
if they exist — treat their content as supplementary project guidelines:

| File | Purpose |
|------|---------|
| `CLAUDE.md` or `.claude/CLAUDE.md` | Claude Code project instructions |
| `.cursorrules` or `.cursor/rules/` | Cursor coding rules |
| `.windsurfrules` | Windsurf workspace rules |
| `.github/copilot-instructions.md` | GitHub Copilot project instructions |

If a conflict arises between these files and this `AGENTS.md`, the
guidelines in `AGENTS.md` take precedence.

### 8. Memory Scope

- **`memories/` is PROJECT-scoped only.** Memory files (`MEMORY.md`,
  `USER.md`) live under `./.agents/memories/` (default agent) or
  `./.agents/profiles/<name>/memories/` (named profiles). There is
  NO `memories/` directory at USER scope (`~/.agents/`).
- **`MEMORY.md` records experiences, not rules.** Content belongs in
  `MEMORY.md` only if it is a concrete, project-specific observation
  or experience (e.g., "CI breaks when X", "module Y depends on Z").
  Structural rules and guardrails belong in `AGENTS.md`; user
  preferences belong in `USER.md`.
- **Natural-language routing.** When the user says:
  - *"Remember this / note that / keep in mind"* → record in `MEMORY.md`
  - *"Always do X / never do Y / enforce Z"* → propose as an
    `AGENTS.md` guardrail (do NOT silently add to `MEMORY.md`)
  - *"I prefer / I like / my style is"* → record in `USER.md`
- **Graduation path.** When an observation in `MEMORY.md` matures into
  cross-project knowledge worth preserving, graduate it to an OKF
  knowledge bundle under `~/.agents/knowledge/` and remove the
  original entry.

## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |

<!-- SPECKIT START -->
<!-- SPECKIT END -->
AGENTSEOF

echo "[agentfs-setup] Created $TARGET"

# Append to .agents/log.md
LOG_FILE="$ROOT/.agents/log.md"
if [[ -f "$LOG_FILE" ]]; then
  TODAY=$(date '+%Y-%m-%d %H:%M')
  ENTRY="- Created AGENTS.md at project root."
  if grep -q "^## $TODAY" "$LOG_FILE"; then
    sed -i "/^## $TODAY$/a\\$ENTRY" "$LOG_FILE"
  else
    sed -i "3a\\\\n## $TODAY\\n\\n$ENTRY" "$LOG_FILE"
  fi
fi
