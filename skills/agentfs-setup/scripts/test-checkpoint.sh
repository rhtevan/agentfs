#!/usr/bin/env bash
# test-checkpoint.sh — Validate checkpoint.sh capabilities.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHK_SCRIPT="$SCRIPT_DIR/checkpoint.sh"

PASSED=0
FAILED=0

assert_ok() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" -eq 0 ]]; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — exit $rc"
    FAILED=$((FAILED + 1))
  fi
}

assert_fail() {
  local label="$1"
  local rc="$2"
  if [[ "$rc" -ne 0 ]]; then
    echo "  ✅ $label (exit $rc)"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — expected non-zero exit"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local label="$1"
  local path="$2"
  if [[ -f "$path" ]]; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — file not found: $path"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_not_exists() {
  local label="$1"
  local path="$2"
  if [[ ! -f "$path" ]]; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — file should not exist: $path"
    FAILED=$((FAILED + 1))
  fi
}

assert_output_contains() {
  local label="$1"
  local pattern="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo "  ✅ $label"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — expected pattern: $pattern"
    FAILED=$((FAILED + 1))
  fi
}

# ── Setup temp project ─────────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

cd "$TMP_DIR"
mkdir -p .agents/memories
git init -q
git config user.email "test@test.com"
git config user.name "Test"
echo "init" > init.txt
git add init.txt .agents/
git commit -q -m "init"

# ── Test 1: Create checkpoint ──────────────────────────────────────
echo "=== Test 1: Create checkpoint ==="
echo "test content" > .agents/memories/MEMORY.md
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" create .agents/memories/MEMORY.md 2>&1) || rc=$?
assert_ok "Create exits 0" "$rc"
assert_file_exists "Checkpoint file created" ".agents/.checkpoint"
assert_output_contains "Reports file count" "Files recorded: 1" "$OUTPUT"

# Verify checkpoint content has hash
rc=0
CONTENT=$(cat .agents/.checkpoint)
assert_output_contains "Contains sha256 hash" "[a-f0-9]{64}" "$CONTENT"
assert_output_contains "Contains filename" "MEMORY.md" "$CONTENT"

# ── Test 2: Check with active checkpoint ───────────────────────────
echo "=== Test 2: Check active checkpoint ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" check 2>&1) || rc=$?
assert_fail "Check exits non-zero when checkpoint exists" "$rc"
assert_output_contains "Reports non-empty checkpoint" "Non-empty checkpoint" "$OUTPUT"

# ── Test 3: Clear checkpoint ───────────────────────────────────────
echo "=== Test 3: Clear checkpoint ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" clear 2>&1) || rc=$?
assert_ok "Clear exits 0" "$rc"
assert_file_not_exists "Checkpoint file removed" ".agents/.checkpoint"

# ── Test 4: Check with no checkpoint ───────────────────────────────
echo "=== Test 4: Check clean state ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" check 2>&1) || rc=$?
assert_ok "Check exits 0 when clean" "$rc"
assert_output_contains "Reports clean" "No pending checkpoint" "$OUTPUT"

# ── Test 5: Create with non-existent file ──────────────────────────
echo "=== Test 5: Non-existent file ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" create /nonexistent/file.md 2>&1) || rc=$?
assert_ok "Create handles non-existent file" "$rc"
assert_output_contains "Records DOES_NOT_EXIST" "DOES_NOT_EXIST" "$(cat .agents/.checkpoint)"
bash "$CHK_SCRIPT" clear &>/dev/null

# ── Test 6: Backup untracked file ──────────────────────────────────
echo "=== Test 6: Backup untracked file ==="
echo "untracked content" > .agents/untracked.md
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" backup .agents/untracked.md 2>&1) || rc=$?
assert_ok "Backup exits 0" "$rc"
assert_output_contains "Reports backup" "Backed up untracked" "$OUTPUT"
# Check .bak file exists
BAK_COUNT=$(ls .agents/untracked.md.bak.* 2>/dev/null | wc -l)
if [[ "$BAK_COUNT" -ge 1 ]]; then
  echo "  ✅ Backup file created"
  PASSED=$((PASSED + 1))
else
  echo "  ❌ No .bak file found"
  FAILED=$((FAILED + 1))
fi

# ── Test 7: Backup git-tracked file (should skip) ─────────────────
echo "=== Test 7: Skip backup for tracked file ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" backup init.txt 2>&1) || rc=$?
assert_ok "Backup tracked exits 0" "$rc"
assert_output_contains "Reports no backup needed" "git-tracked.*no backup" "$OUTPUT"

# ── Test 8: Usage error ────────────────────────────────────────────
echo "=== Test 8: Usage errors ==="
rc=0
OUTPUT=$(bash "$CHK_SCRIPT" 2>&1) || rc=$?
assert_fail "No args exits non-zero" "$rc"

rc=0
OUTPUT=$(bash "$CHK_SCRIPT" create 2>&1) || rc=$?
assert_fail "Create with no files exits non-zero" "$rc"

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "  ✅ All tests passed." || echo "  ❌ $FAILED test(s) failed."
exit $(( FAILED > 0 ? 1 : 0 ))
