#!/usr/bin/env bash
# agentfs-behavior.sh — Layer 2: Behavioral Assertions
#
# Usage: bash agentfs-behavior.sh [TARGET_DIR]
#
#   TARGET_DIR   Directory containing .agents/ (default: .)
#
# Runs 5 behavioral checks that require accumulated evidence.
# Checks without sufficient evidence report N/A.
# No LLM required. Exit code 0 = all pass/N/A, non-zero = failures found.

set -euo pipefail

TARGET="${1:-.}"
TARGET="$(cd "$TARGET" && pwd)"
AGENTS_DIR="$TARGET/.agents"

PASS=0
FAIL=0
WARN=0
NA=0
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

result_na() {
  NA=$((NA + 1))
  echo "  [--] $1"
}

# ── Pre-check ────────────────────────────────────────────────────────
if [ ! -d "$AGENTS_DIR" ]; then
  echo "ERROR: No .agents/ directory at $TARGET"
  exit 1
fi

# Detect git availability
GIT_AVAILABLE=false
GIT_COMMIT_COUNT=0
if git -C "$TARGET" rev-parse --is-inside-work-tree &>/dev/null; then
  GIT_AVAILABLE=true
  GIT_COMMIT_COUNT=$(git -C "$TARGET" rev-list --count HEAD 2>/dev/null || echo 0)
fi

echo "=== Layer 2: Behavioral Assertions ==="
echo "Target: $TARGET"
echo "Git available: $GIT_AVAILABLE (commits: $GIT_COMMIT_COUNT)"
echo ""

# ── B1: Action-Log Correlation ───────────────────────────────────────
echo "B1: Action-Log Correlation"

LOG_FILE="$AGENTS_DIR/log.md"
LOG_ENTRY_COUNT=0
if [ -f "$LOG_FILE" ]; then
  LOG_ENTRY_COUNT=$(grep -cE '^- ' "$LOG_FILE" 2>/dev/null || echo 0)
fi

if ! $GIT_AVAILABLE || [ "$GIT_COMMIT_COUNT" -lt 2 ]; then
  result_na "B1: Action-Log Correlation — N/A (need git with ≥2 commits)"
elif [ "$LOG_ENTRY_COUNT" -lt 2 ]; then
  result_na "B1: Action-Log Correlation — N/A (need ≥2 log entries)"
else
  # Get files changed in git under .agents/ (excluding initial commit)
  GIT_CHANGED_FILES=$(git -C "$TARGET" log --pretty=format: --name-only \
    --diff-filter=ACMR -- .agents/ 2>/dev/null | sort -u | grep -v '^$' || true)

  if [ -z "$GIT_CHANGED_FILES" ]; then
    result_na "B1: Action-Log Correlation — N/A (no .agents/ changes in git)"
  else
    TOTAL_CHANGED=0
    LOGGED=0
    UNLOGGED=""

    while IFS= read -r changed_file; do
      [ -z "$changed_file" ] && continue
      TOTAL_CHANGED=$((TOTAL_CHANGED + 1))
      # Extract just the filename for matching
      fname="$(basename "$changed_file")"
      # Check if log.md mentions this file (by name or path)
      if grep -qF "$fname" "$LOG_FILE" 2>/dev/null || \
         grep -qF "$changed_file" "$LOG_FILE" 2>/dev/null; then
        LOGGED=$((LOGGED + 1))
      else
        UNLOGGED+="  - $changed_file\n"
      fi
    done <<< "$GIT_CHANGED_FILES"

    if [ "$TOTAL_CHANGED" -eq 0 ]; then
      result_na "B1: Action-Log Correlation — N/A (no changes to correlate)"
    elif [ "$LOGGED" -eq "$TOTAL_CHANGED" ]; then
      result_pass "B1: Action-Log Correlation — $LOGGED/$TOTAL_CHANGED changes logged"
    else
      PCTG=$(( (LOGGED * 100) / TOTAL_CHANGED ))
      if [ "$PCTG" -ge 80 ]; then
        result_warn "B1: Action-Log Correlation — $LOGGED/$TOTAL_CHANGED ($PCTG%) logged" \
          "B1 Details" "Unlogged changes:\n$(echo -e "$UNLOGGED")"
      else
        result_fail "B1: Action-Log Correlation — $LOGGED/$TOTAL_CHANGED ($PCTG%) logged" \
          "B1 Details" "Unlogged changes:\n$(echo -e "$UNLOGGED")"
      fi
    fi
  fi
fi

# ── B2: Log-Git Timestamp Alignment ─────────────────────────────────
echo "B2: Log-Git Timestamp Alignment"

