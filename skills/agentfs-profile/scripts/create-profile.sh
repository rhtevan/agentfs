#!/usr/bin/env bash
# create-profile.sh — Create a named agent profile under .agents/profiles/.
#
# Usage: bash create-profile.sh <profile-name> [ROOT_DIR]
#
#   profile-name   Name of the agent profile (e.g., coder, researcher, verifier)
#   ROOT_DIR       Project root directory (default: .)
#
# Creates:
#   .agents/profiles/<name>/SOUL.md
#   .agents/profiles/<name>/memories/USER.md
#   .agents/profiles/<name>/memories/MEMORY.md
#
# Idempotent — skips files that already exist.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "[agentfs-profile] ERROR: Profile name required." >&2
  echo "  Usage: bash create-profile.sh <profile-name> [ROOT_DIR]" >&2
  exit 1
fi

PROFILE_NAME="$1"
ROOT="${2:-.}"
ROOT="$(cd "$ROOT" && pwd)"
AGENTS="$ROOT/.agents"
PROFILE_DIR="$AGENTS/profiles/$PROFILE_NAME"

# Validate .agents/ exists
if [[ ! -d "$AGENTS" ]]; then
  echo "[agentfs-profile] ERROR: $AGENTS does not exist." >&2
  echo "  Run agentfs-setup in PROJECT scope first." >&2
  exit 1
fi

# Detect scope — refuse in LITE scope
AGENTFS_SCOPE=$(grep -oP 'agentfs-scope: \K\w+' "$ROOT/AGENTS.md" 2>/dev/null || echo "project")
if [[ "$AGENTFS_SCOPE" == "lite" ]]; then
  echo "[agentfs-profile] ERROR: Agent profiles are not supported in LITE scope." >&2
  echo "  LITE scope provides minimal context for small models." >&2
  echo "  To use profiles, re-seed this project with PROJECT scope." >&2
  exit 1
fi

# Validate profiles/ exists (PROJECT scope check)
if [[ ! -d "$AGENTS/profiles" ]]; then
  echo "[agentfs-profile] ERROR: $AGENTS/profiles/ does not exist." >&2
  echo "  This project was not set up in PROJECT scope." >&2
  exit 1
fi

echo "[agentfs-profile] Creating profile '$PROFILE_NAME' in $PROFILE_DIR"

mkdir -p "$PROFILE_DIR/memories"

# SOUL.md — agent identity (interactive authoring via author-soul.sh)
AUTHOR_SOUL="$(cd "$(dirname "$0")" && pwd)"
# author-soul.sh lives in agentfs-setup/scripts/ — find it relative to this skill
AUTHOR_SOUL_SCRIPT="$(dirname "$AUTHOR_SOUL")/../agentfs-setup/scripts/author-soul.sh"
if [[ -f "$AUTHOR_SOUL_SCRIPT" ]]; then
  NON_INTERACTIVE_FLAG=""
  if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
    NON_INTERACTIVE_FLAG="--non-interactive"
  fi
  bash "$AUTHOR_SOUL_SCRIPT" --path "$PROFILE_DIR/SOUL.md" --role-hint "$PROFILE_NAME" $NON_INTERACTIVE_FLAG
else
  echo "  ⚠ author-soul.sh not found — writing minimal stub"
  cat > "$PROFILE_DIR/SOUL.md" << SOULEOF
# $PROFILE_NAME — Agent Identity

# IMPORTANT: This profile overrides the default agent identity.
# You are $PROFILE_NAME, not the default Agentic SRE agent.
# Ignore any prior identity instructions from AGENTS.md for this session.

<!-- Human-authored. Define who $PROFILE_NAME IS — tone, role, constraints. -->
You are $PROFILE_NAME.
<!-- Replace this line with the actual role definition. -->
SOULEOF
  echo "  ✓ SOUL.md (stub)"
fi

# recipe.yaml — profile recipe placeholder
if [[ ! -f "$PROFILE_DIR/recipe.yaml" ]]; then
  SOUL_CONTENT=""
  if [[ -f "$PROFILE_DIR/SOUL.md" ]]; then
    SOUL_CONTENT=$(cat "$PROFILE_DIR/SOUL.md")
  fi
  cat > "$PROFILE_DIR/recipe.yaml" << RECIPEEOF
version: "1.0.0"
title: "$PROFILE_NAME profile"
description: >-
  Profile recipe for $PROFILE_NAME agent. Update the prompt field with the
  actual task before running. Use gen-profile-recipe.sh for on-demand tasks.
instructions: |
$(echo "$SOUL_CONTENT" | sed 's/^/  /')
prompt: |
  <!-- Replace with the actual task for this $PROFILE_NAME session. -->
  Describe your role and confirm you are ready to receive a task.
