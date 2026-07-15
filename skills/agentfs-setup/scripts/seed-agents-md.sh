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
  # Ensure Scope Definitions section exists even in a pre-existing file
  if ! grep -q '## Scope Definitions' "$TARGET"; then
    # Insert after Quick Orientation if it exists, otherwise after the first heading
    if grep -q '## Quick Orientation' "$TARGET"; then
      sed -i '/## AgentFS Structural Guardrails/i \
## Scope Definitions\
\
AgentFS operates in two scopes. These definitions are canonical —\
all guardrails, skills, and documentation reference them.\
\
| Scope | Root Path | Purpose |\
|-------|-----------|----------|\
| **USER** | `~\/.agents\/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |\
| **PROJECT** | `.\/\.agents\/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |\
\
### What Lives Where\
\
| Resource | USER (`~\/.agents\/`) | PROJECT (`.\/\.agents\/`) |\
|----------|:-------------------:|:----------------------:|\
| `skills\/` | ✅ shared | ✅ project-specific |\
| `knowledge\/` | ✅ shared | ❌ never |\
| `memories\/` | ❌ never | ✅ per-agent |\
| `profiles\/` | ❌ never | ✅ multi-agent |\
| `SOUL.md` | ❌ never | ✅ agent identity |\
| `AGENTS.md` | ❌ never | ✅ (at repo root `.\/`) |\
| `index.md` | ✅ | ✅ |\
| `log.md` | ✅ | ✅ |\
' "$TARGET"
    fi
    echo "  ✓ Added Scope Definitions section to existing AGENTS.md"
  fi
  exit 0
fi

cat > "$TARGET" << 'AGENTSEOF'
# AGENTS.md — Workspace Entry Point

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, communication defaults |
| Knowledge index | [~/.agents/knowledge/index.md](~/.agents/knowledge/index.md) | Cross-project knowledge bundles (USER scope) |
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Reverse-chronological change history |

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical —
all guardrails, skills, and documentation reference them.

