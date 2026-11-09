#!/usr/bin/env bash
# merge-skills.sh — Copy project-scoped skills to USER scope
#
# Usage: merge-skills.sh [--force] [--project-root DIR] [SKILL_NAME ...]
#
# If no SKILL_NAME arguments, copies all skills from project scope.
# --force overwrites existing USER skills with the same name.
#
# Exit codes:
#   0 — All skills copied (or skipped) successfully
#   1 — Source directory not found or errors occurred

set -euo pipefail

FORCE=false
PROJECT_ROOT="."
SKILL_NAMES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true; shift ;;
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    *) SKILL_NAMES+=("$1"); shift ;;
  esac
done

SOURCE="$PROJECT_ROOT/.agents/skills"
DEST="$HOME/.agents/skills"

echo "Skill Merge"
echo "═══════════"
echo "Source: $SOURCE"
echo "Dest:   $DEST"
echo "Force:  $FORCE"
echo ""

# Validate source
if [[ ! -d "$SOURCE" ]]; then
  echo "❌ Source not found: $SOURCE"
  exit 1
fi

# Validate destination
if [[ ! -d "$DEST" ]]; then
  echo "❌ Destination not found: $DEST"
  echo "   Run 'agentfs-setup' in USER scope first"
  exit 1
fi

# Build skill list
if [[ ${#SKILL_NAMES[@]} -eq 0 ]]; then
  for d in "$SOURCE"/*/; do
    [[ -f "$d/SKILL.md" ]] && SKILL_NAMES+=("$(basename "$d")")
  done
fi

if [[ ${#SKILL_NAMES[@]} -eq 0 ]]; then
  echo "❌ No skills found in $SOURCE"
  exit 1
fi

echo "Skills to merge: ${#SKILL_NAMES[@]}"
echo ""

COPIED=0
SKIPPED=0
ERRORS=0

printf "%-30s %s\n" "Skill" "Status"
printf "%-30s %s\n" "-----" "------"

for name in "${SKILL_NAMES[@]}"; do
  src="$SOURCE/$name"
  dst="$DEST/$name"

  if [[ ! -d "$src" || ! -f "$src/SKILL.md" ]]; then
    printf "%-30s %s\n" "$name" "✗ not found in project"
    ((ERRORS++))
    continue
  fi

  if [[ -d "$dst" ]]; then
    if [[ "$FORCE" == "true" ]]; then
      rm -rf "$dst"
      cp -r "$src" "$dst"
      printf "%-30s %s\n" "$name" "✓ copied (overwritten)"
      ((COPIED++))
    else
      printf "%-30s %s\n" "$name" "⊘ skipped (already exists)"
      ((SKIPPED++))
    fi
  else
    cp -r "$src" "$dst"
    printf "%-30s %s\n" "$name" "✓ copied"
    ((COPIED++))
  fi
done

echo ""
echo "═══════════"
echo "Copied: $COPIED  Skipped: $SKIPPED  Errors: $ERRORS"

if [[ "$COPIED" -gt 0 ]]; then
  echo ""
  echo "Run post-write to refresh the skills index."
fi

[[ "$ERRORS" -eq 0 ]] && exit 0 || exit 1
