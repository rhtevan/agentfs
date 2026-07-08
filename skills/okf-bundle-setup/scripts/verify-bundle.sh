#!/usr/bin/env bash
# verify-bundle.sh — Check OKF v0.1 conformance of a knowledge bundle.
#
# Usage: bash verify-bundle.sh <BUNDLE_ROOT>
#
# Checks:
#   1. Every non-reserved .md file has YAML frontmatter with a `type` field.
#   2. Reserved files (index.md, log.md) have NO YAML frontmatter.
#   3. Internal markdown links resolve to existing files.
#   4. index.md exists at the bundle root.
#   5. log.md exists at the bundle root.
#   6. No README co-exists alongside index.md.
#   7. Reserved directory names are not used as sub-bundles.
#   8. All bundle/sub-bundle directory names are lowercase kebab-case.
#   9. log.md entries are in reverse chronological order (newest first).

set -euo pipefail

BUNDLE_ROOT="${1:?Usage: verify-bundle.sh <BUNDLE_ROOT>}"
BUNDLE_ROOT="$(cd "$BUNDLE_ROOT" && pwd)"

PASS=0
FAIL=0
WARN=0

pass() { echo "  [✓] $1"; PASS=$((PASS + 1)); }
fail() { echo "  [✗] $1"; FAIL=$((FAIL + 1)); }
warn() { echo "  [~] $1"; WARN=$((WARN + 1)); }

echo "═══════════════════════════════════════════════════════════════"
echo "  OKF Bundle Conformance Check"
echo "  Root: $BUNDLE_ROOT"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# ── 1. Root infrastructure files ────────────────────────────────────
echo "── Infrastructure ──"
if [[ -f "$BUNDLE_ROOT/index.md" ]]; then
  pass "Root index.md exists"
else
  fail "Root index.md is MISSING"
fi

if [[ -f "$BUNDLE_ROOT/log.md" ]]; then
  pass "Root log.md exists"
else
  warn "Root log.md is missing (optional but recommended)"
fi

# ── 1b. No README co-existing with index.md ─────────────────────────
README_FOUND=""
for candidate in "$BUNDLE_ROOT"/README.md "$BUNDLE_ROOT"/readme.md \
                 "$BUNDLE_ROOT"/Readme.md "$BUNDLE_ROOT"/README.txt \
                 "$BUNDLE_ROOT"/readme.txt "$BUNDLE_ROOT"/README.rst \
                 "$BUNDLE_ROOT"/readme.rst "$BUNDLE_ROOT"/README; do
  if [[ -f "$candidate" ]]; then
    README_FOUND="$(basename "$candidate")"
    break
  fi
done

if [[ -n "$README_FOUND" && -f "$BUNDLE_ROOT/index.md" ]]; then
  fail "README ($README_FOUND) co-exists with index.md — absorb it into index.md and remove"
elif [[ -n "$README_FOUND" && ! -f "$BUNDLE_ROOT/index.md" ]]; then
  fail "README ($README_FOUND) found but not absorbed into index.md — run scaffold to convert"
else
  pass "No README/index.md duplication"
fi

# ── 1c. Directory naming convention (lowercase kebab-case) ──────────
# Check bundle root name
is_kebab_case() {
  local name="$1"
  # Must match: lowercase letters, digits, hyphens only; no leading/trailing hyphen
  [[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]]
}

BUNDLE_DIRNAME="$(basename "$BUNDLE_ROOT")"
if is_kebab_case "$BUNDLE_DIRNAME"; then
  pass "Bundle root '$BUNDLE_DIRNAME' is lowercase kebab-case"
else
  fail "Bundle root '$BUNDLE_DIRNAME' is NOT lowercase kebab-case — rename to '$(echo "$BUNDLE_DIRNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[_ ]/-/g; s/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-25)'"
fi

# Check sub-bundle directory names (non-reserved, non-hidden)
while IFS= read -r -d '' dir; do
  dname="$(basename "$dir")"
  reldir="${dir#$BUNDLE_ROOT/}"
  # Skip reserved dirs and hidden dirs (already pruned, but guard)
  case "$dname" in
    assets|samples|references|scripts|templates|archive) continue ;;
  esac
  if ! is_kebab_case "$dname"; then
    fail "Sub-bundle '$reldir' is NOT lowercase kebab-case — rename to '$(echo "$dname" | tr '[:upper:]' '[:lower:]' | sed 's/[_ ]/-/g; s/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-25)'"
  fi
