#!/usr/bin/env bash
# verify-setup.sh — Validate (and optionally fix) the .agents/ structure.
#
# Usage: bash verify-setup.sh [--mode user|project] [--with-git] [--with-spec] [--fix] [ROOT_DIR]
#
#   --mode user   Verify USER mode structure (default root: ~)
#   --mode project  Verify PROJECT mode structure (default root: .)
#   --with-git      Also verify git was initialized by the skill
#   --with-spec     Also verify Spec-kit was initialized by the skill
#   --fix           Automatically repair missing directories and files
#                   without overwriting any existing content
#   ROOT_DIR        Override the root directory
#
# The --with-git and --with-spec flags should only be passed when those
# features were explicitly requested during setup. Without them, the
# script does NOT check for git or Spec-kit even if they exist on disk.
#
# --fix mode only creates missing directories and seed files. It NEVER
# overwrites existing files — their content is preserved as-is.
#
# Exits 0 if all checks pass (or were fixed), 1 if any remain unfixed.

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────
MODE="project"
ROOT=""
WITH_GIT=false
WITH_SPEC=false
FIX=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2,,}"  # lowercase
      shift 2
      ;;
    --with-git)
      WITH_GIT=true
      shift
      ;;
    --with-spec)
      WITH_SPEC=true
      shift
      ;;
    --fix)
      FIX=true
      shift
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

if [[ -z "$ROOT" ]]; then
  if [[ "$MODE" == "user" ]]; then
    ROOT="$HOME"
  else
    ROOT="."
  fi
fi

ROOT="$(cd "$ROOT" && pwd)"
AGENTS="$ROOT/.agents"

PASS=0
FAIL=0
FIXED=0

# check LABEL TEST_CMD [FIX_CMD]
#   If FIX_CMD is provided and --fix is active, runs it on failure
#   then re-tests. FIX_CMD must NOT overwrite existing content.
check() {
  local label="$1"
  local test_cmd="$2"
  local fix_cmd="${3:-}"

  if eval "$test_cmd" &>/dev/null; then
    echo "  [✓] $label"
    PASS=$((PASS + 1))
  elif [[ "$FIX" == true && -n "$fix_cmd" ]]; then
    eval "$fix_cmd" &>/dev/null
    if eval "$test_cmd" &>/dev/null; then
      echo "  [✓] $label  ← fixed"
      FIXED=$((FIXED + 1))
      PASS=$((PASS + 1))
    else
      echo "  [✗] $label  ← fix attempted, still failing"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  [✗] $label"
    FAIL=$((FAIL + 1))
  fi
}

# ── Seed-file helpers (used by --fix) ────────────────────────────────
# Each writes ONLY if the file does not already exist.

seed_index_user() {
  [[ -f "$AGENTS/index.md" ]] && return
  cat > "$AGENTS/index.md" << 'EOF'
# .agents — User Directory Index

> Progressive-disclosure entry point. Browse folders before opening files.
> Shared skills and knowledge visible across projects and agents.

| Layer | Path | Purpose |
|-------|------|---------|
| Capability | [skills/](skills/index.md) | Shared agent workflows (Agent Skills format) |
| Knowledge | [knowledge/](knowledge/index.md) | Shared knowledge base (OKF format) |

See [log.md](log.md) for recent activity.
EOF
}

seed_index_project() {
  [[ -f "$AGENTS/index.md" ]] && return
  cat > "$AGENTS/index.md" << 'EOF'
# .agents — Directory Index

> Progressive-disclosure entry point. Browse folders before opening files.

| Layer | Path | Purpose |
|-------|------|---------|
| Identity | [SOUL.md](SOUL.md) | Default agent identity (human-authored) |
| Profiles | [profiles/](profiles/index.md) | Named agent profiles with individual SOUL & memories |
| Capability | [skills/](skills/index.md) | Project-scoped agent workflows (Agent Skills format) |
| Memories | [memories/](memories/MEMORY.md) | Default agent's experiences and learned context |

See [log.md](log.md) for recent activity.
EOF
}

seed_log() {
  [[ -f "$AGENTS/log.md" ]] && return
  cat > "$AGENTS/log.md" << EOF
# Directory Update Log

<!-- Append-only. Newest entries at top. -->

## $(date '+%Y-%m-%d %H:%M')

- Repaired .agents/ directory structure (mode: $MODE, via --fix).
EOF
}

seed_knowledge_index() {
  [[ -f "$AGENTS/knowledge/index.md" ]] && return
  cat > "$AGENTS/knowledge/index.md" << 'EOF'
# Knowledge Index

> Semantic context layer built with the Open Knowledge Format (OKF).
> Every concept file below MUST contain a YAML frontmatter block with a
> required `type` field.

<!-- Add rows as new knowledge categories are created. -->
EOF
}

