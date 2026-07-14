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
| Scope | Root Path | Resolves To | Purpose |\
|-------|-----------|-------------|----------|\
| **USER** | `~\/.agents\/` | `\/home\/<user>\/.agents\/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |\
| **PROJECT** | `.\/\.agents\/` | `<repo-root>\/.agents\/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |\
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
\
> **Rule of thumb:** If the agent says "USER scope", it means\
> `~\/.agents\/`. If it says "PROJECT scope", it means `.\/\.agents\/`\
> relative to the current repository root.\
' "$TARGET"
    fi
    echo "  ✓ Added Scope Definitions section to existing AGENTS.md"
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

## Scope Definitions

AgentFS operates in two scopes. These definitions are canonical —
all guardrails, skills, and documentation reference them.

| Scope | Root Path | Resolves To | Purpose |
|-------|-----------|-------------|----------|
| **USER** | `~/.agents/` | `/home/<user>/.agents/` | Machine-wide shared library: skills and knowledge visible across all projects and agents |
| **PROJECT** | `./.agents/` | `<repo-root>/.agents/` | Per-repository agent workspace: identity, profiles, memories, and project-scoped skills |

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

> **Rule of thumb:** If the agent says "USER scope", it means
> `~/.agents/`. If it says "PROJECT scope", it means `./.agents/`
> relative to the current repository root.

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
- **Entry relevancy.** Each entry in a \`log.md\` MUST only describe
  changes to files **within that log's scope**:
  - \`~/.agents/log.md\` (USER) — only changes to files under
    \`~/.agents/\` or user-level config (e.g., \`~/.config/\`)
  - \`./.agents/log.md\` (PROJECT) — only changes to files under
    \`./.agents/\` or project root (e.g., \`./AGENTS.md\`)
  - Sub-bundle \`log.md\` — only changes within that bundle

  When a single action affects **both** scopes (e.g., harvesting
  project memories into a USER skill), log the relevant portion
  in each scope's \`log.md\`:
  - USER log: "Created skill \`crc-ctl\` v1.0"
  - PROJECT log: "Graduated 3 MEMORY.md entries; MEMORY.md pruned"

  Do NOT cross-reference the other scope's files in a log entry.
  Noting the *source* or *reason* is acceptable (e.g., "from
  goofing-around project"), but the entry's primary subject must
  be a file within the log's own scope.
- **Consistent format:** All \`log.md\` files MUST use:
  - Title: \`# Directory Update Log\`
  - Comment: \`<!-- Append-only. Newest entries at top. -->\`
  - Headings: \`## YYYY-MM-DD HH:MM\`
  - Entries: \`- \` (dash prefix, plain text or inline code)

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
- **Every SKILL.md MUST have `metadata.tags`.** Tags enable the
  fallback routing in Guardrail #9's skill resolution chain. When
  creating or updating a skill, the YAML frontmatter MUST include a
  `metadata:` section with a `tags:` list (bracket notation, e.g.,
  `tags: [agentfs, memory, harvest]`). Choose tags that describe the
  skill's domain, function, and artifact type. A skill without tags
  is invisible to tag-based discovery.
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
|------|----------|
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

### 9. Memory Signal Routing

When a user expresses memory-related intent, the agent MUST consult
the decision table below to determine the correct action. This table
covers agent-agnostic routing only — agent-specific overrides (e.g.,
agent memory extensions) take priority when present and their tools are
available in the current session.

#### Signal → Route Decision Table

| Signal / Keyword | Intent | Route To | Executor | Scope |
|---|---|---|---|---|
| "remember this", "note that", "keep in mind", "save this for later" | Store project observation | `.agents/memories/MEMORY.md` | LLM direct (file edit) | PROJECT |
| "always do X", "never do Y", "enforce Z", "this is a rule" | Structural rule/guardrail | Propose as `AGENTS.md` guardrail | LLM direct (propose edit, human approval) | PROJECT |
| "I prefer", "I like", "my style is" | User preference | `.agents/memories/USER.md` | LLM direct (file edit) | PROJECT |
| "learn this document", "ingest this file", "add to knowledge base" | Knowledge ingestion | OKF bundle under `~/.agents/knowledge/` | `okf-bundle-gen` or `okf-bundle-harvest` skill | USER |
| "how do I", "what's the procedure for" | Procedural lookup | Matching skill from `~/.agents/skills/` | `load_skill` | USER |
| "forget this", "remove that note" | Delete observation | Edit `MEMORY.md`, remove entry | LLM direct (file edit) | PROJECT |
| "create a skill for this", "make this reusable" | Skill creation/update | `~/.agents/skills/<name>/SKILL.md` | `skill-gen` skill (simple mode default; advanced with evals on request) | USER (default) |
| "what do you remember about", "check your notes on" | Retrieve observations | Read `.agents/memories/MEMORY.md` | LLM direct (file read) | PROJECT |
| "harvest", "scan memories", "graduate patterns" | Extract reusable knowledge from MEMORY.md | Skills → `skill-harvest`; Knowledge → `okf-bundle-harvest` | Named skill (scan current project or explicit location) | USER |

#### Routing Rules

- **Agent-specific overrides take priority.** If the agent has its own
  decision table (e.g., in its persistent instructions), and the referenced
  tool exists in the current session's available tools, the
  agent-specific route wins.
- **Skill creation defaults to USER scope.** When creating or updating
  skills, default to `~/.agents/skills/` (USER) unless the user
  explicitly says "project skill", "for this project", or "local skill".
- **Harvest scans the current project by default.** When signaling
  "harvest" or similar, scan `MEMORY.md` files at the current project
  (`.agents/memories/` and `.agents/profiles/*/memories/`). If the
  user names a specific location, scan there instead. Route to
  `skill-harvest` for procedural patterns or `okf-bundle-harvest`
  for declarative/semantic knowledge, following existing graduation
  guidelines in Guardrail #8.
- **Skill resolution chain.** When a route in the decision table
  names a specific skill, resolve it using this chain:
  1. **Explicit name** — try \`load_skill\` with the named skill. If
     found, use it.
  2. **Tag fallback** — if the named skill is not found, search
     \`~/.agents/skills/index.md\` for skills whose Tags column
     matches the intent (e.g., tags containing \`harvest\` +
     \`memory\`). If exactly one match, use it.
  3. **Semantic fallback** — if multiple tag matches or no tag
     match, use skill descriptions to disambiguate.
  4. **Fail loud** — if no skill can be resolved, inform the user:
     *"Could not find a skill for \<intent\>. Expected:
     \<skill-name\>. Searched tags: [\<tags\>]. Suggest: install
     the skill or run agentfs-setup."*
  Do NOT silently improvise a workflow when the named skill is
  missing — follow the chain and fail explicitly at step 4.
- **Executor clarifies agency.** "LLM direct" means the agent performs
  the file operation itself. A named skill means the agent MUST
  `load_skill` first and follow its instructions. "LLM intrinsic
  capability or agent Skills extension" means use whatever skill
  creation mechanism the agent natively supports.

### 10. Idempotency

Every skill and automated workflow MUST be idempotent — running it
twice with the same inputs MUST produce the same filesystem state.
Skills MUST use existence checks (`[ -f ... ]`, `[ -d ... ]`),
upsert patterns (create-or-update), and avoid append-without-dedup.
When a skill modifies a file, it MUST check whether the modification
already exists before applying it.

### 11. Checkpoints & Resumability

Before any destructive or multi-step operation (file deletion, bulk
rename, multi-file edit), the agent MUST create a checkpoint by
recording the list of affected files and their content hashes in
`.agents/.checkpoint`. After successful completion, the checkpoint
is cleared. If a session starts and a non-empty `.checkpoint` exists,
the agent MUST report it and offer to resume or revert.

### 12. Anti-Sycophancy

When a user request conflicts with an existing guardrail in `AGENTS.md`,
the agent MUST NOT silently comply. Instead it MUST:
1. Quote the conflicting guardrail
2. Explain the conflict
3. Ask for explicit confirmation before proceeding
4. If confirmed, log the override in `log.md` with the tag `[OVERRIDE]`

The agent MUST NOT add content to `MEMORY.md` that reads as a rule or
guardrail (contains "always", "never", "must", "enforce") — such
content belongs in `AGENTS.md` and requires human approval.

### 13. Git Push Safety

Before executing any `git push`, the agent MUST follow these steps
**in order**. No step may be skipped, even if the user says "go ahead",
"push it", or "yes". The user's approval authorizes the *intent* to
push, not the push itself. The preflight MUST complete and be
explicitly approved before pushing.

#### Step 1: STOP

Do NOT execute `git push`. Proceed to Step 2.

#### Step 2: Scan

Run `git diff` (for staged changes) or `git diff HEAD~N HEAD` (for
already-committed changes) and scan the output for:

- Secrets, credentials, API keys, tokens, private keys
- Hardcoded user paths (`/home/<user>/`, `/Users/<user>/`)
- PII (personal emails, phone numbers, addresses)
- Sensitive data (internal IPs, hostnames, URLs containing
  authentication parameters)

#### Step 3: Present the Report

Show the user a **Pre-Push Security Report** in this exact format:

```
### Pre-Push Security Report

| Check                | Result                       |
|----------------------|------------------------------|
| Secrets / API keys   | ✅ Clean — or ⚠️ FOUND: ... |
| Hardcoded user paths | ✅ Clean — or ⚠️ FOUND: ... |
| PII                  | ✅ Clean — or ⚠️ FOUND: ... |
| Sensitive URLs/IPs   | ✅ Clean — or ⚠️ FOUND: ... |

**Verdict: ✅ CLEAN** (or **⚠️ ISSUES FOUND**)

Proceed with push? (yes/no)
```

#### Step 4: WAIT

Do NOT proceed until the user explicitly responds to the report.
No assumptions. No auto-proceeding. No combining Step 3 and Step 5
into a single action. Full stop here.

#### Step 5: Push

Only after receiving explicit approval in response to the report,
execute `git push`.

#### Override Logging

If the user acknowledges issues from the report but still requests
the push proceed, log the override in `log.md` with the tag
`[OVERRIDE]` per Guardrail #12 (Anti-Sycophancy).

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