done < <(find "$BUNDLE_ROOT" -mindepth 1 -name '.*' -prune -o -type d -print0 2>/dev/null)
echo ""

# ── 2. Reserved files must NOT have frontmatter ─────────────────────
echo "── Reserved Files (no frontmatter allowed) ──"
while IFS= read -r -d '' file; do
  relpath="${file#$BUNDLE_ROOT/}"
  basename_file="$(basename "$file")"

  if [[ "$basename_file" == "index.md" || "$basename_file" == "log.md" ]]; then
    # Check for YAML frontmatter (file starts with ---)
    first_line="$(head -1 "$file" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$first_line" == "---" ]]; then
      fail "$relpath has YAML frontmatter (reserved files must not)"
    else
      pass "$relpath has no frontmatter"
    fi
  fi
done < <(find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -name "*.md" \( -name "index.md" -o -name "log.md" \) -print0 2>/dev/null)
echo ""

# ── 2b. log.md reverse chronological order ──────────────────────────
echo "── Log Ordering (reverse chronological) ──"
if [[ -f "$BUNDLE_ROOT/log.md" ]]; then
  # Extract all ## YYYY-MM-DD headings in file order
  LOG_DATES=()
  while IFS= read -r line; do
    # Match ## YYYY-MM-DD (with optional trailing text)
    if [[ "$line" =~ ^##[[:space:]]+(([0-9]{4})-([0-9]{2})-([0-9]{2})) ]]; then
      LOG_DATES+=("${BASH_REMATCH[1]}")
    fi
  done < "$BUNDLE_ROOT/log.md"

  if [[ "${#LOG_DATES[@]}" -eq 0 ]]; then
    warn "log.md has no date headings (## YYYY-MM-DD)"
  elif [[ "${#LOG_DATES[@]}" -eq 1 ]]; then
    pass "log.md has 1 date entry (${LOG_DATES[0]}) — order trivially correct"
  else
    # Check that dates are in descending (reverse chronological) order
    ORDER_OK=true
    for (( i=0; i<${#LOG_DATES[@]}-1; i++ )); do
      current="${LOG_DATES[$i]}"
      next="${LOG_DATES[$((i+1))]}"
      if [[ "$current" < "$next" ]]; then
        ORDER_OK=false
        break
      fi
    done
    if $ORDER_OK; then
      pass "log.md dates in reverse chronological order (${LOG_DATES[0]} … ${LOG_DATES[-1]})"
    else
      fail "log.md dates NOT in reverse chronological order — newest (## YYYY-MM-DD) must come first. Found: ${LOG_DATES[*]}"
    fi
  fi
else
  echo "  · log.md not present — skipping order check"
fi
echo ""

# ── 3. Concept files must have frontmatter with `type` ──────────────
echo "── Concept Documents (frontmatter + type required) ──"
CONCEPT_COUNT=0
while IFS= read -r -d '' file; do
  relpath="${file#$BUNDLE_ROOT/}"
  basename_file="$(basename "$file")"

  # Skip reserved files
  if [[ "$basename_file" == "index.md" || "$basename_file" == "log.md" ]]; then
    continue
  fi

  CONCEPT_COUNT=$((CONCEPT_COUNT + 1))

  # Check for YAML frontmatter
  first_line="$(head -1 "$file" 2>/dev/null | tr -d '[:space:]')"
  if [[ "$first_line" != "---" ]]; then
    fail "$relpath — missing YAML frontmatter"
    continue
  fi

  # Extract frontmatter (between first --- and second ---)
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$file" || true)"

  if [[ -z "$frontmatter" ]]; then
    fail "$relpath — empty YAML frontmatter"
    continue
  fi

  # Check for type field (grep may return 1 if no match — guard with || true)
  type_value="$(echo "$frontmatter" | grep -E '^type:' | head -1 | sed 's/^type:[[:space:]]*//' | sed 's/[[:space:]]*$//' || true)"
  if [[ -z "$type_value" ]]; then
    fail "$relpath — frontmatter missing required 'type' field"
  else
    pass "$relpath — type: $type_value"
  fi
done < <(find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -name "*.md" -print0 2>/dev/null)

if [[ "$CONCEPT_COUNT" -eq 0 ]]; then
  warn "No concept documents found"
fi
echo ""

# ── 4. Internal link resolution ─────────────────────────────────────
echo "── Link Resolution ──"
LINK_TOTAL=0
LINK_BROKEN=0
while IFS= read -r -d '' file; do
  relpath="${file#$BUNDLE_ROOT/}"
  filedir="$(dirname "$file")"

  # Extract markdown links: [text](target) — skip external URLs and anchors
  while IFS= read -r target; do
    [[ -z "$target" ]] && continue
    # Skip external URLs
    [[ "$target" =~ ^https?:// ]] && continue
    # Skip pure anchors
    [[ "$target" =~ ^# ]] && continue
    # Strip anchor from target
    target_clean="${target%%#*}"
    [[ -z "$target_clean" ]] && continue

    LINK_TOTAL=$((LINK_TOTAL + 1))

    # Resolve path
    if [[ "$target_clean" == /* ]]; then
      # Bundle-relative (absolute)
      resolved="$BUNDLE_ROOT$target_clean"
    else
      # Relative to current file's directory
      resolved="$filedir/$target_clean"
    fi

    # Normalize (remove . and ..)
    resolved="$(readlink -m "$resolved" 2>/dev/null || echo "$resolved")"

    if [[ -e "$resolved" ]]; then
      : # link resolves — no output to keep report concise
    else
      fail "$relpath → $target (broken link)"
      LINK_BROKEN=$((LINK_BROKEN + 1))
    fi
  done < <(grep -oP '\[.*?\]\(\K[^)]+' "$file" 2>/dev/null || true)
done < <(find "$BUNDLE_ROOT" -name '.*' -prune -o -type f -name "*.md" -print0 2>/dev/null)

LINK_OK=$((LINK_TOTAL - LINK_BROKEN))
if [[ "$LINK_TOTAL" -gt 0 ]]; then
  echo "  Links: $LINK_OK/$LINK_TOTAL resolved"
  if [[ "$LINK_BROKEN" -eq 0 ]]; then
    pass "All internal links resolve"
  fi
else
  warn "No internal links found to check"
fi
echo ""

# ── 5. Subdirectory index coverage + reserved name enforcement ──────
echo "── Subdirectory Index Coverage ──"

# Reserved directory names — helper dirs, not sub-bundles
is_reserved_dir() {
  case "$1" in
    assets|samples|references|scripts|templates|archive) return 0 ;;
    *) return 1 ;;
  esac
}

while IFS= read -r -d '' dir; do
  reldir="${dir#$BUNDLE_ROOT/}"
  dirname_base="$(basename "$dir")"

  if is_reserved_dir "$dirname_base"; then
    # Reserved dir — must NOT contain concept .md files (that would
    # indicate it's being misused as a sub-bundle)
    concept_count="$(find "$dir" -maxdepth 1 -type f -name "*.md" ! -name "index.md" ! -name "log.md" 2>/dev/null | wc -l || true)"
    concept_count="$(echo "$concept_count" | tr -d '[:space:]')"
    if [[ "$concept_count" -gt 0 ]]; then
      fail "$reldir/ is a reserved name but contains $concept_count concept .md file(s) — rename the directory"
    fi
    # Check if it has an index.md (it shouldn't)
    if [[ -f "$dir/index.md" ]]; then
      warn "$reldir/ is a reserved helper dir but has an index.md (unexpected)"
    fi
    continue
  fi

  if [[ -f "$dir/index.md" ]]; then
    pass "$reldir/ has index.md"
  else
    # Only warn if the directory contains .md concept files
    md_count="$(find "$dir" -maxdepth 1 -type f -name "*.md" ! -name "index.md" ! -name "log.md" 2>/dev/null | wc -l || true)"
    md_count="$(echo "$md_count" | tr -d '[:space:]')"
    if [[ "$md_count" -gt 0 ]]; then
      warn "$reldir/ has $md_count concept(s) but no index.md"
    fi
  fi
done < <(find "$BUNDLE_ROOT" -mindepth 1 -name '.*' -prune -o -type d -print0 2>/dev/null | sort -z)
echo ""

# ── Summary ─────────────────────────────────────────────────────────
echo "═══════════════════════════════════════════════════════════════"
echo "  Results:  $PASS passed,  $FAIL failed,  $WARN warnings"
if [[ "$FAIL" -eq 0 ]]; then
  echo "  ✅ Bundle is OKF v0.1 conformant."
else
  echo "  ❌ Bundle has conformance issues — see [✗] items above."
fi
echo "═══════════════════════════════════════════════════════════════"

exit "$FAIL"
