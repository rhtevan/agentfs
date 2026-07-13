#!/usr/bin/env bash
# agentfs-check.sh — Layer 1: Structural Assertions
#
# Usage: bash agentfs-check.sh [TARGET_DIR]
#
#   TARGET_DIR   Directory containing .agents/ (default: .)
#
# Runs 7 deterministic structural checks against the .agents/ tree.
# No LLM required. Exit code 0 = all pass, non-zero = failures found.

set -euo pipefail

TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"
AGENTS_DIR="$TARGET/.agents"

PASS=0
FAIL=0
WARN=0
DETAILS=""

# ── Helpers ──────────────────────────────────────────────────────────
result_pass() {
  PASS=$((PASS + 1))
  echo "  [✅] $1"
}

result_fail() {
  FAIL=$((FAIL + 1))
  echo "  [❌] $1"
  DETAILS+="\n### $2\n$3\n"
}

result_warn() {
  WARN=$((WARN + 1))
  echo "  [⚠️ ] $1"
  DETAILS+="\n### $2\n$3\n"
}

# ── Pre-check ────────────────────────────────────────────────────────
if [ ! -d "$AGENTS_DIR" ]; then
  echo "L0 — Absent: No .agents/ directory at $TARGET"
  exit 1
fi

echo "=== Layer 1: Structural Assertions ==="
echo "Target: $TARGET"
echo ""

# ── S1: Link Integrity ───────────────────────────────────────────────
echo "S1: Link Integrity"
BROKEN_LINKS=0
BROKEN_LIST=""

while IFS= read -r mdfile; do
  dir="$(dirname "$mdfile")"
  # Extract markdown links [text](path) — skip http/https/mailto links
  # First, strip fenced code blocks to avoid checking example/template paths
  stripped_content=$(sed '/^```/,/^```/d' "$mdfile" 2>/dev/null || cat "$mdfile")
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    # Skip URLs and anchors
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    # Skip template/placeholder links containing < >
    case "$link" in
      *\<*\>*) continue ;;
    esac
    # Skip single-word generic placeholders (e.g., 'path', 'relative-path')
    case "$link" in
      path|relative-path|url-or-path|concept-file.md|another.md) continue ;;
    esac
    # Skip links inside backtick-escaped inline code in table cells
    # (grep may pick up links from `[text](path)` inside | ... | cells)
    if echo "$link" | grep -qE '^[a-z][-a-z]*$'; then
      # Bare single-word lowercase — likely a placeholder, not a real path
      continue
    fi
    # Strip any anchor fragment
    link_path="${link%%#*}"
    [ -z "$link_path" ] && continue
    # Resolve relative to the markdown file's directory
    resolved="$dir/$link_path"
    if [ ! -e "$resolved" ]; then
      BROKEN_LINKS=$((BROKEN_LINKS + 1))
      BROKEN_LIST+="  - $mdfile → $link\n"
    fi
  done < <(echo "$stripped_content" | grep -oP '\]\(\K[^)]+' 2>/dev/null || true)
done < <(find "$AGENTS_DIR" -name '*.md' -type f 2>/dev/null)

# Also check AGENTS.md at project root
if [ -f "$TARGET/AGENTS.md" ]; then
  dir="$TARGET"
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    link_path="${link%%#*}"
    [ -z "$link_path" ] && continue
    resolved="$dir/$link_path"
    if [ ! -e "$resolved" ]; then
      BROKEN_LINKS=$((BROKEN_LINKS + 1))
      BROKEN_LIST+="  - AGENTS.md → $link\n"
    fi
  done < <(grep -oP '\]\(\K[^)]+' "$TARGET/AGENTS.md" 2>/dev/null || true)
fi

if [ "$BROKEN_LINKS" -eq 0 ]; then
  result_pass "S1: Link Integrity — 0 broken links"
else
  result_fail "S1: Link Integrity — $BROKEN_LINKS broken link(s)" \
    "S1 Details" "$(echo -e "$BROKEN_LIST")"