if ! $GIT_AVAILABLE || [ "$GIT_COMMIT_COUNT" -lt 2 ]; then
  result_na "B2: Log-Git Timestamp Alignment — N/A (need git with ≥2 commits)"
elif [ "$LOG_ENTRY_COUNT" -lt 2 ]; then
  result_na "B2: Log-Git Timestamp Alignment — N/A (need ≥2 log entries)"
else
  # Extract log.md timestamps
  LOG_TIMESTAMPS=()
  while IFS= read -r line; do
    ts="$(echo "$line" | grep -oP '(?<=^## )\d{4}-\d{2}-\d{2} \d{2}:\d{2}' || true)"
    [ -n "$ts" ] && LOG_TIMESTAMPS+=("$ts")
  done < "$LOG_FILE"

  # Get git commit timestamps for .agents/ changes
  GIT_TIMESTAMPS=$(git -C "$TARGET" log --format='%ai' -- .agents/ 2>/dev/null | \
    sed 's/\([0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\) \([0-9]\{2\}:[0-9]\{2\}\).*/\1 \2/' | \
    sort -u || true)

  if [ ${#LOG_TIMESTAMPS[@]} -eq 0 ] || [ -z "$GIT_TIMESTAMPS" ]; then
    result_na "B2: Log-Git Timestamp Alignment — N/A (insufficient timestamps)"
  else
    ALIGNED=0
    MISALIGNED=0
    MISALIGNED_LIST=""

    for log_ts in "${LOG_TIMESTAMPS[@]}"; do
      # Convert to epoch for ±10 minute comparison
      log_epoch=$(date -d "$log_ts" +%s 2>/dev/null || echo 0)
      [ "$log_epoch" -eq 0 ] && continue

      found=false
      while IFS= read -r git_ts; do
        [ -z "$git_ts" ] && continue
        git_epoch=$(date -d "$git_ts" +%s 2>/dev/null || echo 0)
        [ "$git_epoch" -eq 0 ] && continue
        diff=$(( log_epoch - git_epoch ))
        [ "$diff" -lt 0 ] && diff=$(( -diff ))
        if [ "$diff" -le 600 ]; then  # ±10 minutes
          found=true
          break
        fi
      done <<< "$GIT_TIMESTAMPS"

      if $found; then
        ALIGNED=$((ALIGNED + 1))
      else
        MISALIGNED=$((MISALIGNED + 1))
        MISALIGNED_LIST+="  - log.md entry at $log_ts has no git commit within ±10min\n"
      fi
    done

    TOTAL_CHECKED=$((ALIGNED + MISALIGNED))
    if [ "$MISALIGNED" -eq 0 ]; then
      result_pass "B2: Log-Git Timestamp Alignment — $ALIGNED/$TOTAL_CHECKED aligned"
    else
      result_warn "B2: Log-Git Timestamp Alignment — $MISALIGNED/$TOTAL_CHECKED misaligned" \
        "B2 Details" "$(echo -e "$MISALIGNED_LIST")"
    fi
  fi
fi

# ── B3: Scope Leakage ────────────────────────────────────────────────
echo "B3: Scope Leakage"

USER_AGENTS="$HOME/.agents"
USER_GIT_AVAILABLE=false
if git -C "$USER_AGENTS" rev-parse --is-inside-work-tree &>/dev/null; then
  USER_GIT_AVAILABLE=true
fi

if ! $GIT_AVAILABLE || ! $USER_GIT_AVAILABLE; then
  result_na "B3: Scope Leakage — N/A (need git in both PROJECT and USER scope)"
else
  # Check if any PROJECT git commits happened at the same time as USER git commits
  # This is a simplified heuristic: look for commits within ±2 minutes of each other
  PROJECT_COMMIT_TIMES=$(git -C "$TARGET" log --format='%at' -- .agents/ 2>/dev/null | head -50)
  USER_COMMIT_TIMES=$(git -C "$USER_AGENTS" log --format='%at' 2>/dev/null | head -50)

  if [ -z "$PROJECT_COMMIT_TIMES" ] || [ -z "$USER_COMMIT_TIMES" ]; then
    result_na "B3: Scope Leakage — N/A (insufficient commit history)"
  else
    LEAKS=0
    LEAK_LIST=""
    while IFS= read -r pt; do
      [ -z "$pt" ] && continue
      while IFS= read -r ut; do
        [ -z "$ut" ] && continue
        diff=$(( pt - ut ))
        [ "$diff" -lt 0 ] && diff=$(( -diff ))
        if [ "$diff" -le 120 ]; then  # ±2 minutes
          LEAKS=$((LEAKS + 1))
          pt_human=$(date -d "@$pt" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$pt")
          LEAK_LIST+="  - Simultaneous commits at ~$pt_human (PROJECT + USER)\n"
          break
        fi
      done <<< "$USER_COMMIT_TIMES"
    done <<< "$PROJECT_COMMIT_TIMES"

    if [ "$LEAKS" -eq 0 ]; then
      result_pass "B3: Scope Leakage — no simultaneous cross-scope commits detected"
    else
      # This is a warning, not a fail — simultaneous commits aren't necessarily wrong
      # (e.g., skill-merge legitimately touches both scopes)
      result_warn "B3: Scope Leakage — $LEAKS simultaneous cross-scope commit(s)" \
        "B3 Details" "$(echo -e "$LEAK_LIST")\n  Note: skill-merge and similar tools legitimately modify both scopes."
    fi
  fi
fi

# ── B4: Idempotency Spot-Check ───────────────────────────────────────
echo "B4: Idempotency Spot-Check"

# Find executable scripts in project skills
EXEC_SCRIPTS=$(find "$AGENTS_DIR/skills" -name '*.sh' -type f 2>/dev/null | head -1)

if [ -z "$EXEC_SCRIPTS" ]; then
  result_na "B4: Idempotency Spot-Check — N/A (no executable skill scripts found)"
else
  # We only report availability here — actual idempotency testing
  # requires running the skill, which could have side effects.
  # The eval skill instructs the agent to perform this manually.
  result_na "B4: Idempotency Spot-Check — N/A (manual verification required)"
  # Note: The SKILL.md instructs the agent to:
  #   1. md5sum the .agents/ tree
  #   2. Re-run the skill
  #   3. md5sum again
  #   4. Compare
  # This is intentionally not automated to avoid unintended side effects.
fi

# ── B5: Rule-in-Memory Heuristic ─────────────────────────────────────
echo "B5: Rule-in-Memory Heuristic"

# Collect all MEMORY.md files (default agent + profiles)
MEMORY_FILES=()
[ -f "$AGENTS_DIR/memories/MEMORY.md" ] && MEMORY_FILES+=("$AGENTS_DIR/memories/MEMORY.md")
while IFS= read -r pmem; do
  MEMORY_FILES+=("$pmem")
done < <(find "$AGENTS_DIR/profiles" -path '*/memories/MEMORY.md' -type f 2>/dev/null)

if [ ${#MEMORY_FILES[@]} -eq 0 ]; then
  result_na "B5: Rule-in-Memory Heuristic — N/A (no MEMORY.md files found)"
else
  B5_TOTAL_ENTRIES=0
  B5_FLAGGED=0
  B5_FLAGGED_LIST=""

  for memfile in "${MEMORY_FILES[@]}"; do
    # Count actual entries (lines starting with - that aren't comments)
    entry_count=$(grep -cE '^\s*-\s+[^<]' "$memfile" 2>/dev/null || true)
    entry_count=${entry_count:-0}
    entry_count=$(echo "$entry_count" | tr -d '[:space:]')
    B5_TOTAL_ENTRIES=$((B5_TOTAL_ENTRIES + entry_count))

    # Check for rule-like language
    matches=$(grep -niE '^\s*-\s+.*(\b(always|never|must|shall|enforce|do not|don.t|ensure that)\b)' \
      "$memfile" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      short="$(echo "$memfile" | sed "s|$TARGET/||")"
      while IFS= read -r match; do
        B5_FLAGGED=$((B5_FLAGGED + 1))
        B5_FLAGGED_LIST+="  - $short: $match\n"
      done <<< "$matches"
    fi
  done

  if [ "$B5_TOTAL_ENTRIES" -eq 0 ]; then
    result_na "B5: Rule-in-Memory Heuristic — N/A (MEMORY.md files have no entries)"
  elif [ "$B5_FLAGGED" -eq 0 ]; then
    result_pass "B5: Rule-in-Memory Heuristic — 0 rule-like entries in $B5_TOTAL_ENTRIES total"
  else
    result_warn "B5: Rule-in-Memory Heuristic — $B5_FLAGGED entry(ies) flagged" \
      "B5 Details" "$(echo -e "$B5_FLAGGED_LIST")\n  These entries contain imperative language and may belong in AGENTS.md as guardrails."
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "=== Layer 2 Summary ==="
TOTAL=$((PASS + FAIL + WARN + NA))
echo "Pass: $PASS | Fail: $FAIL | Warn: $WARN | N/A: $NA  (of $TOTAL)"

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
