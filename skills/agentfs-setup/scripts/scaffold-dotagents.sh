#!/usr/bin/env bash
# scaffold-dotagents.sh — Create the .agents/ directory tree and seed files.
#
# Usage: bash scaffold-dotagents.sh [--mode user|project] [ROOT_DIR]
#
#   --mode project  Scaffold ./.agents/ with all layers (default)
#                   Creates: skills/, profiles/, memories/, SOUL.md, index.md, log.md
#                   This is the primary workflow — run once per repo.
#
#   --mode user     Scaffold ~/.agents/ with skills/ and knowledge/ only
#                   Creates an empty structural skeleton for selective skill adoption.
#                   Only needed for "minimal install" users who did NOT clone the
#                   AgentFS repo directly into ~/.agents/ (Path B).
#                   Users who cloned the repo to ~/.agents/ (Path A) do NOT need this.
#
#   ROOT_DIR        Defaults to . for project mode, ~ for user mode
#
# The script is idempotent — it skips files that already exist.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────
MODE="project"
ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2,,}"  # lowercase
      shift 2
      ;;
    *)
      ROOT="$1"
      shift
      ;;
  esac
done

if [[ "$MODE" != "user" && "$MODE" != "project" ]]; then
  echo "[agentfs-setup] ERROR: --mode must be 'user' or 'project' (got: $MODE)" >&2
  exit 1
fi

# Default root based on mode
if [[ -z "$ROOT" ]]; then
  if [[ "$MODE" == "user" ]]; then
    ROOT="$HOME"
  else
    ROOT="."
  fi
fi

ROOT="$(cd "$ROOT" && pwd)"
AGENTS="$ROOT/.agents"

echo "[agentfs-setup] Scaffolding .agents/ under $ROOT (mode: $MODE)"

# ── Layer directories ────────────────────────────────────────────────
mkdir -p "$AGENTS/skills"

if [[ "$MODE" == "user" ]]; then
  mkdir -p "$AGENTS/knowledge"
fi

if [[ "$MODE" == "project" ]]; then
  mkdir -p "$AGENTS/profiles"
  mkdir -p "$AGENTS/memories"
fi

# ── index.md (OKF entry point — NO yaml frontmatter) ────────────────
if [[ ! -f "$AGENTS/index.md" ]]; then
  if [[ "$MODE" == "user" ]]; then
cat > "$AGENTS/index.md" << 'EOF'
# .agents — User Directory Index

> Progressive-disclosure entry point. Browse folders before opening files.
> Shared skills and knowledge visible across projects and agents.

| Layer | Path | Purpose |
|-------|------|---------|
| Capability | [skills/](./skills/index.md) | Shared agent workflows (Agent Skills format) |
| Knowledge | [knowledge/](./knowledge/index.md) | Shared knowledge base (OKF format) |

See [log.md](./log.md) for recent activity.
EOF
  else
cat > "$AGENTS/index.md" << 'EOF'
# .agents — Directory Index

> Progressive-disclosure entry point. Browse folders before opening files.

| Layer | Path | Purpose |
|-------|------|---------|
| Identity | [SOUL.md](./SOUL.md) | Default agent identity (human-authored) |
| Profiles | [profiles/](./profiles/index.md) | Named agent profiles with individual SOUL & memories |
| Capability | [skills/](./skills/index.md) | Project-scoped agent workflows (Agent Skills format) |
| Memories | [memories/](./memories/MEMORY.md) | Default agent's experiences and learned context |

See [log.md](./log.md) for recent activity.
EOF
  fi
  echo "  ✓ index.md"
fi

# ── log.md (append-only chronological tracker) ───────────────────────
if [[ ! -f "$AGENTS/log.md" ]]; then
cat > "$AGENTS/log.md" << EOF
# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## $(date '+%Y-%m-%d %H:%M')

- Initialized .agents/ directory structure (mode: $MODE).
EOF
  echo "  ✓ log.md"
fi

# ── knowledge/index.md (OKF knowledge root — USER mode only) ────────
if [[ "$MODE" == "user" && ! -f "$AGENTS/knowledge/index.md" ]]; then
cat > "$AGENTS/knowledge/index.md" << 'EOF'
# Knowledge Index

