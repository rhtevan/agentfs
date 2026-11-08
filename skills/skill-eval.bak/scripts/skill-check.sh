#!/usr/bin/env bash
# skill-check.sh — Deterministic quality checks for a single skill
#
# Usage: bash skill-check.sh <skill-dir>
#
#   skill-dir   Path to the skill directory (containing SKILL.md)
#
# Runs checks S01–S22 against the seven quality principles from skill-gen.
# No LLM required. Exit code = number of critical (🔴) failures.

set -euo pipefail

SKILL_DIR="${1:?Usage: skill-check.sh <skill-dir>}"
SKILL_DIR="$(cd "$SKILL_DIR" && pwd)"
SKILL_MD="$SKILL_DIR/SKILL.md"
SKILL_NAME="$(basename "$SKILL_DIR")"

PASS=0
FAIL=0
WARN=0
SKIP=0
INFO=0
DETAILS=""

result_pass() { PASS=$((PASS + 1)); echo "  [✅] $1"; }
result_fail() { FAIL=$((FAIL + 1)); echo "  [🔴] $1"; DETAILS+="\n### $1\n$2\n"; }
result_warn() { WARN=$((WARN + 1)); echo "  [🟡] $1"; DETAILS+="\n### $1\n$2\n"; }
result_info() { INFO=$((INFO + 1)); echo "  [🟢] $1"; }
result_skip() { SKIP=$((SKIP + 1)); echo "  [--] $1"; }

echo "=== Skill Eval: $SKILL_NAME ==="
echo "  Path: $SKILL_DIR"
echo ""

if [ ! -f "$SKILL_MD" ]; then
  result_fail "S00: SKILL.md not found" "No SKILL.md at $SKILL_DIR"
  echo ""
  echo "Results: $PASS pass, $FAIL fail, $WARN warn, $SKIP skip"
  exit 1
fi

CONTENT="$(cat "$SKILL_MD")"

# ── Extract frontmatter ──────────────────────────────────────────────
FRONTMATTER=""
if echo "$CONTENT" | head -1 | grep -q '^---'; then
  FRONTMATTER=$(echo "$CONTENT" | sed -n '2,/^---$/p' | head -n -1 || true)
fi

# ── S01: Frontmatter completeness ────────────────────────────────────
echo "P1: Accuracy, Consistency & Testability"

if [ -z "$FRONTMATTER" ]; then
  result_fail "S01: No YAML frontmatter found" "SKILL.md must start with --- delimited YAML"
else
  S01_MISSING=""
  echo "$FRONTMATTER" | grep -q '^name:' || S01_MISSING+="name "
  echo "$FRONTMATTER" | grep -q 'description:' || S01_MISSING+="description "
  echo "$FRONTMATTER" | grep -q 'version:' || S01_MISSING+="metadata.version "
  echo "$FRONTMATTER" | grep -q 'tags:' || S01_MISSING+="metadata.tags "
  echo "$FRONTMATTER" | grep -q 'user-invocable:' || S01_MISSING+="user-invocable "

  if [ -z "$S01_MISSING" ]; then
    # Check version is quoted semver
    VERSION_VAL=$(echo "$FRONTMATTER" | grep -oP 'version: "\K[^"]+' || true)
    if [ -n "$VERSION_VAL" ] && echo "$VERSION_VAL" | grep -qP '^\d+\.\d+\.\d+$'; then
      result_pass "S01: Frontmatter complete (version: $VERSION_VAL)"
    elif [ -n "$VERSION_VAL" ]; then
      result_warn "S01: Version '$VERSION_VAL' not in semver format (N.N.N)" "Use quoted 3-part semver: version: \"1.0.0\""
    else
      result_warn "S01: Version not quoted or missing" "Use: version: \"1.0.0\""
    fi
  else
    result_fail "S01: Missing frontmatter fields: $S01_MISSING" "Add required fields to YAML frontmatter"
  fi
fi

