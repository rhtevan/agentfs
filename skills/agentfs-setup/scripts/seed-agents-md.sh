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
AgentFS operates in two scopes.\
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

<!-- Agent identity — inlined by Goose at session start via @import.
     Other agents: the plain-text fallback below covers non-Goose harnesses. -->
@.agents/SOUL.md

**If `.agents/SOUL.md` was not loaded above, read it now and adopt it as your identity for this session.**

## Rules

1. **Memory routing.** "remember this" / "note that" → append to
   `.agents/memories/MEMORY.md`. "I prefer" / "my style" → append to
   `.agents/memories/USER.md`. "this is a rule" → propose edit to
   this file. "forget this" → remove from MEMORY.md.

2. **Log every change.** After editing any file under `.agents/`,
   append a dated entry to `.agents/log.md`. Do this before any
   other action. Format: `## YYYY-MM-DD HH:MM` heading, `- ` bullet.

3. **No sycophancy.** Do not open with "Great question" or similar.
   Lead with substance. Do not reverse a position without new
   information. Name at least one risk when evaluating a plan.

4. **Confirm before destructive ops.** Before deleting files or
   bulk renaming under `.agents/`, list what will change. Wait
   for user confirmation before proceeding.

5. **Git safety.** Before committing, stage all changes. Run
   `git diff --stat`. Show the output to the user. Wait for
   user confirmation before `git commit` and `git push`.

6. **Plan before complex work.** For tasks where steps depend on
   each other or span multiple phases: define pass/fail criteria
   (Design Spec) first, then list numbered action items (Action
   Spec). Execute in order. Run the criteria check at the end —
   do not claim done until all pass.
AGENTSEOF

# ── PROJECT scope template ────────────────────────────────────────────
else

cat > "$TARGET" << 'AGENTSEOF'
<!-- agentfs-template-version: __TEMPLATE_VERSION__ agentfs-scope: project -->
# AGENTS.md — Workspace Entry Point

<!-- Agent identity — inlined by Goose at session start via @import.
     Other agents: the plain-text fallback below covers non-Goose harnesses. -->
@.agents/SOUL.md

**If `.agents/SOUL.md` was not loaded above, read it now and adopt it as your identity for this session.**


## Rules

**All rules are mandatory.** Override requires explicit user approval logged with `[OVERRIDE]` per the Conflict Resolution rule.

**On every turn:** Before acting on the user's request, scan each
rule's **When** clause against the current request. If matched,
follow the **Do** block before proceeding.

### 1. Signal Dispatch

**When:** User message starts with `hey` followed by keywords.
`hey` is a dispatch prefix — never a greeting.

**Do:**

**Path A — Signal Dispatch table match:**
If keywords match a Signal Dispatch entry below → execute that action directly.

**Path B — Skill/Knowledge dispatch (all other `hey` signals):**
1. Extract keywords: take every word after `hey`. Drop only articles
   (`a`, `an`, `the`) and conjunctions (`and`, `or`, `but`).
   Keep all other words exactly as the user typed them.
   Do NOT add, remove, reorder, or rephrase any word.
   Example: user says `hey crc status` → keywords = `crc status`.
2. Call `search_nodes` with those exact keywords (mandatory —
   enforced by plugin hook; other tools are blocked until this
   completes). KGM search matches exact words, not fuzzy meaning.
   Rephrased or expanded queries will miss.
3. If result is a skill → call `load_skill` with the skill name.
   You MUST call `load_skill`. Do NOT skip it. Do NOT execute the
   skill from memory or training data.
4. If result is a knowledge bundle → read the file at the given path.
5. If no result → retry: drop the rightmost keyword and search again.
6. If still no result → fall through to Tier 2.

**Non-`hey` prompts → Tier 2:**
Browse `~/.agents/skills/index.md` and `~/.agents/knowledge/index.md`. Follow links to content.

**Tier 2 fails → Tier 3:**
Use available tools and knowledge at your discretion.

### 2. Pre-Flight

