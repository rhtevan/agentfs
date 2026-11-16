#!/usr/bin/env bash
# rules-hash.sh — Content hash of the behavioural rules in an AGENTS.md.
#
# Usage:
#   bash rules-hash.sh [AGENTS_MD]        Print the hash
#   bash rules-hash.sh --show [AGENTS_MD] Print the canonicalised text
#
#   AGENTS_MD defaults to the git-root AGENTS.md, then
#   ~/.config/goose/prompts/system.md.
#
# Why this exists
# ---------------
# The compliance profile records how well a model obeys the AGENTS.md
# rules. Whether it is stale depends on whether those RULES changed —
# not on whether a version string moved.
#
# The template version is derived from agentfs-setup's frontmatter
# (seed-agents-md.sh), so bumping that skill for ANY reason — a fix to
# a script that has no presence in AGENTS.md at all — bumps the
# template version and makes a version-string check report a stale
# profile. That is a false positive, and acting on it costs a full
# benchmark run to re-measure rules that did not change.
#
# What is hashed
# --------------
# Only template-owned behavioural sections: '## Rules' and
# '## Signal Dispatch'. Deliberately excluded:
#
#   - the version stamp on line 1          (the thing we must not key on)
#   - '## Quick Orientation', '## Scope Definitions'  (reference tables,
#     not behavioural instructions — they do not change what a model is
#     asked to DO)
#   - everything after the PROJECT-OWNED marker (per-project content;
#     two projects with identical rules must hash the same)
#
# Canonicalisation: trailing whitespace stripped, blank lines dropped.
# Reflowing a paragraph changes the hash — that is intended, since
# rule WORDING is exactly what compliance measures.
#
# Exit codes:
#   0 = hash printed
#   1 = file not found, or no rules sections present

set -euo pipefail

SHOW=false
if [[ "${1:-}" == "--show" ]]; then SHOW=true; shift; fi

AGENTS_MD="${1:-}"
if [[ -z "$AGENTS_MD" ]]; then
  _root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$_root" && -f "$_root/AGENTS.md" ]]; then
    AGENTS_MD="$_root/AGENTS.md"
  else
    AGENTS_MD="${HOME}/.config/goose/prompts/system.md"
  fi
fi

if [[ ! -f "$AGENTS_MD" ]]; then
  echo "❌ Not found: $AGENTS_MD" >&2
  exit 1
fi

# Extract the behavioural sections, stopping at the PROJECT-OWNED marker.
CANON=$(awk '
  /^<!-- PROJECT-OWNED/ { exit }
  /^## / {
    want = ($0 == "## Rules" || $0 == "## Signal Dispatch")
  }
  want { print }
' "$AGENTS_MD" | sed 's/[[:space:]]*$//' | grep -v '^$' || true)

if [[ -z "$CANON" ]]; then
  echo "❌ No '## Rules' or '## Signal Dispatch' section in $AGENTS_MD" >&2
  exit 1
fi

if $SHOW; then
  printf '%s\n' "$CANON"
  exit 0
fi

printf '%s\n' "$CANON" | sha256sum | cut -c1-16