# ── S02: Name matches directory ───────────────────────────────────────
if [ -n "$FRONTMATTER" ]; then
  FM_NAME=$(echo "$FRONTMATTER" | grep '^name:' | awk '{print $2}' | tr -d '"' || true)
  if [ "$FM_NAME" = "$SKILL_NAME" ]; then
    result_pass "S02: Name '$FM_NAME' matches directory"
  elif [ -n "$FM_NAME" ]; then
    result_fail "S02: Name '$FM_NAME' != directory '$SKILL_NAME'" "Rename to match: name: $SKILL_NAME"
  else
    result_fail "S02: No name field in frontmatter" "Add: name: $SKILL_NAME"
  fi
else
  result_skip "S02: No frontmatter to check"
fi

# ── S03: Signal phrase quality ────────────────────────────────────────
if [ -n "$FRONTMATTER" ]; then
  DESC=$(echo "$FRONTMATTER" | sed -n '/description:/,/^[a-z]/p' | sed '$d' | sed 's/description://' | tr ',' '\n' | sed 's/^[[:space:]]*//' | grep -v '^$' || true)
  S03_BAD=0
  S03_BAD_LIST=""
  while IFS= read -r phrase; do
    [ -z "$phrase" ] && continue
    WORD_COUNT=$(echo "$phrase" | wc -w)
    if [ "$WORD_COUNT" -gt 5 ]; then
      S03_BAD=$((S03_BAD + 1))
      S03_BAD_LIST+="  - '$phrase' ($WORD_COUNT words)\n"
    fi
  done <<< "$DESC"
  if [ "$S03_BAD" -eq 0 ]; then
    result_pass "S03: Signal phrases within length limits"
  else
    result_warn "S03: $S03_BAD signal phrase(s) exceed 5 words" "$(echo -e "$S03_BAD_LIST")"
  fi
else
  result_skip "S03: No frontmatter to check"
fi

# ── S04: Opening paragraph ───────────────────────────────────────────
# First non-empty line after the title heading should be a paragraph
BODY=$(echo "$CONTENT" | sed '/^---$/,/^---$/d')
TITLE_LINE=$(echo "$BODY" | grep -n '^# ' | head -1 | cut -d: -f1 || true)
if [ -n "$TITLE_LINE" ]; then
  AFTER_TITLE=$(echo "$BODY" | tail -n +"$((TITLE_LINE + 1))" | sed '/^$/d' | head -1 || true)
  if [ -n "$AFTER_TITLE" ] && ! echo "$AFTER_TITLE" | grep -qE '^(#|>|\||-)'; then
    result_pass "S04: Opening paragraph present"
  else
    result_warn "S04: No opening paragraph after title" "Add a human-readable paragraph explaining what, why, when"
  fi
else
  result_warn "S04: No title heading found" "SKILL.md should start with # Title"
fi

# ── S05: Shellcheck ──────────────────────────────────────────────────
SCRIPTS=$(find "$SKILL_DIR/scripts" -name '*.sh' -type f 2>/dev/null || true)
if [ -z "$SCRIPTS" ]; then
  result_skip "S05: No .sh scripts found"
else
  if command -v shellcheck &>/dev/null; then
    S05_FAIL=0
    S05_DETAILS=""
    while IFS= read -r script; do
      SHORT="$(basename "$script")"
      ERRORS=$(shellcheck -S warning "$script" 2>&1 | grep -c 'SC[0-9]' || true)
      if [ "$ERRORS" -gt 0 ]; then
        S05_FAIL=$((S05_FAIL + 1))
        S05_DETAILS+="  - $SHORT: $ERRORS issue(s)\n"
      fi
    done <<< "$SCRIPTS"
    if [ "$S05_FAIL" -eq 0 ]; then
      result_pass "S05: Shellcheck passes on all scripts"
    else
      result_warn "S05: Shellcheck issues in $S05_FAIL script(s)" "$(echo -e "$S05_DETAILS")"
    fi
  else
    result_skip "S05: shellcheck not installed"
  fi
fi

# ── S06: Value consistency (simplified) ──────────────────────────────
# Check for port numbers in scripts vs SKILL.md
result_skip "S06: Value consistency — manual review recommended"

echo ""
echo "P2: Autonomous & Currency"

