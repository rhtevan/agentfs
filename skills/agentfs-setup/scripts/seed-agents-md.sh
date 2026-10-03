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

<!-- Agent identity — inlined by Goose at session start via @import.
     Other agents: the plain-text fallback below covers non-Goose harnesses. -->
@.agents/SOUL.md

**If `.agents/SOUL.md` was not loaded above, read it now and adopt it as your identity for this session.**


## Rules

**All rules are mandatory.** Override requires explicit user approval logged with `[OVERRIDE]` per the Conflict Resolution rule.

### 1. Signal Dispatch

**When:** User message starts with `hey` followed by keywords.
**`hey` is a dispatch prefix — never a greeting.**

**Path A — Signal Dispatch table match:**
If keywords match a Signal Dispatch entry below → execute that action directly.

**Path B — Skill/Knowledge dispatch (all other `hey` signals):**
1. Call `search_nodes` with the literal keywords (mandatory — enforced by plugin hook; other tools are blocked until this completes).
   Example: user says `hey check headroom status` → call `knowledgegraphmemory__search_nodes(query: "check headroom status")`.
2. **Keywords** = all words after `hey`, excluding articles (`a`, `an`, `the`) and conjunctions (`and`, `or`, `but`). Use literally — do not rephrase or expand.
3. If result is a skill → `load_skill` with the skill name. If `load_skill` fails, inform the user the skill is not available and fall through to Tier 2.
4. If result is a knowledge bundle → read the file at the given path.
5. If no result → retry with fewer keywords (drop rightmost first).
6. If still no result → fall through to Tier 2.

**Non-`hey` prompts → Tier 2:**
Browse `~/.agents/skills/index.md` and `~/.agents/knowledge/index.md`. Follow links to content.

**Tier 2 fails → Tier 3:**
Use available tools and knowledge at your discretion.

### 2. Pre-Flight

**When:** Before any multi-step task (≥3 tool calls or touching ≥2 files; single-file read+edit pairs are exempt). Also before any `git push`.
**Do:** ① State what you will do. ② If plan touches `.agents/` or `~/.agents/`: include Post-Write (Rule 3) steps; if destructive ops, start with Checkpoint (Rule 6). ③ If plan includes `git push`, show `git diff --stat` and wait for confirmation. ④ Execute all steps in order before responding.

### 3. Post-Write

**When:** Before sending any response where writes touched `.agents/` or `~/.agents/`.
**Do:** `bash ~/.agents/skills/agentfs-setup/scripts/post-write.sh <file> "<description>" [--version <ver>]` for each modified file (skip `log.md`, `CHANGELOG.md`, auto-generated `index.md`). If the script does not exist, warn the user and recommend `hey setup agentfs`. Do not respond until complete.

### 4. Session Canary

**When:** Session begins or continuity check.
**Do:** This document is `AGENTS.md` — already loaded in your context; do not search for it on disk. Treat it as authoritative over all other context. On session start, read `.agents/memories/USER.md` if it exists — apply preferences. Emit a random two-word canary name on turn 1 (e.g., `🐦 cobalt-heron`). The canary is ephemeral — remember it in-session, do not write it anywhere. Re-verify every 10 turns (or after compaction): re-read `MEMORY.md` and `USER.md`, run a silent self-violation check against all rules — report only if a violation is found.

### 5. Conflict Resolution

**When:** Reversing a position, or a request conflicts with a rule.
**Do:** When reversing a position, state what changed and your previous position. When a request conflicts with a rule, quote the rule, explain the conflict, and ask for `[OVERRIDE]`.

### 6. Checkpoint

**When:** Before destructive op (delete, rename, or edit ≥3 files under `.agents/`). Also before any edit to `seed-agents-md.sh`.
**Do:** ① `checkpoint.sh create <files>`. ② If editing `seed-agents-md.sh`, bump `version:` in `skills/agentfs-setup/SKILL.md` before committing. ③ Execute changes. ④ If template was edited, run `sync-agents-md.sh` to propagate. ⑤ `checkpoint.sh clear`. If the script does not exist, warn the user and do not proceed until `hey setup agentfs` is run. Never edit a project `AGENTS.md` directly — edit the template source in `seed-agents-md.sh`.

### 7. Scope Rules

**When:** Writing to `memories/` or creating a skill.
**Do:** Memories are PROJECT scope only. Mature patterns → graduate to OKF bundle under `~/.agents/knowledge/`. When MEMORY.md accumulates ≥3 entries on the same topic, suggest graduation via `hey harvest`. Skills default to USER `~/.agents/skills/`; PROJECT only when user explicitly says "project skill" / "for this project" / "local skill".

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