| Scope | Root Path | Purpose |
|-------|-----------|----------|
| **USER** | `~/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

### What Lives Where

| Resource | USER (`~/.agents/`) | PROJECT (`./.agents/`) |
|----------|:-------------------:|:----------------------:|
| `skills/` | ✅ shared | ✅ project-specific |
| `knowledge/` | ✅ shared | ❌ never |
| `memories/` | ❌ never | ✅ per-agent |
| `profiles/` | ❌ never | ✅ multi-agent |
| `SOUL.md` | ❌ never | ✅ agent identity |
| `AGENTS.md` | ❌ never | ✅ (at repo root `./`) |
| `index.md` | ✅ | ✅ |
| `log.md` | ✅ | ✅ |

## AgentFS Structural Guardrails

These guardrails ensure the consistency and integrity of the AgentFS
directory structure — both at the project level (`./.agents/`) and the
user level (`~/.agents/`). Every agent operating in this project
MUST follow them.

### 1. Progressive Disclosure

- **Browse `index.md` first** before opening individual documents.
- Use `index.md` files as navigation hubs — they list and describe
  everything in their directory.
- Follow links from `index.md` → concept docs → referenced assets,
  rather than scanning directories directly.

### 2. Memory Scope & Signal Routing

#### Scope Rules

- **`memories/` is PROJECT-scoped only.** Memory files (`MEMORY.md`,
  `USER.md`) live under `./.agents/memories/` (default agent) or
  `./.agents/profiles/<name>/memories/` (named profiles). There is
  NO `memories/` directory at USER scope (`~/.agents/`).
- **`MEMORY.md` records experiences, not rules.** Content belongs in
  `MEMORY.md` only if it is a concrete, project-specific observation
  or experience (e.g., "CI breaks when X", "module Y depends on Z").
  Structural rules and guardrails belong in `AGENTS.md`; user
  preferences belong in `USER.md`.
- **Graduation path.** When an observation in `MEMORY.md` matures into
  cross-project knowledge worth preserving, graduate it to an OKF
  knowledge bundle under `~/.agents/knowledge/` and remove the
  original entry.

#### Signal → Route Decision Table

When a user expresses memory-related intent, the agent MUST consult
this table. Agent-specific overrides (e.g., agent memory extensions)
take priority when present and their tools are available.

| Signal / Keyword | Intent | Route To |
|---|---|---|
| "remember this", "note that", "keep in mind", "save this for later" | Store project observation | `.agents/memories/MEMORY.md` |
| "always do X", "never do Y", "enforce Z", "this is a rule" | Structural rule/guardrail | Propose as `AGENTS.md` guardrail (human approval) |
| "I prefer", "I like", "my style is" | User preference | `.agents/memories/USER.md` |
| "learn this document", "ingest this file", "add to knowledge base" | Knowledge ingestion | OKF bundle under `~/.agents/knowledge/` via `okf-bundle-gen` or `okf-bundle-harvest` |
| "how do I", "what's the procedure for" | Procedural lookup | Matching skill via `load_skill` |
| "forget this", "remove that note" | Delete observation | Edit `MEMORY.md`, remove entry |
| "create a skill for this", "make this reusable" | Skill creation/update | `~/.agents/skills/<name>/SKILL.md` via `skill-gen` (default USER — see Guardrail #4) |
| "what do you remember about", "check your notes on" | Retrieve observations | Read `.agents/memories/MEMORY.md` |
| "harvest", "scan memories", "graduate patterns" | Extract reusable knowledge | `skill-harvest` (procedural) or `okf-bundle-harvest` (semantic) |

#### Routing Rules

- **Agent-specific overrides take priority.** If the agent has its own
  decision table (e.g., in persistent instructions), and the referenced
  tool exists in the current session's available tools, the
  agent-specific route wins.
- **Harvest scans the current project by default.** Scan `MEMORY.md`
  files at `.agents/memories/` and `.agents/profiles/*/memories/`.
  Route to `skill-harvest` for procedural patterns or
  `okf-bundle-harvest` for declarative/semantic knowledge.
- **Skill resolution chain.** When the decision table names a skill:
  try `load_skill` by name → tag fallback via `~/.agents/skills/index.md`
  → semantic fallback via descriptions → **fail loud** (do NOT
  silently improvise when the named skill is missing).

### 3. Cross-Agent Context Discovery

When starting a session in this project, check for and read these files
if they exist — treat their content as supplementary project guidelines:

| File | Purpose |
|------|----------|
| `CLAUDE.md` or `.claude/CLAUDE.md` | Claude Code project instructions |
| `.cursorrules` or `.cursor/rules/` | Cursor coding rules |
| `.windsurfrules` | Windsurf workspace rules |
| `.github/copilot-instructions.md` | GitHub Copilot project instructions |

If a conflict arises between these files and this `AGENTS.md`, the
guidelines in `AGENTS.md` take precedence.

### 4. Skill Placement

- **Default to USER.** When the user asks to create a skill without
  specifying a location or scope, place it under `~/.agents/skills/<skill-name>/`.
- **Project only when explicit.** Only place a skill under
  `./.agents/skills/<skill-name>/` when the user specifically says
  "project skill", "for this project", "local skill", or similar.

### 5. Filesystem Integrity

These rules apply to all `.md` files under `.agents/` in BOTH scopes.

#### Link Integrity

- **No broken links.** Every markdown link in `index.md`, `SKILL.md`,
  concept docs, and other `.md` files under `.agents/` MUST resolve to
  an existing file or directory.
- **No obsolete links.** When a file is renamed, moved, or deleted,
  update ALL links that reference it.
- **No missing links.** When a new file or directory is created, add
  a link to the appropriate `index.md` immediately.
- **Use `./` prefix** for dot-directory paths (e.g., `./.agents/...`).

#### Log & Changelog Currency

- **Reverse chronological order** — newest entries FIRST (applies to
  both `log.md` and any `Changelog` section in content files).
- **ISO 8601 timestamp headings** — `## YYYY-MM-DD HH:MM`.
- **Log every material change** — file creation, renames, deletions,
  structural updates.
- **Never modify or delete** existing log or changelog entries.
- **Scope:** Each `log.md` MUST only describe changes within its scope
  (`~/.agents/log.md` for USER, `./.agents/log.md` for PROJECT).
  When a single action affects both scopes, log in each.
- **Format:** Title `# Directory Update Log`,
  comment `<!-- Append-only. Newest entries at top. -->`,
  headings `## YYYY-MM-DD HH:MM`, entries `- ` (dash prefix).

#### Index Currency

- **`skills/index.md` and `profiles/index.md` MUST stay current.**
  When a skill or profile is created, renamed, modified, or deleted
  in either scope, regenerate the corresponding `index.md`.
- **Use the `skill-index` skill** to regenerate — do NOT manually edit.
- **Every SKILL.md MUST have `metadata.tags`** in YAML frontmatter
  (e.g., `tags: [agentfs, memory, harvest]`). A skill without tags
  is invisible to tag-based discovery.
- Entries MUST include ISO 8601 timestamps and be sorted newest-first.

#### Post-Edit Completeness

- **Prefer incremental edits over full rewrites** of files under
  \`.agents/\` — full rewrites risk dropping sections (e.g., rendered
  Changelog tables, verification checklists).
- **After modifying any file under \`.agents/\`** (either scope), verify:
  1. All existing sections in the file are preserved (especially
     rendered Changelog sections — never drop during rewrites).
  2. Corresponding \`index.md\` is regenerated if applicable.
  3. Changes are logged in the appropriate \`log.md\` (both scopes
     if both are affected by a single action).

### 6. Idempotency

Every skill and automated workflow MUST be idempotent — running it
twice with the same inputs MUST produce the same filesystem state.
Skills MUST use existence checks, upsert patterns, and avoid
append-without-dedup.

### 7. Anti-Sycophancy

When a user request conflicts with an existing guardrail in `AGENTS.md`,
the agent MUST NOT silently comply. Instead it MUST:
1. Quote the conflicting guardrail
2. Explain the conflict
3. Ask for explicit confirmation before proceeding
4. If confirmed, log the override in `log.md` with the tag `[OVERRIDE]`

The agent MUST NOT add content to `MEMORY.md` that reads as a rule or
guardrail (contains "always", "never", "must", "enforce") — such
content belongs in `AGENTS.md` and requires human approval.

### 8. Checkpoints & Resumability

Before any destructive or multi-step operation (file deletion, bulk
rename, multi-file edit), the agent MUST create a checkpoint by
recording affected files and their content hashes in
`.agents/.checkpoint`. After successful completion, clear the
checkpoint. If a session starts with a non-empty `.checkpoint`,
report it and offer to resume or revert.

### 9. Git Push Safety

Before executing any `git push`, the agent MUST follow these steps
**in order**. No step may be skipped, even if the user says "go ahead".

1. **STOP** — do NOT execute `git push` yet.
2. **Scan** — run `git diff` and scan for: secrets/API keys, hardcoded
   user paths (`/home/<user>/`), PII, sensitive URLs/IPs.
3. **Report** — present a Pre-Push Security Report table showing each
   check category with ✅ Clean or ⚠️ FOUND status, plus a verdict.
4. **WAIT** — do NOT proceed until the user explicitly responds.
5. **Push** — only after explicit approval, execute `git push`.

If the user acknowledges issues but still requests the push, log the
override in `log.md` with `[OVERRIDE]` per Guardrail #7.

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
