#!/usr/bin/env bash
# sync-readme-version.sh — Keep the USER README's version references in
# step with the agentfs-setup template version.
#
# Usage:
#   bash sync-readme-version.sh [--dry-run] [README]
#
#   README defaults to ~/.agents/README.md.
#
# Why this exists
# ---------------
# The template version is derived from agentfs-setup's frontmatter, so
# every bump of that skill — for any reason — leaves the README
# claiming an older version. This drifted three releases in a row
# (7.8.0, 7.9.0, 7.9.1). The README audit's D6 dimension caught it each
# time, but only because someone ran the audit and read the result.
# A public repo stating the wrong version is a correctness problem, so
# it needs a mechanism rather than attention.
#
# Two patterns are updated, matching exactly what D6 inspects:
#   1. "AgentFS vX.Y.Z enforces ..."        — prose reference
#   2. "<!-- agentfs-template-version: X.Y.Z -->"  — example stamp
#
# Anything else mentioning a version is left alone: changelog-style
# history and per-skill versions legitimately name older releases, and
# rewriting those would corrupt real content.
#
# Exit codes:
#   0 = already in sync, or updated successfully
#   1 = README or SKILL.md not found, or template version unreadable

set -euo pipefail

DRY_RUN=false
README=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -*) echo "Usage: sync-readme-version.sh [--dry-run] [README]" >&2; exit 1 ;;
    *)  README="$1"; shift ;;
  esac
done

README="${README:-$HOME/.agents/README.md}"
SKILL_FILE="$HOME/.agents/skills/agentfs-setup/SKILL.md"

[[ -f "$README" ]]     || { echo "❌ Not found: $README" >&2; exit 1; }
[[ -f "$SKILL_FILE" ]] || { echo "❌ Not found: $SKILL_FILE" >&2; exit 1; }

TEMPLATE_VERSION=$(grep -m1 -oP 'version:\s*"\K[0-9.]+' "$SKILL_FILE" || true)
[[ -n "$TEMPLATE_VERSION" ]] || { echo "❌ No version in $SKILL_FILE" >&2; exit 1; }

# Collect the lines that are out of step, so the report names them.
STALE=$(grep -nE "AgentFS v[0-9]+\.[0-9]+\.[0-9]+ enforces|<!-- agentfs-template-version: [0-9]+\.[0-9]+\.[0-9]+ -->" "$README" \
        | grep -v "v\?${TEMPLATE_VERSION//./\\.}" || true)

if [[ -z "$STALE" ]]; then
  echo "[sync-readme-version] ✅ README already at v${TEMPLATE_VERSION}"
  $DRY_RUN && echo "DRY_RUN_RESULT=CONVERGED"
  exit 0
fi

echo "[sync-readme-version] Template v${TEMPLATE_VERSION}; stale reference(s):"
while IFS= read -r line; do
  echo "[sync-readme-version]   ${line%%:*}: ${line#*:}"
done <<< "$STALE"

if $DRY_RUN; then
  echo "DRY_RUN_RESULT=PENDING"
  exit 0
fi

sed -i -E \
  -e "s/AgentFS v[0-9]+\.[0-9]+\.[0-9]+ enforces/AgentFS v${TEMPLATE_VERSION} enforces/" \
  -e "s/<!-- agentfs-template-version: [0-9]+\.[0-9]+\.[0-9]+ -->/<!-- agentfs-template-version: ${TEMPLATE_VERSION} -->/" \
  "$README"

# Verify rather than assume sed matched.
REMAIN=$(grep -nE "AgentFS v[0-9]+\.[0-9]+\.[0-9]+ enforces|<!-- agentfs-template-version: [0-9]+\.[0-9]+\.[0-9]+ -->" "$README" \
         | grep -v "v\?${TEMPLATE_VERSION//./\\.}" || true)
if [[ -n "$REMAIN" ]]; then
  echo "❌ Still stale after rewrite:" >&2
  echo "$REMAIN" >&2
  exit 1
fi

echo "[sync-readme-version] ✅ Updated README to v${TEMPLATE_VERSION}"
