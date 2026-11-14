#!/usr/bin/env bash
# test-merge-log-entry.sh — Validate merge-log-entry.sh guards.
#
# Covers the defect classes found in ~/.agents/log.md on 2026-11-13:
#   raw <tag> HTML injection, missing bullet prefix, embedded newline,
#   missing (path) suffix, second-header injection, comment loss.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MERGE="$SCRIPT_DIR/merge-log-entry.sh"

PASSED=0
FAILED=0

pass() { echo "  ✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "  ❌ $1 — $2"; FAILED=$((FAILED + 1)); }

assert_rc() { # label expected actual
  [[ "$3" -eq "$2" ]] && pass "$1" || fail "$1" "expected exit $2, got $3"
}
assert_contains() { # label pattern text
  grep -qE "$2" <<< "$3" && pass "$1" || fail "$1" "missing pattern: $2"
}
assert_not_contains() { # label pattern text
  grep -qE "$2" <<< "$3" && fail "$1" "unexpected pattern: $2" || pass "$1"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

fresh_log() { # path
  printf '# Directory Update Log\n\n<!-- Append-only. Newest entries at top. -->\n\n## 2020-01-01 00:00\n- Old entry (x.md)\n' > "$1"
}

# ── Test 1: raw <tag> is wrapped in backticks ──────────────────────
echo "=== Test 1: Raw HTML tag auto-fixed ==="
L="$TMP/t1.md"; fresh_log "$L"
OUT=$(bash "$MERGE" "$L" "- Change template to <computed> (skills/x/SKILL.md)" 2>&1); rc=$?
assert_rc "Exits 0" 0 "$rc"
assert_contains "Warns about the raw tag" "Raw <tag> wrapped" "$OUT"
assert_contains "Tag is backticked in the file" '`<computed>`' "$(cat "$L")"
assert_not_contains "No bare tag remains" '[^`]<computed>' "$(cat "$L")"

# ── Test 2: tag already inside backticks is left alone ─────────────
echo "=== Test 2: Already-backticked tag untouched ==="
L="$TMP/t2.md"; fresh_log "$L"
bash "$MERGE" "$L" '- Route to `.traces/<skill>.jsonl` (scripts/trace-lib.sh)' >/dev/null 2>&1
assert_not_contains "No double backticks" '``' "$(cat "$L")"
assert_contains "Entry intact" '`\.traces/<skill>\.jsonl`' "$(cat "$L")"

# ── Test 3: line without a bullet is rejected ──────────────────────
echo "=== Test 3: Missing bullet prefix rejected ==="
L="$TMP/t3.md"; fresh_log "$L"
BEFORE=$(cat "$L")
OUT=$(bash "$MERGE" "$L" "No bullet prefix here (x.md)" 2>&1); rc=$?
assert_rc "Exits 2" 2 "$rc"
assert_contains "Explains the rule" "must start with" "$OUT"
[[ "$(cat "$L")" == "$BEFORE" ]] && pass "Log unmodified" || fail "Log unmodified" "file changed"

# ── Test 4: indented sub-bullets are allowed ───────────────────────
echo "=== Test 4: Nested sub-bullets accepted ==="
L="$TMP/t4.md"; fresh_log "$L"
OUT=$(bash "$MERGE" "$L" '- Parent entry (skills/x/SKILL.md)\n  - child detail' 2>&1); rc=$?
assert_rc "Exits 0" 0 "$rc"
assert_contains "Child line present" "^  - child detail$" "$(cat "$L")"

# ── Test 5: embedded literal newline rejected via the bullet rule ──
echo "=== Test 5: Embedded newline rejected ==="
L="$TMP/t5.md"; fresh_log "$L"
OUT=$(bash "$MERGE" "$L" "- Broken $(printf 'one\ntwo') tail (x.md)" 2>&1); rc=$?
assert_rc "Exits 2" 2 "$rc"
assert_not_contains "Orphan line not written" "^two tail" "$(cat "$L")"

# ── Test 6: missing (path) warns but succeeds ──────────────────────
echo "=== Test 6: Missing path suffix warns ==="
L="$TMP/t6.md"; fresh_log "$L"
OUT=$(bash "$MERGE" "$L" "- No path at all" 2>&1); rc=$?
assert_rc "Exits 0" 0 "$rc"
assert_contains "Warns" "no trailing \(path\)" "$OUT"

# ── Test 7: malformed header refused (no second header injected) ───
echo "=== Test 7: Malformed log header refused ==="
L="$TMP/t7.md"
printf 'r# Directory Update Log\n\n## 2020-01-01 00:00\n- Old (x.md)\n' > "$L"
OUT=$(bash "$MERGE" "$L" "- New entry (x.md)" 2>&1); rc=$?
assert_rc "Exits 1" 1 "$rc"
assert_contains "Names the bad first line" "does not start with" "$OUT"
[[ $(grep -c '# Directory Update Log' "$L") -eq 1 ]] \
  && pass "No second header injected" || fail "No second header injected" "header duplicated"

# ── Test 8: Append-only comment preserved past head -3 ─────────────
echo "=== Test 8: Comment preserved below line 3 ==="
L="$TMP/t8.md"
printf '# Directory Update Log\n\n\n\n<!-- Append-only. Newest entries at top. -->\n\n## 2020-01-01 00:00\n- Old (x.md)\n' > "$L"
bash "$MERGE" "$L" "- New (x.md)" >/dev/null 2>&1
[[ $(grep -c 'Append-only' "$L") -eq 1 ]] \
  && pass "Comment retained exactly once" || fail "Comment retained exactly once" "count=$(grep -c 'Append-only' "$L")"

# ── Test 9: lock file survives (concurrency safety) ────────────────
echo "=== Test 9: Lock file not deleted ==="
L="$TMP/t9.md"; fresh_log "$L"
bash "$MERGE" "$L" "- Entry one (x.md)" >/dev/null 2>&1
[[ -f "$L.lock" ]] && pass "Lock file persists" || fail "Lock file persists" "lock removed — inode race possible"

# ── Test 10: newest-first ordering and idempotent heading merge ────
echo "=== Test 10: Ordering and heading merge ==="
L="$TMP/t10.md"; fresh_log "$L"
bash "$MERGE" "$L" "- First (x.md)"  >/dev/null 2>&1
bash "$MERGE" "$L" "- Second (x.md)" >/dev/null 2>&1
NEW_HEADS=$(grep -c "^## $(date '+%Y-%m-%d %H:%M')" "$L")
[[ "$NEW_HEADS" -eq 1 ]] && pass "Same-minute writes share one heading" \
  || fail "Same-minute writes share one heading" "found $NEW_HEADS headings"
[[ $(grep -n '^## ' "$L" | head -1 | cut -d: -f2) != "## 2020-01-01 00:00" ]] \
  && pass "New section is on top" || fail "New section is on top" "old section first"
assert_contains "Old entry preserved" "Old entry \(x.md\)" "$(cat "$L")"

# ── Test 11: timestamp guard still active (regression) ─────────────
echo "=== Test 11: Leading timestamp still stripped ==="
L="$TMP/t11.md"; fresh_log "$L"
OUT=$(bash "$MERGE" "$L" "- 2026-11-13 20:20 Did a thing (x.md)" 2>&1)
assert_contains "Warns" "Leading timestamp removed" "$OUT"
assert_contains "Entry stored without the date" "^- Did a thing \(x.md\)$" "$(cat "$L")"

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "  ✅ All tests passed." || echo "  ❌ $FAILED test(s) failed."
exit $(( FAILED > 0 ? 1 : 0 ))
