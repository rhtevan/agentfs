#!/usr/bin/env bash
# test-pre-push-scan.sh — Validate pre-push-scan.sh catches all categories.
#
# Creates a temp git repo with planted sensitive data, stages it,
# and verifies the scan detects every category.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN_SCRIPT="$SCRIPT_DIR/pre-push-scan.sh"

PASSED=0
FAILED=0

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

run_scan() {
  # Capture output and exit code without || true swallowing the code
  local rc=0
  SCAN_OUTPUT=$(bash "$SCAN_SCRIPT" --mode cached 2>&1) || rc=$?
  SCAN_RC=$rc
}

assert_exit_code() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✅ $label (exit $actual)"
    PASSED=$((PASSED + 1))
  else
    echo "  ❌ $label — expected exit $expected, got $actual"
    FAILED=$((FAILED + 1))
  fi
}

# ── Setup temp repo ────────────────────────────────────────────────
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

cd "$TMP_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create initial commit so we can diff
echo "init" > init.txt
git add init.txt
git commit -q -m "init"

# ── Test 1: Clean file ─────────────────────────────────────────────
echo "=== Test 1: Clean file ==="
echo "hello world" > clean.txt
git add clean.txt
run_scan
RC=$SCAN_RC
assert_exit_code "Clean file exits 0" "0" "$RC"
assert_output_contains "Clean verdict" "ALL CLEAN" "$SCAN_OUTPUT"
git reset -q HEAD clean.txt
rm -f clean.txt

# ── Test 2: Secrets ────────────────────────────────────────────────
echo "=== Test 2: Secrets detection ==="
cat > secrets.txt << 'EOF'
api_key = "sk-12345abcdef"
password: hunter2
authorization: Bearer tok_abc123
EOF
git add secrets.txt
run_scan
RC=$SCAN_RC
assert_exit_code "Secrets exits 1" "1" "$RC"
assert_output_contains "Detects secrets" "Secrets.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD secrets.txt
rm -f secrets.txt

# ── Test 3: Hardcoded user paths ───────────────────────────────────
echo "=== Test 3: Hardcoded paths ==="
CURRENT_USER=$(whoami)
echo "path = /home/$CURRENT_USER/projects/app" > paths.txt
git add paths.txt
run_scan
RC=$SCAN_RC
assert_exit_code "Hardcoded paths exits 1" "1" "$RC"
assert_output_contains "Detects hardcoded paths" "Hardcoded.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD paths.txt
rm -f paths.txt

# ── Test 4: IP addresses ───────────────────────────────────────────
echo "=== Test 4: IP addresses ==="
echo "server = 192.168.1.100" > ips.txt
git add ips.txt
run_scan
RC=$SCAN_RC
assert_exit_code "IP addresses exits 1" "1" "$RC"
assert_output_contains "Detects IPs" "IP address.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD ips.txt
rm -f ips.txt

# ── Test 5: Sensitive URLs ─────────────────────────────────────────
echo "=== Test 5: Sensitive URLs ==="
echo "endpoint = https://internal.corp.example.com/api" > urls.txt
git add urls.txt
run_scan
RC=$SCAN_RC
assert_exit_code "Sensitive URLs exits 1" "1" "$RC"
assert_output_contains "Detects sensitive URLs" "Sensitive.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD urls.txt
rm -f urls.txt

# ── Test 6: PII ────────────────────────────────────────────────────
echo "=== Test 6: PII detection ==="
cat > pii.txt << 'EOF'
contact: john.doe@example.com
phone: 555-123-4567
EOF
git add pii.txt
run_scan
RC=$SCAN_RC
assert_exit_code "PII exits 1" "1" "$RC"
assert_output_contains "Detects PII" "PII.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD pii.txt
rm -f pii.txt

# ── Test 7: README staleness notice ────────────────────────────────
echo "=== Test 7: README staleness ==="
mkdir -p skills
echo "new skill" > skills/test-skill.txt
git add skills/test-skill.txt
run_scan
assert_output_contains "README notice" "README Notice" "$SCAN_OUTPUT"
git reset -q HEAD skills/test-skill.txt
rm -rf skills

# ── Test 8: All categories in one file ─────────────────────────────
echo "=== Test 8: Multi-category detection ==="
cat > multi.txt << EOF
api_key = "secret123"
path = /home/$CURRENT_USER/data
server = 10.0.1.50
url = https://internal.example.com
email: test@company.com
EOF
git add multi.txt
run_scan
RC=$SCAN_RC
assert_exit_code "Multi-category exits 1" "1" "$RC"
assert_output_contains "Multi: secrets" "Secrets.*FOUND" "$SCAN_OUTPUT"
assert_output_contains "Multi: paths" "Hardcoded.*FOUND" "$SCAN_OUTPUT"
assert_output_contains "Multi: IPs" "IP address.*FOUND" "$SCAN_OUTPUT"
assert_output_contains "Multi: URLs" "Sensitive.*FOUND" "$SCAN_OUTPUT"
assert_output_contains "Multi: PII" "PII.*FOUND" "$SCAN_OUTPUT"
git reset -q HEAD multi.txt
rm -f multi.txt

# ── Summary ────────────────────────────────────────────────────────
echo ""
echo "=== Summary ==="
echo "  Passed: $PASSED"
echo "  Failed: $FAILED"
[[ $FAILED -eq 0 ]] && echo "  ✅ All tests passed." || echo "  ❌ $FAILED test(s) failed."
exit $( [[ $FAILED -eq 0 ]] && echo 0 || echo 1 )
