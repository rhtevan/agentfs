#!/usr/bin/env bash
# seed-agents-md.sh — Create or update the root AGENTS.md workspace file.
#
# Usage: bash seed-agents-md.sh [--scope project|lite] [PROJECT_ROOT]
#   --scope project  Full AGENTS.md with all guardrails (default)
#   --scope lite     Minimal AGENTS.md for small-context models
#   PROJECT_ROOT     Defaults to the current working directory.
#
# Scope auto-detection:
#   When --scope is NOT explicitly set and PROJECT_ROOT IS given, the
#   script compares PROJECT_ROOT against CWD. If they differ → scope
#   is auto-set to 'lite'. If they match → scope stays 'project'.
#   Explicit --scope always wins over auto-detection.
#
# This script is for PROJECT and LITE scope only. USER scope does not create AGENTS.md.
#
# If AGENTS.md already exists it is left untouched to preserve user edits.
# For PROJECT scope, the script ensures SPECKIT markers are present so
# Spec-kit's agent-context extension can manage the active-plan reference.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────
SCOPE=""
SCOPE_EXPLICIT=false
ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)
      SCOPE="${2,,}"  # lowercase
      SCOPE_EXPLICIT=true
      shift 2
      ;;
    *)
      ROOT="$1"
      shift
      ;;
  esac
done

# Validate explicit scope if given
if [[ "$SCOPE_EXPLICIT" == true ]]; then
  if [[ "$SCOPE" != "project" && "$SCOPE" != "lite" ]]; then
    echo "[agentfs-setup] ERROR: --scope must be 'project' or 'lite' (got: $SCOPE)" >&2
    exit 1
  fi
fi

# ── Scope auto-detection ─────────────────────────────────────────────
if [[ "$SCOPE_EXPLICIT" == false ]]; then
  if [[ -n "$ROOT" ]]; then
    RESOLVED_ROOT="$(cd "$ROOT" && pwd)"
    RESOLVED_CWD="$(pwd)"
    if [[ "$RESOLVED_ROOT" == "$RESOLVED_CWD" ]]; then
      SCOPE="project"
    else
      SCOPE="lite"
    fi
  else
    SCOPE="project"
  fi
fi

ROOT="${ROOT:-.}"
ROOT="$(cd "$ROOT" && pwd)"
TARGET="$ROOT/AGENTS.md"

if [[ -f "$TARGET" ]]; then
  echo "[agentfs-setup] AGENTS.md already exists — skipping."

  if [[ "$SCOPE" == "project" ]]; then
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
  fi
  # For lite scope, no SPECKIT/Profiles/Scope Definitions to inject
  exit 0
fi