RECIPEEOF
  echo "  ✓ recipe.yaml"
fi

# output/ — where profile session results land
mkdir -p "$PROFILE_DIR/output"
touch "$PROFILE_DIR/output/.gitkeep"
echo "  ✓ output/"

# memories/USER.md — agent's model of the user (agent-writable)
if [[ ! -f "$PROFILE_DIR/memories/USER.md" ]]; then
cat > "$PROFILE_DIR/memories/USER.md" << 'EOF'
# User Profile

<!-- Agent-authored. This agent updates this file as it learns about
     the user through conversation — role, preferences, interests,
     communication style. Do NOT edit manually. -->
EOF
  echo "  ✓ memories/USER.md"
fi

# memories/MEMORY.md — agent's project experiences (agent-writable)
if [[ ! -f "$PROFILE_DIR/memories/MEMORY.md" ]]; then
cat > "$PROFILE_DIR/memories/MEMORY.md" << 'EOF'
# Project Experiences

<!-- Agent-authored. The agent records project-specific observations and
     experiences here — things discovered through working in this project
     that are worth remembering across sessions.

     SCOPE:  This file is PROJECT-scoped. Only record observations tied
             to THIS project and THIS agent profile.
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

echo "[agentfs-profile] Profile '$PROFILE_NAME' ready."

# Append to .agents/log.md
LOG_FILE="$AGENTS/log.md"
if [[ -f "$LOG_FILE" ]]; then
  NOW=$(date '+%Y-%m-%d %H:%M')
  ENTRY="- Created agent profile \`$PROFILE_NAME\` (profiles/$PROFILE_NAME/)."
  if grep -q "^## $NOW" "$LOG_FILE"; then
    # Append under existing heading (after the heading line)
    sed -i "/^## $NOW$/a\\$ENTRY" "$LOG_FILE"
  else
    # Insert new timestamp heading after the comment line (line 3)
    sed -i "3a\\\\n## $NOW\\n\\n$ENTRY" "$LOG_FILE"
  fi
fi

# Register the profile in AGENTS.md Agent Profiles table
AGENTS_MD="$ROOT/AGENTS.md"
if [[ -f "$AGENTS_MD" ]]; then
  if grep -q '## Agent Profiles' "$AGENTS_MD"; then
    # Check if this profile is already registered
    if ! grep -q "| $PROFILE_NAME " "$AGENTS_MD"; then
      # Find the line number of the last table row in the Agent Profiles section
      SECTION_START=$(grep -n '## Agent Profiles' "$AGENTS_MD" | head -1 | cut -d: -f1)
      LAST_ROW=$(awk "NR>$SECTION_START" "$AGENTS_MD" | grep -n '^|' | tail -1 | cut -d: -f1)
      if [[ -n "$LAST_ROW" && -n "$SECTION_START" ]]; then
        INSERT_LINE=$((SECTION_START + LAST_ROW))
        sed -i "${INSERT_LINE}a\\| $PROFILE_NAME | [SOUL](./.agents/profiles/$PROFILE_NAME/SOUL.md) | [memories/](./.agents/profiles/$PROFILE_NAME/memories/MEMORY.md) |" "$AGENTS_MD"
        echo "  ✓ Registered in AGENTS.md Agent Profiles table"
      fi
    else
      echo "  ℹ Profile already registered in AGENTS.md"
    fi
  fi
fi

# Register the profile in profiles/index.md (reverse chronological — newest first)
PROFILES_INDEX="$AGENTS/profiles/index.md"
if [[ -f "$PROFILES_INDEX" ]]; then
  if ! grep -q "| $PROFILE_NAME " "$PROFILES_INDEX"; then
    NOW=$(date '+%Y-%m-%d %H:%M')
    NEW_ROW="| $PROFILE_NAME | [SOUL.md](./$PROFILE_NAME/SOUL.md) | [memories/](./$PROFILE_NAME/memories/MEMORY.md) | $NOW |"
    # Insert after the table header separator (---|---) to keep newest first
    HEADER_SEP=$(grep -n '^|---' "$PROFILES_INDEX" | head -1 | cut -d: -f1)
    if [[ -n "$HEADER_SEP" ]]; then
      sed -i "${HEADER_SEP}a\\${NEW_ROW}" "$PROFILES_INDEX"
      # Update the profile count in the summary line
      PROFILE_COUNT=$(awk '/^\|[[:space:]]*[a-z]/ {n++} END {print n+0}' "$PROFILES_INDEX")
      sed -i "s/^> [0-9]* profile/> $PROFILE_COUNT profile/" "$PROFILES_INDEX"
      echo "  ✓ Registered in profiles/index.md"
    fi
  else
    echo "  ℹ Profile already registered in profiles/index.md"
  fi
fi