seed_skills_index() {
  [[ -f "$AGENTS/skills/index.md" ]] && return
  cat > "$AGENTS/skills/index.md" << 'EOF'
# Skills Index

> 0 skills | Sorted by reverse chronological order (newest first).

| Skill | Description | Updated |
|-------|-------------|---------|

<!-- Rows are added when skills are created. Sorted newest-first by the
     Updated timestamp. Use the skill-index skill to regenerate this file
     automatically. -->
EOF
}

seed_profiles_index() {
  [[ -f "$AGENTS/profiles/index.md" ]] && return
  mkdir -p "$AGENTS/profiles"
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
}

seed_soul() {
  [[ -f "$AGENTS/SOUL.md" ]] && return
  cat > "$AGENTS/SOUL.md" << 'EOF'
# Agent Identity

<!-- Human-authored. Define who the default agent IS — tone, style,
     communication defaults. This is the foundation of the system prompt. -->
EOF
}

seed_user_md() {
  local dir="$1"
  [[ -f "$dir/USER.md" ]] && return
  cat > "$dir/USER.md" << 'EOF'
# User Profile

<!-- Agent-authored. The agent updates this file as it learns about the user
     through conversation — role, preferences, interests, communication style.
     Do NOT edit manually; let the agent manage this file. -->
EOF
}

seed_memory_md() {
  local dir="$1"
  [[ -f "$dir/MEMORY.md" ]] && return
  cat > "$dir/MEMORY.md" << 'EOF'
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
}

# ── Header ───────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
echo "  DotAgents Setup Verification (mode: $MODE)"
echo "  Root: $ROOT"
local_flags=""
if [[ "$MODE" == "project" ]]; then
  [[ "$WITH_GIT" == true ]] && local_flags+=" +git"
  [[ "$WITH_SPEC" == true ]] && local_flags+=" +spec"
fi
[[ "$FIX" == true ]] && local_flags+=" +fix"
[[ -n "$local_flags" ]] && echo "  Options:$local_flags"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Common checks (both modes) ──────────────────────────────────────
echo "── .agents/ Core Structure ──────────────────────────────"
check ".agents/ directory exists" \
  "[[ -d '$AGENTS' ]]" \
  "mkdir -p '$AGENTS'"

if [[ "$MODE" == "user" ]]; then
  check ".agents/index.md exists" \
    "[[ -f '$AGENTS/index.md' ]]" \
    "seed_index_user"
else
  check ".agents/index.md exists" \
    "[[ -f '$AGENTS/index.md' ]]" \
    "seed_index_project"
fi

check ".agents/log.md exists" \
  "[[ -f '$AGENTS/log.md' ]]" \
  "seed_log"

check ".agents/skills/ directory exists" \
  "[[ -d '$AGENTS/skills' ]]" \
  "mkdir -p '$AGENTS/skills'"

check ".agents/skills/index.md exists" \
  "[[ -f '$AGENTS/skills/index.md' ]]" \
  "seed_skills_index"

if [[ "$MODE" == "user" ]]; then
  # ── USER mode: knowledge is USER-scoped ────────────────────────
  check ".agents/knowledge/ directory exists" \
    "[[ -d '$AGENTS/knowledge' ]]" \
    "mkdir -p '$AGENTS/knowledge'"

  check ".agents/knowledge/index.md exists" \
    "[[ -f '$AGENTS/knowledge/index.md' ]]" \
    "seed_knowledge_index"
  echo ""

  # ── USER mode: verify excluded dirs are absent ─────────────────
  echo "── USER Mode Exclusions ─────────────────────────────"
  check "No .agents/profiles/ (project-scoped)" "[[ ! -d '$AGENTS/profiles' ]]"
  check "No .agents/memories/ (project-scoped)" "[[ ! -d '$AGENTS/memories' ]]"
  check "No .agents/SOUL.md (project-scoped)" "[[ ! -f '$AGENTS/SOUL.md' ]]"
  check "No AGENTS.md at root (project-scoped)" "[[ ! -f '$ROOT/AGENTS.md' ]]"
  echo ""