# ── S07: Referenced commands exist ────────────────────────────────────
if [ -n "$SCRIPTS" ]; then
  S07_MISSING=0
  S07_DETAILS=""
  while IFS= read -r script; do
    SHORT="$(basename "$script")"
    # Extract commands from explicit existence checks (command -v X or which X)
    # Only match standalone command checks, not inside comments
    CMDS=$(grep -v '^\s*#' "$script" 2>/dev/null \
      | grep -oP '(?<=command -v )[a-zA-Z][a-zA-Z0-9_-]*|(?<=which )[a-zA-Z][a-zA-Z0-9_-]*' \
      | sort -u || true)
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      if ! command -v "$cmd" &>/dev/null; then
        S07_MISSING=$((S07_MISSING + 1))
        S07_DETAILS+="  - $SHORT: '$cmd' not found\n"
      fi
    done <<< "$CMDS"
  done <<< "$SCRIPTS"
  if [ "$S07_MISSING" -eq 0 ]; then
    result_pass "S07: All explicitly checked commands exist"
  else
    result_warn "S07: $S07_MISSING command(s) not found on this host" "$(echo -e "$S07_DETAILS")"
  fi
else
  result_skip "S07: No scripts to check"
fi

# ── S08/S10: Referenced file paths exist ──────────────────────────────
# Check Supporting Files section for broken references
S08_MISSING=0
S08_DETAILS=""
# Extract file paths from Supporting Files section — match "- path →" pattern
# Strips backticks and leading/trailing whitespace
SUPPORTING=$(echo "$CONTENT" | sed -n '/^## Supporting Files/,/^## /p' \
  | grep -oP '^\- \K[^\s]+(?= →)' | tr -d '`' || true)
if [ -n "$SUPPORTING" ]; then
  while IFS= read -r ref_path; do
    [ -z "$ref_path" ] && continue
    # Resolve relative to skill dir
    FULL_PATH="$SKILL_DIR/$ref_path"
    if [ ! -e "$FULL_PATH" ]; then
      S08_MISSING=$((S08_MISSING + 1))
      S08_DETAILS+="  - $ref_path\n"
    fi
  done <<< "$SUPPORTING"
fi
if [ "$S08_MISSING" -eq 0 ]; then
  result_pass "S08: All referenced file paths exist"
else
  result_fail "S08: $S08_MISSING referenced path(s) missing" "$(echo -e "$S08_DETAILS")"
fi

# ── S09: Supporting Files matches directory ──────────────────────────
ACTUAL_FILES=$(find "$SKILL_DIR" -type f \
  ! -name 'SKILL.md' ! -name 'CHANGELOG.md' ! -name '*.pyc' \
  ! -path '*/.cache/*' ! -path '*/__pycache__/*' \
  -printf '%P\n' 2>/dev/null | sort)
LISTED_FILES=$(echo "$CONTENT" | sed -n '/^## Supporting Files/,/^## /p' \
  | grep -oP '^\- .+?(?= →)' | sed 's/^- //' | sort || true)

if [ -z "$ACTUAL_FILES" ] && [ -z "$LISTED_FILES" ]; then
  result_pass "S09: No supporting files (none expected)"
elif [ -z "$LISTED_FILES" ] && [ -n "$ACTUAL_FILES" ]; then
  UNLISTED=$(echo "$ACTUAL_FILES" | wc -l)
  result_warn "S09: $UNLISTED file(s) in directory but no Supporting Files section" "Add ## Supporting Files section"
else
  result_pass "S09: Supporting Files section present"
fi

# ── S10: Covered by S08 ─────────────────────────────────────────────
# S10 is subsumed by S08 (path existence check)

echo ""
echo "P3: Traceable & Well-Formatted"

# ── S11: CHANGELOG exists and version matches ────────────────────────
CHANGELOG="$SKILL_DIR/CHANGELOG.md"
if [ -f "$CHANGELOG" ]; then
  CL_VERSION=$(grep -oP 'v\K[0-9]+\.[0-9]+\.[0-9]+' "$CHANGELOG" | head -1 || true)
  FM_VERSION=$(echo "$FRONTMATTER" | grep -oP 'version: "\K[^"]+' || true)
  if [ -n "$CL_VERSION" ] && [ -n "$FM_VERSION" ]; then
    if [ "$CL_VERSION" = "$FM_VERSION" ]; then
      result_pass "S11: CHANGELOG latest ($CL_VERSION) matches metadata ($FM_VERSION)"
    else
      result_warn "S11: CHANGELOG latest ($CL_VERSION) != metadata ($FM_VERSION)" "Bump one to match"
    fi
  else
    result_warn "S11: Could not extract versions to compare" "Check CHANGELOG and frontmatter format"
  fi