**When:** Before any task that modifies ≥2 files, has step
dependencies, or includes \`git push\`. Single-file read+edit
pairs are exempt.

**Do:**

Assess task complexity, then follow the matching tier:

**Tier 1 — Standard** (steps are independent, single phase):
1. State the plan: what files change, in what order, what outcome.
2. Fold in constraints: Checkpoint if destructive,
   \`git diff --stat\` + confirmation if \`git push\`.
3. Execute. Confirm the stated outcome before responding.

**Tier 2 — Specification-Driven** (steps have dependencies,
multi-phase, or user explicitly requests structured execution):
1. Define pass/fail criteria (**Validation Gate**).
2. Decompose into numbered actions with expected outcomes.
3. Fold in constraints: Checkpoint, git push confirmation.
4. Execute in order. Stop and report on failure.
5. Run the Validation Gate. Do not claim completion until all pass.

### 3. Session Canary

**When:** Turn 1 of any session, or every 10 turns, or after compaction.

**Do:**
1. Write a random two-word canary at the top of your response.
   Use this format: \`🐦 word-word\` (example: \`🐦 cobalt-heron\`).
2. Read \`.agents/memories/USER.md\`. Apply any preferences found.
3. Keep the canary in memory for this session. Do not write it to any file.
4. On every 10th turn and after every compaction: re-read \`MEMORY.md\`
   and \`USER.md\`. Run a silent self-check against all rules.
   Report only if you find a violation.

### 4. Conflict Resolution

**When:** Reversing a position, or a request conflicts with a rule.

**Do:**
1. When reversing a position: state what changed. State your previous position.
2. When a request conflicts with a rule: quote the rule. Explain the conflict. Ask the user for `[OVERRIDE]` approval.

### 5. Checkpoint

**When:** Before destructive op (delete, rename, or edit ≥3 files under `.agents/`). Also before any edit to `seed-agents-md.sh`.

**Do:**
1. Run `checkpoint.sh create <files>`.
2. If editing `seed-agents-md.sh`: bump `version:` in `skills/agentfs-setup/SKILL.md` before committing.
3. Execute the changes.
4. If the template was edited: run `sync-agents-md.sh` to propagate.
5. Run `checkpoint.sh clear`.
6. If `checkpoint.sh` does not exist: warn the user. Do not proceed until `hey setup agentfs` is run.
7. Never edit a project `AGENTS.md` directly. Edit the template source in `seed-agents-md.sh`.

### 6. Scope & Post-Write

**When:** Writing to any file under `.agents/` or `~/.agents/`.

**Do:**
1. Scope: write memories to PROJECT scope only (`.agents/memories/`).
   Place skills in USER scope (`~/.agents/skills/`) by default.
   Use PROJECT scope only when user says "project skill" or "local skill".
2. After EACH write (except `log.md`, `CHANGELOG.md`, auto-generated
   `index.md`), immediately run:
   `bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh <file> "<description>"`
   Do NOT respond to the user until the command completes.
3. When MEMORY.md accumulates ≥3 entries on same topic: suggest
   graduation via `hey harvest`.

## Signal Dispatch

When the user message starts with `hey`, match the keywords and route:

__SIGNAL_DISPATCH_TABLE__

## Quick Orientation

| Resource | Path | What's Inside |
|----------|------|---------------|
| Agent identity | [.agents/SOUL.md](./.agents/SOUL.md) | Tone, style, communication defaults |
| Skills index | `~/.agents/skills/index.md` | Skill discovery |
| Knowledge index | `~/.agents/knowledge/index.md` | Knowledge discovery |
| Directory index | [.agents/index.md](./.agents/index.md) | Full layer listing |
| Activity log | [.agents/log.md](./.agents/log.md) | Change history |

**Context lookup fallback:** When `search_nodes` is unavailable, browse `~/.agents/skills/index.md` and `~/.agents/knowledge/index.md` (USER), or `./.agents/index.md` (PROJECT) to discover skills, knowledge, and directory structure.

## Scope Definitions

AgentFS operates in two scopes.

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

# Generate Signal Dispatch table from patterns.txt (single source of truth)
PATTERNS_FILE="$HOME/.agents/plugins/signal-dispatch/patterns.txt"
if [[ -f "$PATTERNS_FILE" ]]; then
  # Build the Markdown table from patterns.txt
  TABLE_CONTENT="| Pattern | Action |\n|---------|--------|"

  # Group patterns by action to combine into single rows
  declare -A ACTION_PATTERNS
  while IFS='|' read -r prefix action; do
    [[ -z "$prefix" || "$prefix" =~ ^# ]] && continue
    prefix="$(echo "$prefix" | sed 's/[[:space:]]*$//')"
    action="$(echo "$action" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')"
    if [[ -n "${ACTION_PATTERNS[$action]+x}" ]]; then
      ACTION_PATTERNS[$action]="${ACTION_PATTERNS[$action]} / \`hey ${prefix} ...\`"
    else
      ACTION_PATTERNS[$action]="\`hey ${prefix} ...\`"
    fi
  done < "$PATTERNS_FILE"

  for action in "${!ACTION_PATTERNS[@]}"; do
    TABLE_CONTENT="$TABLE_CONTENT\n| ${ACTION_PATTERNS[$action]} | → ${action} |"
  done

  # Replace placeholder with generated table
  # Use a temp file to handle multi-line replacement
  TABLE_FILE=$(mktemp)
  printf '%b\n' "$TABLE_CONTENT" > "$TABLE_FILE"
  sed -i "/__SIGNAL_DISPATCH_TABLE__/{
    r $TABLE_FILE
    d
  }" "$TARGET"
  rm -f "$TABLE_FILE"
else
  # Fallback: remove placeholder if patterns.txt not found
  sed -i "s/__SIGNAL_DISPATCH_TABLE__/<!-- patterns.txt not found — table not generated -->/" "$TARGET"
  echo "[agentfs-setup] WARNING: patterns.txt not found, Signal Dispatch table not generated."
fi

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
