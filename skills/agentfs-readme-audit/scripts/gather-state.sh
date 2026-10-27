#!/bin/bash
# gather-state.sh — Deterministic state gathering for README audit
#
# Resolves scope, collects filesystem ground truth, reads README,
# and outputs explicit fact statements. Replaces Steps 0-2 of the
# original prose-only SKILL.md.
#
# Usage:
#   gather-state.sh [--scope user|project] [--repo-root <path>]
#
# If --scope is omitted, auto-detects from git repo root.
# If --repo-root is provided, uses that instead of CWD for detection.
#
# Output (stdout):
#   Structured sections with explicit facts. Designed for both
#   LLM consumption (agent reads and compares) and SDM evidence.
#
# Exit codes:
#   0 — Facts gathered successfully
#   1 — No README found (PROJECT scope — not an error, skip audit)
#   2 — Not in a git repository
#
# Trace integration:
#   Sources trace-lib.sh if AGENTFS_TRACE is set.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TRACE_LIB="${HOME}/.agents/scripts/trace-lib.sh"

# --- Trace setup (optional) ---
_trace=false
if [[ -n "${AGENTFS_TRACE:-}" ]] && [[ -f "$TRACE_LIB" ]]; then
  source "$TRACE_LIB"
  _trace=true
fi

trace() {
  if [[ "$_trace" == "true" ]]; then
    trace_step "$@"
  fi
}

die() { echo "ERROR: $*" >&2; exit 2; }

# --- Parse arguments ---
SCOPE=""
REPO_ROOT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)  SCOPE="$2"; shift 2 ;;
    --repo-root) REPO_ROOT_ARG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: gather-state.sh [--scope user|project] [--repo-root <path>]"
      exit 0
      ;;
    *) die "Unknown option: $1" ;;
  esac
done

# =========================================================
# Step 0 — Resolve Scope
# =========================================================

DETECT_DIR="${REPO_ROOT_ARG:-$(pwd)}"

if [[ -z "$SCOPE" ]]; then
  # Auto-detect from git repo root
  REPO_ROOT=$(cd "$DETECT_DIR" && git rev-parse --show-toplevel 2>/dev/null) || \
    die "Not in a git repository: $DETECT_DIR"

  AGENTS_HOME=$(cd ~ && pwd)
  if [[ "$REPO_ROOT" == "${AGENTS_HOME}/.agents" ]]; then
    SCOPE="user"
  else
    SCOPE="project"
  fi
fi

# Set paths based on scope
case "$SCOPE" in
  user)
    AGENTS_ROOT="${HOME}/.agents"
    README_PATH="${AGENTS_ROOT}/README.md"
    ;;
  project)
    REPO_ROOT="${REPO_ROOT_ARG:-$(cd "$DETECT_DIR" && git rev-parse --show-toplevel 2>/dev/null)}" || \
      die "Not in a git repository: $DETECT_DIR"
    AGENTS_ROOT="${REPO_ROOT}/.agents"
    # README resolution order
    if [[ -f "${AGENTS_ROOT}/README.md" ]]; then
      README_PATH="${AGENTS_ROOT}/README.md"
    elif [[ -f "${REPO_ROOT}/README.md" ]]; then
      README_PATH="${REPO_ROOT}/README.md"
    else
      echo "=== SCOPE ==="
      echo "Scope: PROJECT"
      echo "Repo root: $REPO_ROOT"
      echo "Result: NO README FOUND — skip audit"
      exit 1
    fi
    ;;
  *)
    die "Invalid scope: $SCOPE (expected user or project)"
    ;;
esac

trace 0 "resolve_scope" 0 "scope=$SCOPE"

# =========================================================
# Step 1 — Gather Filesystem State
# =========================================================

echo "=== SCOPE ==="
echo "Scope: $(echo "$SCOPE" | tr '[:lower:]' '[:upper:]')"
echo "Agents root: $AGENTS_ROOT"
echo "README path: $README_PATH"