else
  result_warn "S11: No CHANGELOG.md" "Create CHANGELOG.md with at least a v1.0.0 entry"
fi

# ── S12: Markdown well-formed ────────────────────────────────────────
# Check for unclosed code blocks (triple backtick at start of line)
OPEN_FENCES=$(echo "$CONTENT" | grep -cP '^```' || true)
if [ $((OPEN_FENCES % 2)) -eq 0 ]; then
  result_pass "S12: Markdown code blocks balanced ($OPEN_FENCES fences)"
else
  result_info "S12: Odd number of code fences ($OPEN_FENCES) — possible unclosed block"
fi

echo ""
echo "P4: Verifiable Specification & Test"

# ── S13: Specification section ────────────────────────────────────────
if echo "$CONTENT" | grep -qiP '^## (Specification|Spec)\b'; then
  SPEC_IDS=$(echo "$CONTENT" | grep -oP '\bS[0-9]+\b' | sort -u | wc -l)
  result_pass "S13: Specification section present ($SPEC_IDS spec IDs found)"
else
  result_warn "S13: No Specification section" "Add ## Specification with verifiable items (S1, S2...)"
fi

# ── S14: Tests section ───────────────────────────────────────────────
if echo "$CONTENT" | grep -qiP '^## Tests?\b'; then
  TEST_IDS=$(echo "$CONTENT" | grep -oP '\bT[0-9]+\b' | sort -u | wc -l)
  result_pass "S14: Tests section present ($TEST_IDS test IDs found)"
else
  result_warn "S14: No Tests section" "Add ## Tests with testcases mapped to spec IDs"
fi

echo ""
echo "P5: Security & Trust Boundary"

# ── S15: Hardcoded secrets ────────────────────────────────────────────
S15_FOUND=0
S15_DETAILS=""
if [ -n "$SCRIPTS" ]; then
  while IFS= read -r script; do
    SHORT="$(basename "$script")"
    # Look for common secret patterns (API keys, tokens, passwords)
    MATCHES=$(grep -nP '(api[_-]?key|secret|password|token)\s*[:=]\s*["\x27][^"\x27]{8,}' "$script" 2>/dev/null \
      | grep -v '#.*api[_-]?key\|#.*secret\|#.*password\|#.*token' || true)
    if [ -n "$MATCHES" ]; then
      S15_FOUND=$((S15_FOUND + 1))
      S15_DETAILS+="  - $SHORT:\n$(echo "$MATCHES" | sed 's/^/      /')\n"
    fi
  done <<< "$SCRIPTS"
fi
if [ "$S15_FOUND" -eq 0 ]; then
  result_pass "S15: No hardcoded secrets detected"
else
  result_fail "S15: Possible hardcoded secrets in $S15_FOUND script(s)" "$(echo -e "$S15_DETAILS")"
fi

# ── S16: eval/source of untrusted input ──────────────────────────────
S16_FOUND=0
S16_DETAILS=""
if [ -n "$SCRIPTS" ]; then
  while IFS= read -r script; do
    SHORT="$(basename "$script")"
    # Look for eval with variable expansion (not eval "$(known_command)")
    MATCHES=$(grep -nP '^\s*eval\s+[^#]' "$script" 2>/dev/null || true)
    if [ -n "$MATCHES" ]; then
      S16_FOUND=$((S16_FOUND + 1))
      S16_DETAILS+="  - $SHORT: uses eval\n"
    fi
  done <<< "$SCRIPTS"
fi
if [ "$S16_FOUND" -eq 0 ]; then
  result_pass "S16: No eval of untrusted input"
else
  result_fail "S16: $S16_FOUND script(s) use eval" "$(echo -e "$S16_DETAILS")Review for untrusted input"
fi

echo ""
echo "P6: Context Economy"

# ── S17: SKILL.md line count ─────────────────────────────────────────
LINE_COUNT=$(echo "$CONTENT" | wc -l)
if [ "$LINE_COUNT" -le 300 ]; then
  result_pass "S17: SKILL.md is $LINE_COUNT lines (≤300)"
