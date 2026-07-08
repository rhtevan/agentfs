#!/usr/bin/env bash
# rebuild-index.sh — Generate a complete index.md for a directory from its actual contents.
#
# Usage:  bash rebuild-index.sh <directory> [title]
# Output: index.md content on stdout (no YAML frontmatter)
#
# - Derives a title from the existing index.md heading, the supplied
#   argument, or the directory name (in that priority order).
# - Lists concept .md files with title/description from frontmatter.
# - Lists sub-bundle directories with title from their index.md.
# - Skips reserved files (index.md, log.md) and reserved directories.

set -euo pipefail

DIR="${1:-.}"
DIR="${DIR%/}"
TITLE="${2:-}"

RESERVED="assets samples references scripts templates archive"

is_reserved() {
  local name="$1" r
  for r in $RESERVED; do [[ "$name" == "$r" ]] && return 0; done
  return 1
}

# --- Helper: title-case from kebab-case ----------------------------
title_case() {
  echo "$1" | sed 's/-/ /g' | \
    awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

# --- Derive title --------------------------------------------------
if [[ -z "$TITLE" ]]; then
  # Try existing index.md first heading
  if [[ -f "$DIR/index.md" ]]; then
    TITLE="$(grep -m1 '^#' "$DIR/index.md" | sed 's/^#\+[[:space:]]*//' || true)"
  fi
  # Fallback: directory name → Title Case
  if [[ -z "$TITLE" ]]; then
    TITLE="$(title_case "$(basename "$DIR")")"
  fi
fi

# --- Collect concepts ----------------------------------------------
concepts=()
shopt -s nullglob
for f in "$DIR"/*.md; do
  fname="$(basename "$f")"
  [[ "$fname" == "index.md" || "$fname" == "log.md" ]] && continue

  title="" desc=""
  in_fm=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      $in_fm && break || { in_fm=true; continue; }
    fi
    $in_fm || continue
    if [[ "$line" =~ ^title:\ *(.*) ]]; then
      title="${BASH_REMATCH[1]}"
      title="${title#\"}" ; title="${title%\"}"
      title="${title#\'}" ; title="${title%\'}"
    fi
    if [[ "$line" =~ ^description:\ *(.*) ]]; then
      desc="${BASH_REMATCH[1]}"
      desc="${desc#\"}" ; desc="${desc%\"}"
      desc="${desc#\'}" ; desc="${desc%\'}"
    fi
  done < "$f"
  [[ -z "$title" ]] && title="$(title_case "$(basename "$fname" .md)")"

  if [[ -n "$desc" ]]; then
    concepts+=("* [$title]($fname) - $desc")
  else
    concepts+=("* [$title]($fname)")
  fi
done

# --- Collect sub-bundles -------------------------------------------
subbundles=()
for d in "$DIR"/*/; do
  [[ -d "$d" ]] || continue
  dname="$(basename "$d")"
  [[ "$dname" == .* ]] && continue
  is_reserved "$dname" && continue

  stitle=""
  [[ -f "$d/index.md" ]] && stitle="$(grep -m1 '^#' "$d/index.md" | sed 's/^#\+[[:space:]]*//' || true)"
  [[ -z "$stitle" ]] && stitle="$(title_case "$dname")"

  subbundles+=("* [$stitle]($dname/index.md)")
done
shopt -u nullglob

# --- Output --------------------------------------------------------
echo "# $TITLE"
echo ""

if [[ ${#concepts[@]} -gt 0 ]]; then
  for entry in "${concepts[@]}"; do
    echo "$entry"
  done
  echo ""
fi

if [[ ${#subbundles[@]} -gt 0 ]]; then
  # Add a section heading only when concepts also exist
  if [[ ${#concepts[@]} -gt 0 ]]; then
    echo "## Sub-bundles"
    echo ""
  fi
  for entry in "${subbundles[@]}"; do
    echo "$entry"
  done
  echo ""
fi