if [[ "$SCOPE" == "user" ]]; then
  # --- Skill count and list ---
  SKILL_LIST=$(ls -d "${AGENTS_ROOT}"/skills/*/SKILL.md 2>/dev/null \
    | sed 's|.*/skills/||;s|/SKILL.md||' | sort || true)
  SKILL_COUNT=$(echo "$SKILL_LIST" | grep -c '.' 2>/dev/null || echo 0)

  trace 1 "gather_skill_count" 0 "count=$SKILL_COUNT"

  # --- Knowledge bundle count and list ---
  KNOWLEDGE_LIST=$(ls -d "${AGENTS_ROOT}"/knowledge/*/index.md 2>/dev/null \
    | sed 's|.*/knowledge/||;s|/index.md||' | sort || true)
  KNOWLEDGE_COUNT=$(echo "$KNOWLEDGE_LIST" | grep -c '.' 2>/dev/null || echo 0)

  trace 2 "gather_knowledge_count" 0 "count=$KNOWLEDGE_COUNT"

  # --- Guardrail list from seed template ---
  GUARDRAILS=""
  GUARDRAIL_COUNT=0
  if [[ -f "${AGENTS_ROOT}/skills/agentfs-setup/scripts/seed-agents-md.sh" ]]; then
    GUARDRAILS=$(grep -oP '### [0-9]+\. .+' \
      "${AGENTS_ROOT}/skills/agentfs-setup/scripts/seed-agents-md.sh" 2>/dev/null || true)
    if [[ -n "$GUARDRAILS" ]]; then
      GUARDRAIL_COUNT=$(echo "$GUARDRAILS" | wc -l)
    fi
  fi

  trace 3 "gather_guardrails" 0 "count=$GUARDRAIL_COUNT"

  # --- Template version ---
  TEMPLATE_VERSION="unknown"
  _ver=$(grep -oP 'version:\s*"\K[^"]+' \
    "${AGENTS_ROOT}/skills/agentfs-setup/SKILL.md" 2>/dev/null || true)
  if [[ -n "$_ver" ]]; then
    TEMPLATE_VERSION=$(echo "$_ver" | head -1)
  fi

  trace 4 "gather_template_version" 0 "version=$TEMPLATE_VERSION"

  # --- Directory structure ---
  DIR_TREE=$(tree -L 1 --dirsfirst -I '__pycache__|node_modules|.git' \
    "$AGENTS_ROOT/" 2>/dev/null || ls -d "$AGENTS_ROOT"/*/ 2>/dev/null || echo "unavailable")

  trace 5 "gather_directory_tree" 0 "done"

  # --- Skill categories (from index.md) ---
  SKILL_CATEGORIES=""
  if [[ -f "${AGENTS_ROOT}/skills/index.md" ]]; then
    SKILL_CATEGORIES=$(grep '^|' "${AGENTS_ROOT}/skills/index.md" \
      | grep -v '^| Name\|^| Skill\|^|---\|^| -' 2>/dev/null \
      | head -20 || true)
  fi

  # --- Output USER facts ---
  echo ""
  echo "=== FILESYSTEM STATE ==="
  echo "Skill count: $SKILL_COUNT"
  echo "Knowledge bundle count: $KNOWLEDGE_COUNT"
  echo "Guardrail count: $GUARDRAIL_COUNT"
  echo "Template version: $TEMPLATE_VERSION"
  echo ""
  echo "Skill list:"
  echo "$SKILL_LIST" | head -70
  echo ""
  echo "Knowledge bundle list:"
  echo "$KNOWLEDGE_LIST"
  echo ""
  if [[ -n "$GUARDRAILS" ]]; then
    echo "Guardrails:"
    echo "$GUARDRAILS"
    echo ""
  fi
  echo "Top-level directory structure:"
  echo "$DIR_TREE"
  echo ""
  if [[ -n "$SKILL_CATEGORIES" ]]; then
    echo "Skill categories (first 20 from index.md):"
    echo "$SKILL_CATEGORIES"
    echo ""
  fi

elif [[ "$SCOPE" == "project" ]]; then
  # --- Project skill count ---
  SKILL_LIST=$(ls -d "${AGENTS_ROOT}"/skills/*/SKILL.md 2>/dev/null \
    | sed 's|.*/skills/||;s|/SKILL.md||' | sort || true)
  SKILL_COUNT=0
  if [[ -n "$SKILL_LIST" ]]; then
    SKILL_COUNT=$(echo "$SKILL_LIST" | wc -l)
  fi

  trace 1 "gather_skill_count" 0 "count=$SKILL_COUNT"

  # --- Profile count ---
  PROFILE_LIST=$(ls -d "${AGENTS_ROOT}"/profiles/*/ 2>/dev/null \
    | sed 's|.*/profiles/||;s|/$||' | sort || true)
  PROFILE_COUNT=0
  if [[ -n "$PROFILE_LIST" ]]; then
    PROFILE_COUNT=$(echo "$PROFILE_LIST" | wc -l)
  fi

  trace 2 "gather_profile_count" 0 "count=$PROFILE_COUNT"

  # --- SOUL.md identity ---
  SOUL_SUMMARY=""
  if [[ -f "${AGENTS_ROOT}/SOUL.md" ]]; then
    SOUL_SUMMARY=$(head -10 "${AGENTS_ROOT}/SOUL.md")
  fi

  # --- AGENTS.md summary ---
  AGENTSMD_SUMMARY=""
  if [[ -f "${REPO_ROOT}/AGENTS.md" ]]; then
    AGENTSMD_SUMMARY=$(head -50 "${REPO_ROOT}/AGENTS.md")
  fi

  trace 3 "gather_project_identity" 0 "soul=$(test -n "$SOUL_SUMMARY" && echo yes || echo no)"

  # --- Directory structure ---
  DIR_TREE=$(tree -L 2 --dirsfirst -I '__pycache__|node_modules|.git' \
    "$AGENTS_ROOT/" 2>/dev/null || ls -la "$AGENTS_ROOT"/ 2>/dev/null || echo "unavailable")

  trace 4 "gather_directory_tree" 0 "done"

  # --- Output PROJECT facts ---
  echo ""
  echo "=== FILESYSTEM STATE ==="
  echo "Project skill count: $SKILL_COUNT"
  echo "Profile count: $PROFILE_COUNT"
  echo ""
  if [[ -n "$SKILL_LIST" ]] && [[ "$SKILL_COUNT" -gt 0 ]]; then
    echo "Project skill list:"
    echo "$SKILL_LIST"
    echo ""
  fi
  if [[ -n "$PROFILE_LIST" ]] && [[ "$PROFILE_COUNT" -gt 0 ]]; then
    echo "Profile list:"
    echo "$PROFILE_LIST"
    echo ""
  fi
  if [[ -n "$SOUL_SUMMARY" ]]; then
    echo "SOUL.md (first 10 lines):"
    echo "$SOUL_SUMMARY"
    echo ""
  fi
  echo "Directory structure:"
  echo "$DIR_TREE"
  echo ""
  if [[ -n "$AGENTSMD_SUMMARY" ]]; then
    echo "AGENTS.md (first 50 lines):"
    echo "$AGENTSMD_SUMMARY"
    echo ""
  fi
fi

# =========================================================
# Step 2 — Read README
# =========================================================

trace 6 "read_readme" 0 "path=$README_PATH"

README_LINES=$(wc -l < "$README_PATH")

echo "=== README CONTENT ==="
echo "README path: $README_PATH"
echo "README lines: $README_LINES"
echo ""
cat "$README_PATH"
