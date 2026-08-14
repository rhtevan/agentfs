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
<!-- agentfs-template-version: 3.10 -->
# AGENTS.md — Workspace Entry Point

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, communication defaults |
| Skills index | \`~/.agents/skills/index.md\` | Signal-based skill routing lookup (read on session start) |
| Knowledge index | \`~/.agents/knowledge/index.md\` | Cross-project knowledge bundles (USER scope) |
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Reverse-chronological change history |

## Signal Routing

When a user expresses a recognized intent signal, the agent MUST
consult this table before acting. Agent-specific overrides (e.g.,
agent memory extensions) take priority when present and their tools
are available.

| Signal / Keyword | Intent | Route To |
|---|---|---|
| "remember this", "note that", "keep in mind", "save this for later" | Store project observation | \`.agents/memories/MEMORY.md\` |
| "always do X", "never do Y", "enforce Z", "this is a rule" | Structural rule/guardrail | Propose as \`AGENTS.md\` guardrail (human approval) |
| "I prefer", "I like", "my style is" | User preference | \`.agents/memories/USER.md\` |
| "learn this document", "ingest this file", "add to knowledge base" | Knowledge ingestion | OKF bundle under \`~/.agents/knowledge/\` via \`okf-bundle-gen\` or \`okf-bundle-harvest\` |
| "forget this", "remove that note" | Delete observation | Edit \`MEMORY.md\`, remove entry |
| "what do you remember about", "check your notes on" | Retrieve observations | Read \`.agents/memories/MEMORY.md\` |
| "harvest", "reflect", "scan memories", "graduate patterns" | Extract reusable knowledge | \`skill-harvest\` (procedural) or \`okf-bundle-harvest\` (semantic) |
| "hey git", "git" | Commit & push USER AgentFS | \`cd ~/.agents\` (or explicit path if specified), stage all, commit, then trigger Guardrail #10 (Git Push Safety) |

For skill-routed signals (e.g., "setup agentfs", "create a skill"),
the agent discovers skills via the built-in skills listing (which
contains each skill's signal phrases in the \`description\` field)
and \`~/.agents/skills/index.md\` as defense-in-depth. Only LLM-direct
routes and genuinely ambiguous multi-skill triage entries belong in
this table.

### Routing Rules

- **Agent-specific overrides take priority.** If the agent has its own
  decision table (e.g., in persistent instructions), and the referenced
  tool exists in the current session's available tools, the
  agent-specific route wins.
- **Skill signal resolution.** Signal phrases in each skill's
  \`description\` field are always in context via the built-in skills
  listing. On session start, also read \`~/.agents/skills/index.md\`
  as defense-in-depth. When user intent doesn't match an LLM-direct
  route in the table above, match against the Description column in
  the skills index before falling back to skill name matching.
- **Harvest scans the current project by default.** Scan \`MEMORY.md\`
  files at \`.agents/memories/\` and \`.agents/profiles/*/memories/\`.
  Route to \`skill-harvest\` for procedural patterns or
  \`okf-bundle-harvest\` for declarative/semantic knowledge.
- **Skill resolution chain.** When the decision table names a skill:
  try \`load_skill\` by name → tag fallback via \`~/.agents/skills/index.md\`
  → semantic fallback via descriptions → **fail loud** (do NOT
  silently improvise when the named skill is missing).
- **Never improvise when a skill exists.** When user intent matches
  a skill signal, the agent MUST \`load_skill\` and follow its
  instructions — even if the agent believes it already knows the
  procedure. Stale context, schema changes, and memory
  hallucination make "I already know this" unreliable.

## Guardrail Quick Reference

| # | Type | Rule | Key Action |
|---|:----:|------|------------|
| [1](#1-progressive-disclosure-) | 🔄 | Progressive Disclosure | On \`.agents/\` access: browse \`index.md\` first, follow links to content |
| [2](#2-memory-scope-️) | ⚖️ | Memory Scope | Default \`memories/MEMORY.md\` for experiences; \`AGENTS.md\` for rules; \`USER.md\` for preferences |
| [3](#3-cross-agent-context-discovery-) | 🔄 | Cross-Agent Discovery | Session start: check \`CLAUDE.md\`, \`.cursorrules\`, etc.; \`AGENTS.md\` wins conflicts |
| [4](#4-skill-placement-️) | ⚖️ | Skill Placement | Default USER \`~/.agents/skills/\`; PROJECT only when user explicitly signals |
| [5](#5-filesystem-integrity-) | 🚧 | Filesystem Integrity | **STOP** after \`.agents/\` edit → preserve sections → regen index (delegated) → update log → **RESUME** |
| [6](#6-idempotency-) | 🔄 | Idempotency | Ongoing: existence checks, upsert patterns, no append-without-dedup |
| [7](#7-anti-sycophancy-️) | ⚖️ | Anti-Sycophancy | Default: quote conflict + ask; override only with explicit user confirmation + log \`[OVERRIDE]\` |
| [8](#8-anti-daydreaming-) | 🔄 | Anti-Daydreaming | Periodic (~1-in-5): emit canary name + self-check for context drift |
| [9](#9-checkpoints--resumability-) | 🚧 | Checkpoints | **STOP** before destructive op → record affected files → execute → clear checkpoint |
| [10](#10-git-push-safety-) | 🚧 | Git Push Safety | **STOP** → Scan → Report → **WAIT** for approval → Push |

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

### 1. Progressive Disclosure 🔄

- **Browse `index.md` first** before opening individual documents.
- Use `index.md` files as navigation hubs — they list and describe
  everything in their directory.
- Follow links from `index.md` → concept docs → referenced assets,
  rather than scanning directories directly.

### 2. Memory Scope ⚖️

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

### 3. Cross-Agent Context Discovery 🔄

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

### 4. Skill Placement ⚖️

- **Default to USER.** When the user asks to create a skill without
  specifying a location or scope, place it under `~/.agents/skills/<skill-name>/`.
- **Project only when explicit.** Only place a skill under
  `./.agents/skills/<skill-name>/` when the user specifically says
  "project skill", "for this project", "local skill", or similar.

### 5. Filesystem Integrity 🚧

> **STOP** after any `.agents/` edit — consult the delegation table
> before responding.

#### Editing Rules

- **Prefer incremental edits over full rewrites** — full rewrites
  risk dropping sections.
- **Link integrity.** Every markdown link under `.agents/` MUST
  resolve. When files are created, renamed, moved, or deleted,
  update all affected links and `index.md` entries immediately.
  Use `./` prefix for dot-directory paths.

#### Log & Index Delegation

| File | Level | Owner | How to update |
|------|-------|-------|---------------|
| `~/.agents/log.md` | Root (USER) | Agent direct | `edit` with comment-line anchor |
| `./.agents/log.md` | Root (PROJECT) | Agent direct | `edit` with comment-line anchor |
| `skills/index.md` | Skills | `skill-index` | `load_skill(name: "skill-index")` |
| `skills/*/CHANGELOG.md` | Skill | `skill-gen` | Agent direct (table format per `skill-schema.md`) |
| `knowledge/index.md` | Knowledge root | `okf-bundle-index` | `load_skill(name: "okf-bundle-index")` |
| `knowledge/log.md` | Knowledge root | `okf-bundle-gen` | `merge-log-entry.sh` |
| `knowledge/*/index.md` | Knowledge bundle | `okf-bundle-index` | `load_skill(name: "okf-bundle-index")` |
| `knowledge/*/log.md` | Knowledge bundle | `okf-bundle-gen` | `merge-log-entry.sh` |
| `profiles/index.md` | Profiles | `agentfs-profile` | `load_skill(name: "agentfs-profile")` |

Every `SKILL.md` MUST have `metadata.tags` in YAML frontmatter
(e.g., `tags: [agentfs, memory, harvest]`). A skill without tags
is invisible to tag-based discovery.

#### Root Log Format (agent-direct edits only)

- **Reverse chronological** — newest FIRST.
- **ISO 8601 headings** — `## YYYY-MM-DD HH:MM`
  (use `date '+%Y-%m-%d %H:%M'`).
- **Bullet prefix** — `- ` (dash).
- **Scope** — each `log.md` describes only its own scope. When a
  single action affects both, log in each.
- **Never modify or delete** existing entries.
- **Insertion anchor.** The `before` anchor MUST be the comment line
  (`<!-- Append-only. Newest entries at top. -->`), NEVER a `##`
  heading — headings shift across sessions and after compaction.
  Always `head -6 <log_file>` before editing to confirm current state.

### 6. Idempotency 🔄

Every skill and automated workflow MUST be idempotent — running it
twice with the same inputs MUST produce the same filesystem state.
Skills MUST use existence checks, upsert patterns, and avoid
append-without-dedup.

### 7. Anti-Sycophancy ⚖️

When a user request conflicts with an existing guardrail in `AGENTS.md`,
the agent MUST NOT silently comply. Instead it MUST:
1. Quote the conflicting guardrail
2. Explain the conflict
3. Ask for explicit confirmation before proceeding
4. If confirmed, log the override in `log.md` with the tag `[OVERRIDE]`

The agent MUST NOT add content to `MEMORY.md` that reads as a rule or
guardrail (contains "always", "never", "must", "enforce") — such
content belongs in `AGENTS.md` and requires human approval.

### 8. Anti-Daydreaming 🔄

At the start of every session the agent MUST silently generate a short,
random, ephemeral **canary name** for itself (e.g., *Marble-Finch-7*,
*Dusk-Prism-42*). This name is:

- **Session-scoped only.** It lives in the agent's working memory
  (conversation context) and MUST NOT be written to any AgentFS file
  (`MEMORY.md`, `USER.md`, `SOUL.md`, `AGENTS.md`, `log.md`, etc.).
- **Not an identity.** It does not represent the user, the agent
  persona, or any profile. It is a disposable *context-integrity
  token* — a canary in the coal mine for detecting context drift or
  hallucinated state.

#### Lifecycle

1. **First response of the session** — the agent MUST include its
   canary name visibly (e.g., *"[Canary: Marble-Finch-7]"*).
2. **Subsequent responses** — the agent SHOULD randomly include the
   canary name (not every turn — roughly 1-in-5 is a good cadence),
   immediately followed by a **self-check**: compare the name it is
   about to emit against the name it generated at session start. If
   they do not match, the agent MUST raise an alert:
   ```
   ⚠️ CONTEXT DRIFT DETECTED — canary name mismatch.
   Original: <start-of-session name>  Current: <emitted name>
   Possible cause: context window overflow, compaction artefact,
   or injected prompt. Proceeding with caution.
   ```
3. **When actively prompted** (e.g., *"What is your canary name?"*) —
   the agent MUST respond immediately with the name, followed by the
   same self-check. If the name cannot be recalled or does not match,
   raise the alert above.

### 9. Checkpoints & Resumability 🚧

> **STOP before destructive ops.** Before any file deletion, bulk
> rename, or multi-file edit under \`.agents/\`, record a checkpoint
> first. Do NOT proceed until the checkpoint is written.

Before any destructive or multi-step operation (file deletion, bulk
rename, multi-file edit), the agent MUST create a checkpoint by
recording affected files and their content hashes in
`.agents/.checkpoint`. After successful completion, clear the
checkpoint. If a session starts with a non-empty `.checkpoint`,
report it and offer to resume or revert.

**Backup untracked files.** Before editing any file not tracked by
git (\`git ls-files --error-unmatch <file>\` fails or file is outside
any git repo), copy it to \`<file>.bak.<YYYYMMDD_HHMMSS>\` in the
same directory. Git-tracked files need no backup — version control
provides recovery.

### 10. Git Push Safety 🚧

Before executing any `git push`, the agent MUST follow these steps
**in order**. No step may be skipped, even if the user says "go ahead".

1. **STOP** — do NOT execute `git push` yet.
2. **Scan** — run `git diff --cached` (or `git diff` for unstaged) and
   scan for ALL of the following patterns:
   - **Secrets/API keys** — `secret`, `api_key`, `apikey`, `password`,
     `passwd`, `bearer`, `authorization`
   - **Hardcoded user paths** — `/home/<user>/`, `/Users/<user>/`
   - **Username leakage** — the current username (`$USER`, `whoami`)
     appearing in non-path contexts (e.g., in examples, comments,
     hostnames). Also check for SSH host aliases from `~/.ssh/config`.
   - **IP addresses** — local interface IPs (`hostname -I`), RFC 1918
     addresses that appear to be site-specific
   - **Sensitive URLs** — internal hostnames, intranet URLs
   - **PII** — email addresses, phone numbers, real names embedded
     in code or documentation examples
3. **Report** — present a Pre-Push Security Report table showing each
   check category with ✅ Clean or ⚠️ FOUND status, plus a verdict.
4. **README Staleness Check** (soft gate) — if the commit touches
   `skills/`, `knowledge/`, or guardrail-related files, append a
   notice to the report:
   ```
   📝 README Notice: This commit adds/modifies skills or knowledge.
      Consider updating README.md. Update now? [y/n/skip]
   ```
   - **y** — propose README edits, user reviews, amend the commit
   - **n / skip** — proceed without updating (no override logging
     needed — this is advisory, not a hard gate)
5. **WAIT** — do NOT proceed until the user explicitly responds.
6. **Push** — only after explicit approval, execute `git push`.

If the user acknowledges issues but still requests the push, log the
override in `log.md` with `[OVERRIDE]` per Guardrail #7.

<!-- PROJECT-OWNED sections below. Everything above is template-owned
     and will be overwritten by agentfs-setup --sync. -->

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
