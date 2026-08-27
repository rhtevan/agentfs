#!/usr/bin/env bash
# scaffold-dotagents.sh — Create the .agents/ directory tree and seed files.
#
# Usage: bash scaffold-dotagents.sh [--scope user|project|lite] [ROOT_DIR]
#
#   --scope project  Scaffold ./.agents/ with all layers (default)
#   --scope lite     Scaffold ./.agents/ with minimal layers for small-context models
#   --scope user     Scaffold ~/.agents/ with skills/ and knowledge/ only
#
#   ROOT_DIR         Target directory. Defaults to . for project, ~ for user.
#
# Scope auto-detection:
#   When --scope is NOT explicitly set and ROOT_DIR IS given, the script
#   compares ROOT_DIR against CWD. If they differ → scope is auto-set
#   to 'lite'. If they match (or ROOT_DIR is absent) → scope stays 'project'.
#   --scope user is never auto-detected — it must always be explicit.
#   Explicit --scope always wins over auto-detection.
#
# The script is idempotent — it skips files that already exist.

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
  if [[ "$SCOPE" != "user" && "$SCOPE" != "project" && "$SCOPE" != "lite" ]]; then
    echo "[agentfs-setup] ERROR: --scope must be 'user', 'project', or 'lite' (got: $SCOPE)" >&2
    exit 1
  fi
fi

# ── Scope auto-detection ─────────────────────────────────────────────
if [[ "$SCOPE_EXPLICIT" == false ]]; then
  if [[ -n "$ROOT" ]]; then
    # ROOT_DIR given — compare against CWD to decide project vs lite
    # Create target dir first if it doesn't exist (so realpath works)
    if [[ ! -d "$ROOT" ]]; then
      mkdir -p "$ROOT"
      echo "[agentfs-setup] Created target directory: $ROOT"
    fi
    RESOLVED_ROOT="$(cd "$ROOT" && pwd)"
    RESOLVED_CWD="$(pwd)"
    if [[ "$RESOLVED_ROOT" == "$RESOLVED_CWD" ]]; then
      SCOPE="project"
    else
      SCOPE="lite"
      echo "[agentfs-setup] Auto-detected LITE scope (target $RESOLVED_ROOT ≠ CWD $RESOLVED_CWD)"
    fi
  else
    # No ROOT_DIR, no explicit scope → default project
    SCOPE="project"
  fi
fi

# Default root based on scope
if [[ -z "$ROOT" ]]; then
  if [[ "$SCOPE" == "user" ]]; then
    ROOT="$HOME"
  else
    ROOT="."
  fi
fi

# Create ROOT_DIR if it doesn't exist
if [[ ! -d "$ROOT" ]]; then
  echo "[agentfs-setup] Creating target directory: $ROOT"
  mkdir -p "$ROOT"
fi

ROOT="$(cd "$ROOT" && pwd)"
AGENTS="$ROOT/.agents"

echo "[agentfs-setup] Scaffolding .agents/ under $ROOT (scope: $SCOPE)"

# ── Layer directories ────────────────────────────────────────────────
if [[ "$SCOPE" == "user" || "$SCOPE" == "project" ]]; then
  mkdir -p "$AGENTS/skills"
fi

if [[ "$SCOPE" == "user" ]]; then
  mkdir -p "$AGENTS/knowledge"
fi

if [[ "$SCOPE" == "project" ]]; then
  mkdir -p "$AGENTS/profiles"
fi

if [[ "$SCOPE" == "project" || "$SCOPE" == "lite" ]]; then
  mkdir -p "$AGENTS/memories"
fi

# ── index.md (entry point — NO yaml frontmatter) ────────────────────
if [[ ! -f "$AGENTS/index.md" ]]; then
  if [[ "$SCOPE" == "user" ]]; then
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
  elif [[ "$SCOPE" == "lite" ]]; then
cat > "$AGENTS/index.md" << 'EOF'
# .agents — Directory Index (Lite)

> Progressive-disclosure entry point. Browse folders before opening files.

| Layer | Path | Purpose |
|-------|------|---------|
| Identity | [SOUL.md](./SOUL.md) | Default agent identity (human-authored) |
| Memories | [memories/](./memories/MEMORY.md) | Default agent's experiences and learned context |

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

## $(date '+%Y-%m-%d %H:%M')

- Initialized .agents/ directory structure (scope: $SCOPE).
EOF
  echo "  ✓ log.md"
fi

# ── knowledge/index.md (OKF knowledge root — USER scope only) ───────
if [[ "$SCOPE" == "user" && ! -f "$AGENTS/knowledge/index.md" ]]; then
cat > "$AGENTS/knowledge/index.md" << 'EOF'
# Knowledge Index

> Semantic context layer built with the Open Knowledge Format (OKF).
> Every concept file below MUST contain a YAML frontmatter block with a
> required `type` field.

<!-- Add rows as new knowledge categories are created. -->
EOF
  echo "  ✓ knowledge/index.md"
fi

# ── skills/index.md (skill directory listing — PROJECT and USER) ─────
if [[ "$SCOPE" != "lite" && ! -f "$AGENTS/skills/index.md" ]]; then
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

# ── PROJECT/LITE scope: seed SOUL.md and memories/ ────────────────────
if [[ "$SCOPE" == "project" || "$SCOPE" == "lite" ]]; then

  # SOUL.md — default agent identity (interactive authoring via author-soul.sh)
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  AUTHOR_SOUL="$SCRIPT_DIR/author-soul.sh"
  if [[ -f "$AUTHOR_SOUL" ]]; then
    NON_INTERACTIVE_FLAG=""
    if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
      NON_INTERACTIVE_FLAG="--non-interactive"
    fi
    bash "$AUTHOR_SOUL" --path "$AGENTS/SOUL.md" $NON_INTERACTIVE_FLAG
  else
    echo "  ⚠ author-soul.sh not found at $AUTHOR_SOUL — writing minimal stub"
    cat > "$AGENTS/SOUL.md" << 'SOULEOF'
# Agent Identity

<!-- Human-authored. Define who the default agent IS — tone, style,
     communication defaults. This is the foundation of the system prompt. -->
SOULEOF
    echo "  ✓ SOUL.md (stub)"
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

# ── PROJECT scope only: seed profiles/index.md ────────────────────────
if [[ "$SCOPE" == "project" ]]; then

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

fi

# ── PROJECT scope: initialize git if not already a repo ───────────────
if [[ "$SCOPE" == "project" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [[ -f "$SCRIPT_DIR/init-git.sh" ]]; then
    bash "$SCRIPT_DIR/init-git.sh" "$ROOT"
  else
    echo "  ⚠ init-git.sh not found at $SCRIPT_DIR — skipping git init"
  fi
fi

echo "[agentfs-setup] .agents/ scaffold complete (scope: $SCOPE)."