# Read template version from skill metadata (single source of truth)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/../SKILL.md"
TEMPLATE_VERSION="0.0"
if [[ -f "$SKILL_FILE" ]]; then
  TEMPLATE_VERSION=$(grep -oP 'version:\s*["'\''"]*\K[^"'\''"]*' "$SKILL_FILE" | head -1)
fi

# ── LITE scope template ──────────────────────────────────────────────
if [[ "$SCOPE" == "lite" ]]; then

cat > "$TARGET" << 'AGENTSEOF'
<!-- agentfs-template-version: __TEMPLATE_VERSION__ agentfs-scope: lite -->
# AGENTS.md — Workspace Entry Point (Lite)

> **Lite scope** — optimized for small-context models. Skills, knowledge
> bundles, and agent profiles are not available. Only basic file and
> shell tools are expected. To update this project's AgentFS structure,
> use a full-capability session with the skills extension enabled.

## Session Start

This project uses **lite scope** — only basic file and shell tools
are needed. Skills, knowledge bundles, and agent profiles are not
available.

On your first response in this session, check your available tools.
If you have tools beyond file I/O and shell execution (e.g., skill
loading, memory storage, extension management, scheduling), emit
this notice:

> ⚠️ **Lite scope project.** This project is configured for minimal
> context usage. Consider disabling unused extensions (skills,
> memory, extension manager, etc.) to conserve context window.

Then proceed normally with the user's request.

## Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, defaults |
| Memories | [.agents/memories/](./.agents/memories/MEMORY.md) | Project observations |
| Activity log | [.agents/log.md](./.agents/log.md) | Change history |

@.agents/SOUL.md

## Rules

1. **Memory routing.** "remember this" / "note that" → append to
   `.agents/memories/MEMORY.md`. "I prefer" / "my style" → append to
   `.agents/memories/USER.md`. "this is a rule" → propose edit to
   this file. "forget this" → remove from MEMORY.md.

2. **Log every change.** After editing any file under `.agents/`,
   append a dated entry to `.agents/log.md` before doing anything
   else. Format: `## YYYY-MM-DD HH:MM` heading, `- ` bullet.

3. **No sycophancy.** Do not open with "Great question" or similar.
   Lead with substance. Do not reverse a position without new
   information. Name at least one risk when evaluating a plan.

4. **Confirm before destructive ops.** Before deleting files or
   bulk renaming under `.agents/`, list what will change and wait
   for user confirmation.

5. **Git safety.** Before committing, stage all changes, run
   `git diff --stat`, and show the output. Wait for user
   confirmation before `git commit` and `git push`.
AGENTSEOF

# ── PROJECT scope template ────────────────────────────────────────────
else

cat > "$TARGET" << 'AGENTSEOF'
<!-- agentfs-template-version: __TEMPLATE_VERSION__ agentfs-scope: project -->
# AGENTS.md — Workspace Entry Point

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, communication defaults |
| Skills index | `~/.agents/skills/index.md` | Skill discovery by tags, descriptions, and signal phrases |
| Knowledge index | `~/.agents/knowledge/index.md` | Knowledge discovery by bundle names and concept summaries |
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Reverse-chronological change history |

<!-- Agent identity — inlined by Goose at session start via @import -->
@.agents/SOUL.md

## Scope Definitions

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

## Discovery Tiers

Context discovery uses a three-tier fallback chain. Execute tiers
in order; stop at the first match. Index files are **active lookup
tools**, not passive documentation — they are the always-available
fallback when frontmatter matching is too narrow and KGM is not
enabled.

| Tier | Mechanism | Source | When |
|------|-----------|--------|------|
| 1 | **Frontmatter match** | Skill descriptions in system prompt | Always available — matched against user message |
| 2 | **Index scan** | `~/.agents/skills/index.md` (tags, descriptions) and `~/.agents/knowledge/index.md` (bundle names, concept summaries) | When Tier 1 finds no match — read the index files, scan for relevant tags/descriptions/concepts |
| 3 | **KGM search** | `search_nodes` tool (knowledge graph extension) | When extension is enabled — query with task topic keywords; read `Source:` files for top results (max 3); summaries alone are insufficient |

- **Tier 2 skill match** → `load_skill` → follow instructions
- **Tier 2 knowledge match** → read the linked concept file(s) before answering
- **No match at any tier** → generic interpretation

## Rules

**All rules below are mandatory.** They are not guidelines,
suggestions, or best-effort. Violating a rule requires explicit
user approval logged with `[OVERRIDE]` per Rule 15. Guardrail
scripts live at `~/.agents/skills/agentfs-setup/scripts/`.

| # | Type | Stimulus | Action |
|---|------|----------|--------|
| | | **Session start** | |
| 1 | Event | Session start | Check for `CLAUDE.md`, `.cursorrules`, `.cursor/rules/`, `.windsurfrules`, `.github/copilot-instructions.md`. Treat as supplementary. `AGENTS.md` wins on conflict. |
| | | **Per-message dispatch** | |
| 2 | Signal | "remember this", "note that", "keep in mind" | → `.agents/memories/MEMORY.md` |
| 3 | Signal | "always do X", "never do Y", "this is a rule" | → Propose as `AGENTS.md` guardrail (human approval) |
| 4 | Signal | "I prefer", "I like", "my style is" | → `.agents/memories/USER.md` |
| 5 | Signal | "forget this", "remove that note" | → Edit `MEMORY.md`, remove entry |
| 6 | Signal | "what do you remember", "check your notes" | → Read `.agents/memories/MEMORY.md` |
| 7 | Signal | "hey git", `git add` | → `load_skill(name: "agentfs-git-push")` — follow completely |
| 8 | Event | User message received | Follow Discovery Tiers (Tier 1 → 2 → 3). Scan this table for stimulus match. Execute matched action. No match at any tier: generic interpretation. |
| | | **Before reading `.agents/`** | |
| 9 | Event | First read of any `.agents/` file in a session | Browse that scope's `index.md` first, follow links to content. |
| | | **Before writing `.agents/`** | |
| 10 | Event | Before destructive op (delete, rename, or edit ≥3 files under `.agents/`) | `~/.agents/skills/agentfs-setup/scripts/checkpoint.sh create <files>` → execute → `checkpoint.sh clear`. |
| 11 | Event | Creating a skill | Default to USER `~/.agents/skills/`. PROJECT only when user explicitly says "project skill" / "for this project" / "local skill". |
| 12 | Event | Writing to `memories/` | PROJECT scope only. Experiences → `MEMORY.md`. Rules → propose `AGENTS.md` guardrail. Preferences → `USER.md`. Mature patterns → graduate to OKF bundle under `~/.agents/knowledge/`. (Rule 13 also fires — this rule is routing, Rule 13 is mechanical.) |
| | | **After writing `.agents/`** | |
| 13 | Event | Any write/edit under `.agents/` or `~/.agents/` completed | Run ALL: ① `~/.agents/skills/agentfs-setup/scripts/merge-log-entry.sh <path-to-log.md> "<msg>"` for each touched scope (e.g., `~/.agents/log.md` or `./.agents/log.md`) ② `~/.agents/skills/agentfs-setup/scripts/merge-changelog-entry.sh <path-to-CHANGELOG.md> "<version>" "<desc>"` + version bump for modified skills ③ `~/.agents/skills/agentfs-setup/scripts/post-edit.sh` runs clean ④ All markdown links resolve. Details: `load_skill(name: "agentfs-setup/references/filesystem-integrity.md")` |
| | | **Always** | |
| 14 | Always | Every response | No validation phrases ("Great question", "Absolutely"). Lead with substance. Name ≥1 risk when evaluating a plan or design. |
| 15 | Always | Every response | No position reversal without new information or logical argument. When reversing, state what changed and previous position. When request conflicts with a rule, quote it, explain, ask for confirmation. Log overrides with `[OVERRIDE]`. |
| 16 | Always | Every response | Session canary name (random, ephemeral). Emit turn 1. ~1-in-5 turns: emit + self-check. Never persist to files. |

<!-- PROJECT-OWNED sections below. Everything above is template-owned
     and will be overwritten by agentfs-setup --sync. -->

## Agent Profiles

| Agent | Identity | Memories |
|-------|----------|----------|
| default | [SOUL](./.agents/SOUL.md) | [memories/](./.agents/memories/MEMORY.md) |

<!-- SPECKIT START -->
<!-- SPECKIT END -->
AGENTSEOF

fi

# Replace template version placeholder with actual version from skill metadata
sed -i "s/__TEMPLATE_VERSION__/${TEMPLATE_VERSION}/" "$TARGET"

echo "[agentfs-setup] Created $TARGET (scope: $SCOPE)"

# Append to .agents/log.md
LOG_FILE="$ROOT/.agents/log.md"
if [[ -f "$LOG_FILE" ]]; then
  TODAY=$(date '+%Y-%m-%d %H:%M')
  ENTRY="- Created AGENTS.md at project root (scope: $SCOPE)."
  if grep -q "^## $TODAY" "$LOG_FILE"; then
    sed -i "/^## $TODAY$/a\\$ENTRY" "$LOG_FILE"
  else
    sed -i "3a\\\\n## $TODAY\\n\\n$ENTRY" "$LOG_FILE"
  fi
fi