elif [ "$LINE_COUNT" -le 500 ]; then
  result_warn "S17: SKILL.md is $LINE_COUNT lines (>300)" "Consider extracting to references/"
else
  result_warn "S17: SKILL.md is $LINE_COUNT lines (>500)" "Extract reference content or split skill"
fi

# ── S18: References section if references/ exists ─────────────────────
if [ -d "$SKILL_DIR/references" ]; then
  if echo "$CONTENT" | grep -qiP '^## References?\b'; then
    result_pass "S18: References section exists for references/ directory"
  else
    result_warn "S18: references/ directory exists but no ## References section" "Add ## References linking to files"
  fi
else
  result_pass "S18: No references/ directory (section not required)"
fi

echo ""
echo "P7: Error Contract"

# ── S19: Semantic exit codes ──────────────────────────────────────────
if [ -n "$SCRIPTS" ]; then
  S19_BAD=0
  S19_DETAILS=""
  while IFS= read -r script; do
    SHORT="$(basename "$script")"
    # Find exit statements with non-standard codes
    BAD_EXITS=$(grep -nP '^\s*exit\s+[^0-3$"\x27 ]' "$script" 2>/dev/null \
      | grep -vP 'exit\s+\$' || true)
    if [ -n "$BAD_EXITS" ]; then
      S19_BAD=$((S19_BAD + 1))
      S19_DETAILS+="  - $SHORT: non-standard exit codes\n$(echo "$BAD_EXITS" | sed 's/^/      /')\n"
    fi
  done <<< "$SCRIPTS"
  if [ "$S19_BAD" -eq 0 ]; then
    result_pass "S19: Scripts use standard exit codes (0/1/2/3)"
  else
    result_warn "S19: $S19_BAD script(s) use non-standard exit codes" "$(echo -e "$S19_DETAILS")"
  fi
else
  result_skip "S19: No scripts to check"
fi

# ── S20: Error Handling table ─────────────────────────────────────────
if [ -n "$SCRIPTS" ]; then
  if echo "$CONTENT" | grep -qiP '^## Error Handling|^### Error Handling'; then
    result_pass "S20: Error Handling section exists"
  else
    result_warn "S20: No Error Handling section" "Add ## Error Handling with idempotency table"
  fi
else
  result_skip "S20: No scripts (error handling not applicable)"
fi

# ── S21: Troubleshooting table ────────────────────────────────────────
if [ -n "$SCRIPTS" ]; then
  if echo "$CONTENT" | grep -qiP '^## Troubleshooting|^### Troubleshooting'; then
    result_pass "S21: Troubleshooting section exists"
  else
    result_warn "S21: No Troubleshooting section" "Add ## Troubleshooting with symptom/cause/fix table"
  fi
else
  result_skip "S21: No scripts (troubleshooting not applicable)"
fi

# ── S22: Privilege gates ──────────────────────────────────────────────
if [ -n "$SCRIPTS" ]; then
  SUDO_SCRIPTS=""
  while IFS= read -r script; do
    if grep -qP '\bsudo\b' "$script" 2>/dev/null; then
      SHORT="$(basename "$script")"
      if grep -qP 'exit\s+3' "$script" 2>/dev/null; then
        : # Has exit 3 — correct
      else
        SUDO_SCRIPTS+="  - $SHORT: uses sudo but no exit 3 gate\n"
      fi
    fi
  done <<< "$SCRIPTS"
  if [ -z "$SUDO_SCRIPTS" ]; then
    result_pass "S22: Privilege gates correct (or no sudo usage)"
  else
    result_warn "S22: Scripts use sudo without exit 3 gate" "$(echo -e "$SUDO_SCRIPTS")"
  fi
else
  result_skip "S22: No scripts to check"
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Skill Eval Summary: $SKILL_NAME ==="
echo "Pass: $PASS | Fail: $FAIL | Warn: $WARN | Info: $INFO | Skip: $SKIP"

if [ -n "$DETAILS" ]; then
  echo ""
  echo "=== Details ==="
  echo -e "$DETAILS"
fi

exit "$FAIL"