else
  # ── PROJECT mode checks ──────────────────────────────────────────
  echo "── PROJECT Mode Structure ─────────────────────────────"
  check "AGENTS.md exists" \
    "[[ -f '$ROOT/AGENTS.md' ]]"
    # AGENTS.md is complex — do not auto-seed in fix mode; agent should
    # run seed-agents-md.sh explicitly if missing.

  check "AGENTS.md has SPECKIT markers" \
    "grep -q 'SPECKIT START' '$ROOT/AGENTS.md'" \
    "printf '\n<!-- SPECKIT START -->\n<!-- SPECKIT END -->\n' >> '$ROOT/AGENTS.md'"

  check ".agents/SOUL.md exists" \
    "[[ -f '$AGENTS/SOUL.md' ]]" \
    "seed_soul"

  check ".agents/profiles/ directory exists" \
    "[[ -d '$AGENTS/profiles' ]]" \
    "mkdir -p '$AGENTS/profiles'"

  check ".agents/profiles/index.md exists" \
    "[[ -f '$AGENTS/profiles/index.md' ]]" \
    "seed_profiles_index"

  check ".agents/memories/ directory exists" \
    "[[ -d '$AGENTS/memories' ]]" \
    "mkdir -p '$AGENTS/memories'"

  check ".agents/memories/USER.md exists" \
    "[[ -f '$AGENTS/memories/USER.md' ]]" \
    "seed_user_md '$AGENTS/memories'"

  check ".agents/memories/MEMORY.md exists" \
    "[[ -f '$AGENTS/memories/MEMORY.md' ]]" \
    "seed_memory_md '$AGENTS/memories'"
  echo ""

  # ── Link integrity checks ─────────────────────────────────────────
  echo "── Link Integrity ─────────────────────────────────────"
  # Check that index.md links resolve
  if [[ -f "$AGENTS/index.md" ]]; then
    # Extract markdown link targets from index.md
    while IFS= read -r link_target; do
      resolved="$AGENTS/$link_target"
      check "index.md → $link_target" "[[ -e '$resolved' ]]"
    done < <(grep -oP '\]\(\K[^)]+' "$AGENTS/index.md" | grep -v '^http')
  fi
  echo ""

  # knowledge/ is USER-scoped only — should NOT exist in PROJECT mode
  check "No .agents/knowledge/ (USER-scoped only)" "[[ ! -d '$AGENTS/knowledge' ]]"
  echo ""

  # Verify no stale agent-specific context files at root
  echo "── Stale File Checks ──────────────────────────────────"
  check "No CLAUDE.md at root (should be AGENTS.md)" "[[ ! -f '$ROOT/CLAUDE.md' ]]"
  check "No COPILOT.md at root" "[[ ! -f '$ROOT/COPILOT.md' ]]"
  check "No GEMINI.md at root" "[[ ! -f '$ROOT/GEMINI.md' ]]"
  echo ""

  # ── Git check (only when --with-git was passed) ──────────────────
  if [[ "$WITH_GIT" == true ]]; then
    echo "── Git (requested via --with-git) ────────────────────"
    check "Git repository initialized" "git -C '$ROOT' rev-parse --is-inside-work-tree"
    check ".gitignore exists" "[[ -f '$ROOT/.gitignore' ]]"
    check ".gitignore excludes .agents/memories/" "grep -q '.agents/memories' '$ROOT/.gitignore'"
    echo ""
  fi

  # ── Spec-kit check (only when --with-spec was passed) ────────────
  if [[ "$WITH_SPEC" == true ]]; then
    echo "── Spec-kit (requested via --with-spec) ─────────────"
    check ".specify/ directory exists" "[[ -d '$ROOT/.specify' ]]"
    check "specs/ directory exists" "[[ -d '$ROOT/specs' ]]"
    echo ""
  fi

  # ── Profile integrity (check any existing profiles) ──────────────
  if [[ -d "$AGENTS/profiles" ]] && ls -d "$AGENTS/profiles"/*/ &>/dev/null; then
    echo "── Profile Integrity ────────────────────────────────"
    for profile_dir in "$AGENTS/profiles"/*/; do
      pname="$(basename "$profile_dir")"
      check "profiles/$pname/SOUL.md exists" \
        "[[ -f '$profile_dir/SOUL.md' ]]" \
        "mkdir -p '$profile_dir/memories' && cat > '$profile_dir/SOUL.md' << EOSOUL
# $pname — Agent Identity

<!-- Human-authored. Define who this agent IS. -->
EOSOUL"

      check "profiles/$pname/memories/ exists" \
        "[[ -d '$profile_dir/memories' ]]" \
        "mkdir -p '$profile_dir/memories'"

      check "profiles/$pname/memories/USER.md exists" \
        "[[ -f '$profile_dir/memories/USER.md' ]]" \
        "seed_user_md '$profile_dir/memories'"

      check "profiles/$pname/memories/MEMORY.md exists" \
        "[[ -f '$profile_dir/memories/MEMORY.md' ]]" \
        "seed_memory_md '$profile_dir/memories'"
    done
    echo ""
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════"
if [[ "$FIXED" -gt 0 ]]; then
  echo "  Results: $PASS passed ($FIXED fixed), $FAIL failed"
else
  echo "  Results: $PASS passed, $FAIL failed"
fi
echo "═══════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
  echo ""
  echo "  Some checks failed. Review the [✗] items above."
  exit 1
else
  echo ""
  echo "  All checks passed."
  exit 0
fi
