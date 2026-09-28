#!/usr/bin/env bash
# author-soul.sh — Interactive SOUL.md authoring helper.
#
# Usage:
#   bash author-soul.sh --path <target-soul.md> [OPTIONS]
#
# Options:
#   --path <file>          Target SOUL.md path (required)
#   --role-hint <name>     Profile name hint for role-tuned draft (optional)
#   --non-interactive      Write default stub without prompting (for CI/scripts)
#
# Exit codes:
#   0 = file written or kept unchanged
#   1 = user cancelled
#
# Called by:
#   scaffold-dotagents.sh  (default agent SOUL)
#   create-profile.sh      (named profile SOUL)

set -euo pipefail

# ── Parse arguments ──────────────────────────────────────────────────
TARGET_PATH=""
ROLE_HINT=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)
      TARGET_PATH="$2"
      shift 2
      ;;
    --role-hint)
      ROLE_HINT="$2"
      shift 2
      ;;
    --non-interactive)
      NON_INTERACTIVE=true
      shift
      ;;
    *)
      echo "[author-soul] ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_PATH" ]]; then
  echo "[author-soul] ERROR: --path is required." >&2
  exit 1
fi

# ── Helpers ──────────────────────────────────────────────────────────
is_stub() {
  local file="$1"
  # A file is a stub if it exists but contains only comments/whitespace
  # (no non-comment, non-empty lines outside the heading).
  # Uses awk-based multi-line comment stripping so content inside <!-- -->
  # blocks (e.g. examples) is correctly excluded from the line count.
  local non_comment_lines
  non_comment_lines=$(awk '
    /<!--/ { in_comment=1 }
    /-->/ { in_comment=0; next }
    in_comment { next }
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    { print }
  ' "$file" | wc -l)
  [[ "$non_comment_lines" -eq 0 ]]
}

prompt_user() {
  local question="$1"
  local default="$2"
  local answer
  echo ""
  echo "  $question"
  if [[ -n "$default" ]]; then
    echo "  [default: $default — press Enter to accept]"
  fi
  echo -n "  > "
  read -r answer
  if [[ -z "$answer" ]]; then
    echo "$default"
  else
    echo "$answer"
  fi
}

# ── Default Agentic SRE SOUL content (v6 format) ─────────────────────
default_soul_content() {
  # Generate via seed-soul.sh for single source of truth
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local seed_soul="$script_dir/seed-soul.sh"
  local tmpfile
  tmpfile=$(mktemp)
  if [[ -f "$seed_soul" ]]; then
    bash "$seed_soul" "$tmpfile" >/dev/null 2>&1
    cat "$tmpfile"
    rm -f "$tmpfile"
  else
    rm -f "$tmpfile"
    # Fallback if seed-soul.sh not found
    cat << 'EOF'
# Agent Identity

You are an Agentic SRE — a pragmatic systems reliability engineer
operating autonomously within CI/CD and operational contexts.

## Principles

- **Reliability over cleverness.** Prefer simple, proven solutions.
- **Root cause, not symptom.** Ad-hoc fixes are temporary — trace to
  root cause, implement durable fix (script, guardrail, or config change).
- **Direct communication.** No filler, no hedging. Never open with
  validation phrases ("Great question", "Absolutely", "Of course").
  Lead with substance.
- **Intellectual integrity.** Do not reverse a stated position unless
  given new information or a logical argument. Social pressure is not
  a reason to reverse course.
- **No assumed inputs.** When information is missing, ask before
  proceeding. A confident wrong answer is worse than a clarifying
  question. When uncertain, say so.
- **Proactive risk naming.** Name risks and failure modes even when
  not asked. Push back on bad plans.
- **Scope discipline.** Defer on aesthetic and domain-specific choices
  outside your operational scope.
- **Ledger integrity.** Ledger files (log.md, CHANGELOG.md, MEMORY.md,
  score sheets) are always latest-entry-first. Flag ordering violations,
  duplicate headers, or structural anomalies immediately.
- **Signal dispatch.** When a user message starts with "hey" followed
  by keywords, treat it as a skill/knowledge dispatch command — never
  as a greeting. Always follow the dispatch rule in AGENTS.md.

<!-- PROJECT-OWNED: custom identity below is preserved across sync -->
EOF
  fi
}

# ── Profile role-tuned stub ───────────────────────────────────────────
profile_soul_stub() {
  local name="$1"
cat << EOF
# ${name} — Agent Identity

# IMPORTANT: This profile overrides the default agent identity.
# You are ${name}, not the default Agentic SRE agent.
# Ignore any prior identity instructions from AGENTS.md for this session.

<!-- Define who ${name} IS. Write in second person ("You are...").
     Be specific — vague instructions produce vague behavior.

     Dimensions to define:
     ROLE        What ${name} does and why it exists.
     TONE        How it communicates — direct, skeptical, formal, terse?
     PUSH BACK   What it challenges or refuses.
     DEFER       What it defers on.
     CONSTRAINTS What it must never do.

     Common profile patterns:
       verifier   → skeptical, finds gaps, never validates without evidence
       watchdog   → monitors guardrail violations, reports without fixing
       critic     → adversarial reviewer, steelmans then attacks
       researcher → broad synthesis, surfaces trade-offs, flags unknowns
-->

You are ${name}.
<!-- Replace this line with the actual role definition. -->
EOF
}

# ── Main logic ───────────────────────────────────────────────────────
mkdir -p "$(dirname "$TARGET_PATH")"

# Case 1: File exists and is NOT a stub — offer keep/edit/replace
if [[ -f "$TARGET_PATH" ]] && ! is_stub "$TARGET_PATH"; then
  if [[ "$NON_INTERACTIVE" == true ]]; then
    echo "[author-soul] SOUL.md already exists and is non-stub — keeping as-is."
    exit 0
  fi
  echo ""
  echo "[author-soul] Existing SOUL.md found at: $TARGET_PATH"
  echo "  Current content:"
  echo "  ─────────────────────────────────────────"
  cat "$TARGET_PATH" | sed 's/^/  /'
  echo "  ─────────────────────────────────────────"
  echo ""
  echo "  What would you like to do?"
  echo "    [k] Keep as-is (default)"
  echo "    [r] Replace with a new draft"
  echo -n "  > "
  read -r choice
  choice=$(echo "${choice:-k}" | tr '[:upper:]' '[:lower:]')
  if [[ "$choice" != "r" ]]; then
    echo "[author-soul] Keeping existing SOUL.md."
    exit 0
  fi
fi

# Case 2: Non-interactive — write default stub or profile stub
if [[ "$NON_INTERACTIVE" == true ]]; then
  if [[ -z "$ROLE_HINT" ]]; then
    default_soul_content "Agent Identity" > "$TARGET_PATH"
    echo "[author-soul] ✓ Default Agentic SRE SOUL.md written (non-interactive)."
  else
    profile_soul_stub "$ROLE_HINT" > "$TARGET_PATH"
    echo "[author-soul] ✓ Profile SOUL.md stub written for '$ROLE_HINT' (non-interactive)."
  fi
  exit 0
fi

# Case 3: Interactive authoring
echo ""
echo "═══════════════════════════════════════════════"
if [[ -z "$ROLE_HINT" ]]; then
  echo " Authoring: Default Agent Identity (SOUL.md)"
else
  echo " Authoring: $ROLE_HINT — Agent Identity (SOUL.md)"
fi
echo "═══════════════════════════════════════════════"

# Show the starting draft
if [[ -z "$ROLE_HINT" ]]; then
  DRAFT=$(default_soul_content "Agent Identity")
else
  DRAFT=$(profile_soul_stub "$ROLE_HINT")
fi

echo ""
echo " Starting draft:"
echo " ─────────────────────────────────────────"
echo "$DRAFT" | sed 's/^/ /'
echo " ─────────────────────────────────────────"

# Ask the 3 targeted questions
if [[ -z "$ROLE_HINT" ]]; then
  # Default agent questions
  PUSHBACK=$(prompt_user \
    "What does this agent push back on? (bad plans, unverified reversals, scope creep...)" \
    "Bad plans, requests to change position without new evidence, guardrail violations")

  DEFER=$(prompt_user \
    "What does this agent defer on? (aesthetic choices, out-of-scope domains...)" \
    "Aesthetic choices, user preferences, domain-specific decisions outside operational scope")

  CONSTRAINTS=$(prompt_user \
    "Any hard constraints? (things it must never do — press Enter to skip)" \
    "")
else
  # Profile agent questions
  PUSHBACK=$(prompt_user \
    "What does $ROLE_HINT push back on or refuse?" \
    "Unverified claims, incomplete evidence, requests outside its defined role")

  DEFER=$(prompt_user \
    "What does $ROLE_HINT defer on?" \
    "Implementation decisions, aesthetic choices, out-of-scope requests")

  CONSTRAINTS=$(prompt_user \
    "Any hard constraints for $ROLE_HINT? (press Enter to skip)" \
    "")
fi

# Assemble final SOUL.md
# Template section (Principles) comes from seed-soul.sh
# Custom answers go in the project-owned section

if [[ -z "$ROLE_HINT" ]]; then
  # Default agent: use template + custom project section
  TEMPLATE_SECTION=$(default_soul_content)

  PROJECT_SECTION="You push back on: ${PUSHBACK}.
You defer on: ${DEFER}."

  if [[ -n "$CONSTRAINTS" ]]; then
    PROJECT_SECTION+="
Constraints: ${CONSTRAINTS}."
  fi

  # Template already includes the PROJECT-OWNED marker.
  # Append custom content after it.
  FINAL_SOUL="${TEMPLATE_SECTION}

${PROJECT_SECTION}"

else
  # Profile agent: no template Principles, fully custom
  FINAL_SOUL="# ${ROLE_HINT} — Agent Identity

# IMPORTANT: This profile overrides the default agent identity.
# You are ${ROLE_HINT}, not the default Agentic SRE agent.
# Ignore any prior identity instructions from AGENTS.md for this session.

You are ${ROLE_HINT}.

You push back on: ${PUSHBACK}.
You defer on: ${DEFER}."

  if [[ -n "$CONSTRAINTS" ]]; then
    FINAL_SOUL+="
Constraints: ${CONSTRAINTS}."
  fi

  FINAL_SOUL+="
Never open a response with validation phrases such as \"Great question\",
\"Absolutely\", \"Of course\", or \"That's a great idea\". Lead with substance.
You never act on assumed inputs. When information required to complete
a task is missing, you ask for it before proceeding."
fi

# Show assembled result and confirm
echo ""
echo " Assembled SOUL.md:"
echo " ─────────────────────────────────────────"
echo "$FINAL_SOUL" | sed 's/^/ /'
echo " ─────────────────────────────────────────"
echo ""
echo -n " Write this to $TARGET_PATH? [Y/n] "
read -r confirm
confirm=$(echo "${confirm:-y}" | tr '[:upper:]' '[:lower:]')

if [[ "$confirm" != "y" && "$confirm" != "yes" ]]; then
  echo "[author-soul] Cancelled — SOUL.md not written."
  exit 1
fi

echo "$FINAL_SOUL" > "$TARGET_PATH"
echo "[author-soul] ✓ SOUL.md written to: $TARGET_PATH"
