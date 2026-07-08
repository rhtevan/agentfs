#!/usr/bin/env bash
# audit-index.sh — Audit one directory's index.md for broken links and missing entries.
#
# Usage:  bash audit-index.sh <directory>
# Output: structured report (always exits 0)
#
# Sections:
#   INDEX: EXISTS | MISSING
#   --- BROKEN LINKS ---      links in index.md whose targets do not exist
#   --- MISSING ENTRIES ---    concept files / sub-bundle dirs not listed in index.md
#
# Missing-entry format:
#   CONCEPT|<filename>|<title>|<description>
#   SUB-BUNDLE|<dirname>/|<title>|

set -euo pipefail

DIR="${1:-.}"
DIR="${DIR%/}"
INDEX="$DIR/index.md"

RESERVED="assets samples references scripts templates archive"

is_reserved() {
  local name="$1" r
  for r in $RESERVED; do [[ "$name" == "$r" ]] && return 0; done
  return 1
}

# --- Helper: extract title from a concept .md frontmatter -----------
extract_meta() {
  local file="$1"
  _title="" _desc=""
  local in_fm=false
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      $in_fm && break || { in_fm=true; continue; }
    fi
    $in_fm || continue
    if [[ "$line" =~ ^title:\ *(.*) ]]; then
      _title="${BASH_REMATCH[1]}"
      _title="${_title#\"}" ; _title="${_title%\"}"
      _title="${_title#\'}" ; _title="${_title%\'}"
    fi
    if [[ "$line" =~ ^description:\ *(.*) ]]; then
      _desc="${BASH_REMATCH[1]}"
      _desc="${_desc#\"}" ; _desc="${_desc%\"}"
      _desc="${_desc#\'}" ; _desc="${_desc%\'}"
    fi
  done < "$file"
}

# --- Helper: title-case from kebab-case filename -------------------
title_from_filename() {
  basename "$1" .md | sed 's/-/ /g' | \
    awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) tolower(substr($i,2))}1'
}

echo "=== AUDIT: $DIR ==="

# ── INDEX MISSING ──────────────────────────────────────────────────
if [[ ! -f "$INDEX" ]]; then
  echo "INDEX: MISSING"
  echo ""
  echo "--- BROKEN LINKS ---"
  echo "(n/a — no index.md to check)"
  echo ""
  echo "--- MISSING ENTRIES ---"
  has_missing=false
  shopt -s nullglob
  for f in "$DIR"/*.md; do
    fname="$(basename "$f")"
    [[ "$fname" == "index.md" || "$fname" == "log.md" ]] && continue
    extract_meta "$f"
    [[ -z "$_title" ]] && _title="$(title_from_filename "$fname")"
    echo "CONCEPT|$fname|$_title|$_desc"
    has_missing=true
  done
  for d in "$DIR"/*/; do
    [[ -d "$d" ]] || continue
    dname="$(basename "$d")"
    [[ "$dname" == .* ]] && continue
    is_reserved "$dname" && continue
    stitle=""
    [[ -f "$d/index.md" ]] && stitle="$(grep -m1 '^#' "$d/index.md" | sed 's/^#\+[[:space:]]*//' || true)"
    [[ -z "$stitle" ]] && stitle="$(title_from_filename "$dname")"
    echo "SUB-BUNDLE|$dname/|$stitle|"
    has_missing=true
  done
  shopt -u nullglob
  $has_missing || echo "(none)"
  exit 0
fi

# ── INDEX EXISTS ───────────────────────────────────────────────────
echo "INDEX: EXISTS"

# Warn if index.md has frontmatter
first_line="$(head -1 "$INDEX" | tr -d '[:space:]')"
if [[ "$first_line" == "---" ]]; then
  echo "WARNING: index.md has YAML frontmatter (violates OKF §6)"
fi

# ── Build normalised set of linked paths ───────────────────────────
declare -A linked_norm
mapfile -t raw_links < <(grep -oP '\]\(\K[^)]+' "$INDEX" || true)

for lp in "${raw_links[@]+"${raw_links[@]}"}"; do
  clean="${lp%%#*}"        # strip anchor fragment
  clean="${clean#./}"      # strip leading ./
  clean="${clean%/}"       # strip trailing /
  clean="${clean%/index.md}"  # normalise dir/index.md → dir
  [[ -n "$clean" ]] && linked_norm["$clean"]=1
done

# ── Broken links ──────────────────────────────────────────────────
echo ""
echo "--- BROKEN LINKS ---"
has_broken=false
for lp in "${raw_links[@]+"${raw_links[@]}"}"; do
  clean="${lp%%#*}"
  [[ -z "$clean" ]] && continue        # anchor-only link
  resolved="$DIR/$clean"
  if [[ ! -e "$resolved" ]]; then
    echo "$lp"
    has_broken=true
  fi
done
$has_broken || echo "(none)"

# ── Missing entries ───────────────────────────────────────────────
echo ""
echo "--- MISSING ENTRIES ---"
has_missing=false
shopt -s nullglob

# Concept .md files
for f in "$DIR"/*.md; do
  fname="$(basename "$f")"
  [[ "$fname" == "index.md" || "$fname" == "log.md" ]] && continue

  # Check common link variants: file.md  (./file.md already normalised)
  if [[ -n "${linked_norm[$fname]+x}" ]]; then
    continue
  fi
  # Also check without extension (rare but possible)
  fname_no_ext="${fname%.md}"
  if [[ -n "${linked_norm[$fname_no_ext]+x}" ]]; then
    continue
  fi

  extract_meta "$f"
  [[ -z "$_title" ]] && _title="$(title_from_filename "$fname")"
  echo "CONCEPT|$fname|$_title|$_desc"
  has_missing=true
done

# Sub-bundle directories
for d in "$DIR"/*/; do
  [[ -d "$d" ]] || continue
  dname="$(basename "$d")"
  [[ "$dname" == .* ]] && continue
  is_reserved "$dname" && continue

  # Check common link variants: dir, dir/index.md
  idx_key="${dname}/index.md"
  if [[ -n "${linked_norm[$dname]+x}" ]] || [[ -n "${linked_norm[$idx_key]+x}" ]]; then
    continue
  fi

  stitle=""
  [[ -f "$d/index.md" ]] && stitle="$(grep -m1 '^#' "$d/index.md" | sed 's/^#\+[[:space:]]*//' || true)"
  [[ -z "$stitle" ]] && stitle="$(title_from_filename "$dname")"
  echo "SUB-BUNDLE|$dname/|$stitle|"
  has_missing=true
done

shopt -u nullglob
$has_missing || echo "(none)"