> Semantic context layer built with the Open Knowledge Format (OKF).
> Every concept file below MUST contain a YAML frontmatter block with a
> required `type` field.

<!-- Add rows as new knowledge categories are created. -->
EOF
  echo "  ✓ knowledge/index.md"
fi

# ── skills/index.md (skill directory listing — NO yaml frontmatter) ──
if [[ ! -f "$AGENTS/skills/index.md" ]]; then
cat > "$AGENTS/skills/index.md" << 'EOF'
# Skills Index

> 0 skills | Sorted by reverse chronological order (newest first).

| Skill | Description | Updated |
|-------|-------------|---------|

<!-- Rows are added when skills are created. Sorted newest-first by the
     Updated timestamp. Use the skill-index skill to regenerate this file
     automatically. -->
EOF
  echo "  ✓ skills/index.md"
fi

# ── PROJECT mode: seed profiles/index.md, SOUL.md and memories/ ──────
if [[ "$MODE" == "project" ]]; then

  # profiles/index.md — profile directory listing
  if [[ ! -f "$AGENTS/profiles/index.md" ]]; then
cat > "$AGENTS/profiles/index.md" << 'EOF'
# Agent Profiles

> 0 profiles | Named agent profiles for multi-agent collaboration.
> Each profile defines a distinct ROLE with its own identity (SOUL.md)
> and memories. Sorted by reverse chronological order (newest first).

| Profile | Identity | Memories | Updated |
|---------|----------|----------|---------|

<!-- Rows are added automatically by the agentfs-profile skill.
     Sorted newest-first by the Updated timestamp. -->
EOF
    echo "  ✓ profiles/index.md"
  fi

  # SOUL.md — default agent identity (human-authored)
  if [[ ! -f "$AGENTS/SOUL.md" ]]; then
cat > "$AGENTS/SOUL.md" << 'EOF'
# Agent Identity

<!-- Human-authored. Define who the default agent IS — tone, style,
     communication defaults. This is the foundation of the system prompt. -->

<!-- Example:
You are a pragmatic senior engineer who values clarity over ceremony.
You push back when something is a bad idea.
You prefer simple systems over clever systems.
-->
EOF
    echo "  ✓ SOUL.md"
  fi

  # memories/USER.md — default agent's model of the user (agent-writable)
  if [[ ! -f "$AGENTS/memories/USER.md" ]]; then
cat > "$AGENTS/memories/USER.md" << 'EOF'
# User Profile

<!-- Agent-authored. The agent updates this file as it learns about the user
     through conversation — role, preferences, interests, communication style.
     Do NOT edit manually; let the agent manage this file. -->
EOF
    echo "  ✓ memories/USER.md"
  fi

  # memories/MEMORY.md — default agent's project experiences (agent-writable)
  if [[ ! -f "$AGENTS/memories/MEMORY.md" ]]; then
cat > "$AGENTS/memories/MEMORY.md" << 'EOF'
# Project Experiences

<!-- Agent-authored. The agent records project-specific observations and
     experiences here — things discovered through working in this project
     that are worth remembering across sessions.

     SCOPE:  This file is PROJECT-scoped. Only record observations tied
             to THIS project.
     CONTENT: Concrete experiences — "discovered that X behaves like Y",
             "the build breaks when Z", "this codebase prefers pattern W".
     NOT HERE: Rules, guardrails, or workflow policies belong in AGENTS.md.
             User preferences belong in USER.md.
             Distilled cross-project knowledge graduates to OKF bundles
             under ~/.agents/knowledge/.

     NATURAL LANGUAGE SIGNALS from the user:
       "remember this", "note that", "save this for later",
       "keep in mind" → add an entry here.
       "this is a rule", "always do X", "never do Y" → add to AGENTS.md
       guardrails instead.

     Do NOT edit manually; let the agent manage this file. -->
EOF
    echo "  ✓ memories/MEMORY.md"
  fi

fi

echo "[agentfs-setup] .agents/ scaffold complete (mode: $MODE)."
