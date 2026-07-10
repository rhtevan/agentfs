#!/usr/bin/env bash
# init-speckit.sh — Initialize Spec-kit with agent integration selection.
#
# Usage:
#   bash init-speckit.sh [--agent <name>] [--list] [ROOT_DIR]
#
#   --agent <name>   Skip interactive selection; use this agent directly.
#                    Use this when calling from an agent console (non-interactive).
#   --list           Print the numbered agent list to stdout and exit.
#                    Useful for the agent to display choices in chat.
#   ROOT_DIR         Project root directory (default: .)
#
# Interactive mode (no --agent flag):
#   Presents a numbered list of available integrations.
#   Waits 15 seconds for input; defaults to the DEFAULT_AGENT on timeout.
#
# Non-interactive mode (--agent flag):
#   Skips the menu entirely and uses the specified agent.
#   This is how an agent should call the script after presenting the
#   choices to the user in the chat and getting a response.
#
# Prerequisites: `specify` CLI must be on PATH.

set -euo pipefail

DEFAULT_AGENT="generic"
TIMEOUT=15

# ── Agent integration list ───────────────────────────────────────────
# Curated list of well-known integrations (sorted alphabetically).
# Derived from the installed specify-cli integrations directory.
AGENTS=(
  agy
  amp
  auggie
  bob
  claude
  cline
  codebuddy
  codex
  copilot
  cursor_agent
  devin
  firebender
  forge
  gemini
  generic
  goose
  hermes
  iflow
  junie
  kilocode
  kimi
  kiro_cli
  lingma
  omp
  opencode
  pi
  qodercli
  qwen
  roo
  rovodev
  shai
  tabnine
  trae
  vibe
  windsurf
  zcode
  zed
)

# ── Parse arguments ──────────────────────────────────────────────────
AGENT_FLAG=""
LIST_ONLY=false
ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      AGENT_FLAG="${2,,}"  # lowercase
      shift 2
      ;;
    --list)
      LIST_ONLY=true
      shift
      ;;
    *)
      ROOT="$1"
      shift
      ;;
  esac
done

ROOT="${ROOT:-.}"

# ── --list mode: print agent list and exit ───────────────────────────
if [[ "$LIST_ONLY" == true ]]; then
  for i in "${!AGENTS[@]}"; do
    num=$((i + 1))
    marker=""
    if [[ "${AGENTS[$i]}" == "$DEFAULT_AGENT" ]]; then
      marker=" ← default"
    fi
    printf "%2d) %s%s\n" "$num" "${AGENTS[$i]}" "$marker"
  done
  exit 0
fi

# ── Resolve ROOT ─────────────────────────────────────────────────────
ROOT="$(cd "$ROOT" && pwd)"

echo "[agentfs-setup] Spec-kit initialization in $ROOT"
echo ""

# ── Check that specify is available ──────────────────────────────────
if ! command -v specify &>/dev/null; then
  echo "  ✗ 'specify' CLI not found on PATH."
  echo "    Install it first:  uv tool install specify-cli --from git+https://github.com/github/spec-kit.git"
  echo "    Or use the 'spec-kit-setup' skill."
  exit 1
fi

# ── Determine agent integration ─────────────────────────────────────
if [[ -n "$AGENT_FLAG" ]]; then
  # ── Non-interactive mode (called by an agent) ──────────────────────
  # Validate the provided agent name against the known list
  VALID=false
  for a in "${AGENTS[@]}"; do
    if [[ "$a" == "$AGENT_FLAG" ]]; then
      VALID=true
      break
    fi
  done

  if [[ "$VALID" == true ]]; then
    AGENT="$AGENT_FLAG"
    echo "  → Agent specified via --agent flag: '$AGENT'"
  else
    echo "  ⚠ Unknown agent '$AGENT_FLAG'. Falling back to default: '$DEFAULT_AGENT'"
    AGENT="$DEFAULT_AGENT"
  fi
else
  # ── Interactive mode (real terminal) ───────────────────────────────
  echo "  Available Spec-kit agent integrations:"
  echo "  ───────────────────────────────────────"
  for i in "${!AGENTS[@]}"; do
    num=$((i + 1))
    marker=""
    if [[ "${AGENTS[$i]}" == "$DEFAULT_AGENT" ]]; then
      marker=" ← default"
    fi
    printf "  %2d) %s%s\n" "$num" "${AGENTS[$i]}" "$marker"
  done

  echo ""
  echo "  Enter the number of your agent integration (1-${#AGENTS[@]})."
  echo "  Press Enter or wait ${TIMEOUT}s to use the default: '$DEFAULT_AGENT'"
  echo ""

  SELECTED=""
  read -t "$TIMEOUT" -rp "  Selection: " SELECTED 2>/dev/null || true

  if [[ -z "$SELECTED" ]]; then
    AGENT="$DEFAULT_AGENT"
    echo ""
    echo "  → No selection made. Using default: '$AGENT'"
  elif [[ "$SELECTED" =~ ^[0-9]+$ ]] && (( SELECTED >= 1 && SELECTED <= ${#AGENTS[@]} )); then
    AGENT="${AGENTS[$((SELECTED - 1))]}"
    echo "  → Selected: '$AGENT'"
  else
    echo "  → Invalid selection '$SELECTED'. Falling back to default: '$DEFAULT_AGENT'"
    AGENT="$DEFAULT_AGENT"
  fi
fi

echo ""

# ── Run specify init ─────────────────────────────────────────────────
echo "[agentfs-setup] Running: specify init $ROOT --force --integration $AGENT"
specify init "$ROOT" --force --integration "$AGENT"

echo ""
echo "[agentfs-setup] Spec-kit initialized with '$AGENT' integration."

# Append to .agents/log.md
LOG_FILE="$ROOT/.agents/log.md"
if [[ -f "$LOG_FILE" ]]; then
  NOW=$(date '+%Y-%m-%d %H:%M')
  ENTRY="- Initialized Spec-kit with \`$AGENT\` integration."
  if grep -q "^## $NOW" "$LOG_FILE"; then
    sed -i "/^## $NOW$/a\\$ENTRY" "$LOG_FILE"
  else
    sed -i "3a\\\\n## $NOW\\n\\n$ENTRY" "$LOG_FILE"
  fi
fi