fi

# ── S2: Log Monotonicity ─────────────────────────────────────────────
echo "S2: Log Monotonicity"
LOG_FILE="$AGENTS_DIR/log.md"

if [ ! -f "$LOG_FILE" ]; then
  result_fail "S2: Log Monotonicity — log.md not found" \
    "S2 Details" "Expected: $AGENTS_DIR/log.md"
else
  # Extract timestamp headings
  TIMESTAMPS=()
  while IFS= read -r line; do
    ts="$(echo "$line" | grep -oP '(?<=^## )\d{4}-\d{2}-\d{2} \d{2}:\d{2}' || true)"
    [ -n "$ts" ] && TIMESTAMPS+=("$ts")
  done < "$LOG_FILE"

  if [ ${#TIMESTAMPS[@]} -eq 0 ]; then
    result_warn "S2: Log Monotonicity — no timestamp headings found" \
      "S2 Details" "log.md exists but has no ## YYYY-MM-DD HH:MM headings"
  else
    MONOTONIC=true
    for ((i=1; i<${#TIMESTAMPS[@]}; i++)); do
      prev="${TIMESTAMPS[$((i-1))]}"
      curr="${TIMESTAMPS[$i]}"
      if [[ "$curr" > "$prev" ]]; then
        MONOTONIC=false
        break
      fi
    done
    if $MONOTONIC; then
      result_pass "S2: Log Monotonicity — ${#TIMESTAMPS[@]} entries, all ordered"
    else
      result_fail "S2: Log Monotonicity — timestamps not in descending order" \
        "S2 Details" "Entry '$curr' appears after '$prev' but is newer"
    fi
  fi
fi

# ── S3: Index Completeness ───────────────────────────────────────────
echo "S3: Index Completeness"
S3_ISSUES=""
S3_FAIL=false

# Check skills
SKILLS_INDEX="$AGENTS_DIR/skills/index.md"
if [ -d "$AGENTS_DIR/skills" ]; then
  SKILL_COUNT=0
  MISSING_SKILLS=""
  while IFS= read -r skill_dir; do
    skill_name="$(basename "$skill_dir")"
    SKILL_COUNT=$((SKILL_COUNT + 1))
    if [ -f "$SKILLS_INDEX" ]; then
      if ! grep -q "$skill_name" "$SKILLS_INDEX" 2>/dev/null; then
        MISSING_SKILLS+="  - $skill_name not in skills/index.md\n"
        S3_FAIL=true
      fi
    else
      S3_ISSUES+="  - skills/index.md not found\n"
      S3_FAIL=true
    fi
  done < <(find "$AGENTS_DIR/skills" -mindepth 1 -maxdepth 1 -type d \
           -exec test -f '{}/SKILL.md' \; -print 2>/dev/null)

  if [ -n "$MISSING_SKILLS" ]; then
    S3_ISSUES+="$MISSING_SKILLS"
  fi
fi

# Check profiles
PROFILES_INDEX="$AGENTS_DIR/profiles/index.md"
if [ -d "$AGENTS_DIR/profiles" ]; then
  while IFS= read -r profile_dir; do
    profile_name="$(basename "$profile_dir")"
    if [ -f "$PROFILES_INDEX" ]; then
      if ! grep -q "$profile_name" "$PROFILES_INDEX" 2>/dev/null; then
        S3_ISSUES+="  - Profile '$profile_name' not in profiles/index.md\n"
        S3_FAIL=true
      fi
    fi
  done < <(find "$AGENTS_DIR/profiles" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi

if $S3_FAIL; then
  result_fail "S3: Index Completeness — missing entries" \
    "S3 Details" "$(echo -e "$S3_ISSUES")"
else
  result_pass "S3: Index Completeness — all skills/profiles indexed"
fi

# ── S4: Frontmatter Validity ─────────────────────────────────────────
echo "S4: Frontmatter Validity"
S4_TOTAL=0
S4_INVALID=0
S4_ISSUES=""

while IFS= read -r skillmd; do
  S4_TOTAL=$((S4_TOTAL + 1))
  # Check for YAML frontmatter delimiters
  first_line="$(head -1 "$skillmd")"
  if [ "$first_line" != "---" ]; then
    S4_INVALID=$((S4_INVALID + 1))
    S4_ISSUES+="  - $(echo "$skillmd" | sed "s|$AGENTS_DIR/||"): no YAML frontmatter\n"
    continue
  fi
  # Extract frontmatter and check for metadata.tags
  frontmatter="$(sed -n '1,/^---$/{ /^---$/d; p; }' "$skillmd" | tail -n +1)"
  if ! echo "$frontmatter" | grep -qE '^\s*tags:\s*\[' ; then
    S4_INVALID=$((S4_INVALID + 1))
    S4_ISSUES+="  - $(echo "$skillmd" | sed "s|$AGENTS_DIR/||"): missing metadata.tags\n"
  fi
done < <(find "$AGENTS_DIR/skills" -name 'SKILL.md' -type f 2>/dev/null)

if [ "$S4_TOTAL" -eq 0 ]; then
  result_pass "S4: Frontmatter Validity — no SKILL.md files to check"
elif [ "$S4_INVALID" -eq 0 ]; then
  result_pass "S4: Frontmatter Validity — $S4_TOTAL/$S4_TOTAL valid"
else
  result_fail "S4: Frontmatter Validity — $S4_INVALID/$S4_TOTAL invalid" \
    "S4 Details" "$(echo -e "$S4_ISSUES")"
fi

# ── S5: Scope Correctness ────────────────────────────────────────────
echo "S5: Scope Correctness"
S5_ISSUES=""
S5_FAIL=false
USER_AGENTS="$HOME/.agents"

# USER scope must NOT have memories/ or profiles/
if [ -d "$USER_AGENTS/memories" ]; then
  S5_ISSUES+="  - ~/.agents/memories/ exists (memories are PROJECT-only)\n"
  S5_FAIL=true
fi
if [ -d "$USER_AGENTS/profiles" ]; then
  S5_ISSUES+="  - ~/.agents/profiles/ exists (profiles are PROJECT-only)\n"
  S5_FAIL=true
fi

# PROJECT scope must NOT have knowledge/
# Only check this if the target is NOT the USER scope (~/.agents)
if [ "$AGENTS_DIR" != "$USER_AGENTS" ]; then
  if [ -d "$AGENTS_DIR/knowledge" ]; then
    S5_ISSUES+="  - .agents/knowledge/ exists (knowledge is USER-only)\n"
    S5_FAIL=true
  fi
fi

if $S5_FAIL; then
  result_fail "S5: Scope Correctness — violations found" \
    "S5 Details" "$(echo -e "$S5_ISSUES")"
else
  result_pass "S5: Scope Correctness — no violations"
fi

# ── S6: Changelog Monotonicity ───────────────────────────────────────
echo "S6: Changelog Monotonicity"
S6_ISSUES=""
S6_FAIL=false
S6_CHECKED=0

while IFS= read -r mdfile; do
  # Only check files that have a Changelog section
  if ! grep -qiE '^#+\s*Changelog' "$mdfile" 2>/dev/null; then
    continue
  fi
  S6_CHECKED=$((S6_CHECKED + 1))

  # Extract timestamps from changelog table rows (| YYYY-MM-DD HH:MM | ...)
  CL_TIMESTAMPS=()
  in_changelog=false
  while IFS= read -r line; do
    if echo "$line" | grep -qiE '^#+\s*Changelog'; then
      in_changelog=true
      continue
    fi
    if $in_changelog; then
      # Stop at next heading
      if echo "$line" | grep -qE '^#+\s'; then
        break
      fi
      ts="$(echo "$line" | grep -oP '\|\s*\K\d{4}-\d{2}-\d{2}(\s+\d{2}:\d{2})?' | head -1 || true)"
      [ -n "$ts" ] && CL_TIMESTAMPS+=("$ts")
    fi
  done < "$mdfile"

  if [ ${#CL_TIMESTAMPS[@]} -gt 1 ]; then
    for ((i=1; i<${#CL_TIMESTAMPS[@]}; i++)); do
      prev="${CL_TIMESTAMPS[$((i-1))]}"
      curr="${CL_TIMESTAMPS[$i]}"
      if [[ "$curr" > "$prev" ]]; then
        short="$(echo "$mdfile" | sed "s|$TARGET/||")"
        S6_ISSUES+="  - $short: '$curr' after '$prev'\n"
        S6_FAIL=true
        break
      fi
    done
  fi
done < <(find "$AGENTS_DIR" -name '*.md' -type f 2>/dev/null; \
         [ -f "$TARGET/AGENTS.md" ] && echo "$TARGET/AGENTS.md")

if [ "$S6_CHECKED" -eq 0 ]; then
  result_pass "S6: Changelog Monotonicity — no changelog sections found"
elif $S6_FAIL; then
  result_fail "S6: Changelog Monotonicity — out-of-order timestamps" \
    "S6 Details" "$(echo -e "$S6_ISSUES")"
else
  result_pass "S6: Changelog Monotonicity — $S6_CHECKED files checked, all ordered"
fi

# ── S7: Orphan Detection ─────────────────────────────────────────────
echo "S7: Orphan Detection"
ORPHANS=""
ORPHAN_COUNT=0

# Collect all links from all index.md files and AGENTS.md
ALL_LINKS=$(mktemp)
while IFS= read -r idx; do
  dir="$(dirname "$idx")"
  while IFS= read -r link; do
    case "$link" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    link_path="${link%%#*}"
    [ -z "$link_path" ] && continue
    resolved="$(cd "$dir" && realpath -m "$link_path" 2>/dev/null || echo "$dir/$link_path")"
    echo "$resolved" >> "$ALL_LINKS"
  done < <(grep -oP '\]\(\K[^)]+' "$idx" 2>/dev/null || true)
done < <(find "$AGENTS_DIR" -name 'index.md' -type f 2>/dev/null; \
         [ -f "$TARGET/AGENTS.md" ] && echo "$TARGET/AGENTS.md")

# Check each non-infrastructure file
while IFS= read -r agentfile; do
  basename="$(basename "$agentfile")"
  # Skip infrastructure files
  case "$basename" in
    index.md|log.md|.session-marker|.checkpoint|.gitkeep) continue ;;
  esac
  # Check if this file is linked from any index
  if ! grep -qF "$agentfile" "$ALL_LINKS" 2>/dev/null; then
    # Also check by relative name in case realpath differs
    short="$(echo "$agentfile" | sed "s|$TARGET/||")"
    if ! grep -qF "$short" "$ALL_LINKS" 2>/dev/null; then
      ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
      ORPHANS+="  - $short\n"
    fi
  fi
done < <(find "$AGENTS_DIR" -name '*.md' -type f \
         ! -name 'index.md' ! -name 'log.md' 2>/dev/null)

rm -f "$ALL_LINKS"

if [ "$ORPHAN_COUNT" -eq 0 ]; then
  result_pass "S7: Orphan Detection — 0 orphans"
else
  result_warn "S7: Orphan Detection — $ORPHAN_COUNT file(s) not linked from any index" \
    "S7 Details" "$(echo -e "$ORPHANS")"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Layer 1 Summary ==="
TOTAL=$((PASS + FAIL + WARN))
echo "Pass: $PASS / $TOTAL"
[ "$WARN" -gt 0 ] && echo "Warnings: $WARN"
[ "$FAIL" -gt 0 ] && echo "Failures: $FAIL"

if [ -n "$DETAILS" ]; then
  echo ""
  echo "=== Details ==="
  echo -e "$DETAILS"
fi

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
