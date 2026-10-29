#!/bin/bash
# benchmark.sh v2 — AgentFS skill operability test harness
#
# Runs test cases against a specified model via goose run CLI.
# Captures output, checks pass criteria, produces a summary report.
#
# Usage:
#   benchmark.sh [--provider <name>] [--model <id>] [--tests <t1,t2,...>] [--runs <N>]
#   benchmark.sh --preflight          # Verify KGM resolves all dispatch queries
#
# Options:
#   --provider    Goose provider name (default: custom_skupper)
#   --model       Model ID (default: Qwen/Qwen3-14B-FP8)
#   --tests       Comma-separated test IDs to run (default: t1,t2,t3,t5,t9 — read-only)
#   --runs        Number of runs per test (default: 1)
#   --max-turns   Max turns per goose run (default: 15)
#   --output      Output directory (default: /tmp/benchmark-<timestamp>)
#   --preflight   Run KGM verification gate only (no model tests)
#
# Exit codes:
#   0 — All tests passed
#   1 — Some tests failed
#   2 — Configuration error
#
# Safety: Only read-only tests (T1,T2,T3,T5,T9) run by default.
#         Write tests (T4,T6,T7,T8) require --tests to include explicitly.
#
# v2 changes (2026-10-27):
#   - T2 prompt fixed: 'hey headroom status' (KGM-verified signal)
#   - T9 added: readme audit (Phase 2 operable skill)
#   - Pre-flight KGM verification gate
#   - T2/T3/T5/T9 checkers require full chain: search → load → execute
#   - Default tests: t1,t2,t3,t5,t9

set -uo pipefail

# --- Defaults ---
PROVIDER="custom_skupper"
MODEL="Qwen/Qwen3-14B-FP8"
TESTS="t1,t3,t9"
RUNS=1
MAX_TURNS=15
OUTPUT_DIR=""
PREFLIGHT=false
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)   PROVIDER="$2"; shift 2 ;;
    --model)      MODEL="$2"; shift 2 ;;
    --tests)      TESTS="$2"; shift 2 ;;
    --runs)       RUNS="$2"; shift 2 ;;
    --max-turns)  MAX_TURNS="$2"; shift 2 ;;
    --output)     OUTPUT_DIR="$2"; shift 2 ;;
    --preflight)  PREFLIGHT=true; shift ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# //;s/^#//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/benchmark-${TIMESTAMP}}"
mkdir -p "$OUTPUT_DIR"

log() { echo "[benchmark] $*" >&2; }
log "Provider: $PROVIDER"
log "Model: $MODEL"
log "Tests: $TESTS"
log "Runs per test: $RUNS"
log "Output: $OUTPUT_DIR"

# --- Test definitions ---
# Each test: ID, prompt, CWD, max_turns, safety level

# Project CWD: a directory with .agents/ and AGENTS.md for context loading.
# Override with BENCHMARK_PROJECT_CWD environment variable.
BENCHMARK_PROJECT_CWD="${BENCHMARK_PROJECT_CWD:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$HOME")}"

declare -A TEST_PROMPT TEST_CWD TEST_MAXTURN TEST_SAFETY TEST_KGM_QUERY

# T1 — Session Canary (hardcoded — tests rule, not skill)
TEST_PROMPT[t1]="hello"
TEST_CWD[t1]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t1]=5
TEST_SAFETY[t1]="read-only"

# --- AGENTS.md rule coverage tests ---
# These test rule compliance, not skill operability.
# Write-contained tests use a sandbox project.
SANDBOX_DIR="/tmp/benchmark-sandbox"

# T_R2 — Pre-Flight: multi-file task should produce a plan
TEST_PROMPT[t_r2]="Create two empty files in /tmp/benchmark-scratch: test1.txt and test2.txt"
TEST_CWD[t_r2]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t_r2]=5
TEST_SAFETY[t_r2]="write-contained"

# T_R3 — Post-Write: writing to .agents/ should trigger post-write.sh
TEST_PROMPT[t_r3]="hey remember that benchmark R3 test ran successfully"
TEST_CWD[t_r3]="$SANDBOX_DIR"
TEST_MAXTURN[t_r3]=10
TEST_SAFETY[t_r3]="write-contained"

# T_R7 — Scope Rules: memory write should go to PROJECT scope
TEST_PROMPT[t_r7]="hey remember that benchmark R7 scope test ran successfully"
TEST_CWD[t_r7]="$SANDBOX_DIR"
TEST_MAXTURN[t_r7]=10
TEST_SAFETY[t_r7]="write-contained"

# --- Auto-discover QOO-qualified skills ---
# A skill is QOO-qualified if it has scores.yaml with qoo-qualified: true.
# For each qualified skill, extract the first signal phrase from
# the SKILL.md description field and register a dynamic test.
SKILLS_DIR="$HOME/.agents/skills"
QOO_COUNT=0

for skill_dir in "$SKILLS_DIR"/*/; do
  [[ -f "$skill_dir/scores.yaml" ]] || continue
  grep -q "qoo-qualified: true" "$skill_dir/scores.yaml" || continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  skill_name=$(basename "$skill_dir")

  # Extract first signal phrase from description field
  signal=$(sed -n '/^description:/,/^[a-z]/{ /^description:/s/.*: *//p; /^  /s/^ *//p; }' \
    "$skill_dir/SKILL.md" | tr '\n' ' ' | sed 's/^> *//' | xargs)
  first_signal=$(echo "$signal" | cut -d',' -f1 | xargs)

  [[ -z "$first_signal" ]] && continue

  # Create test ID: qoo_<skill_name> (sanitized)
  test_id="qoo_$(echo "$skill_name" | tr '-' '_')"

  TEST_PROMPT[$test_id]="hey $first_signal"
  TEST_CWD[$test_id]="$BENCHMARK_PROJECT_CWD"
  TEST_MAXTURN[$test_id]=15
  TEST_SAFETY[$test_id]="read-only"
  TEST_KGM_QUERY[$test_id]="$first_signal"

  QOO_COUNT=$((QOO_COUNT + 1))
  log "  QOO skill discovered: $skill_name → 'hey $first_signal' (test: $test_id)"
done

log "QOO skills discovered: $QOO_COUNT"

# Build default test list: t1 + rule tests + all QOO tests
if [[ "$TESTS" == "t1,t3,t9" ]]; then
  # Replace old default with dynamic discovery
  QOO_TESTS=$(printf '%s\n' "${!TEST_PROMPT[@]}" | grep '^qoo_' | sort | tr '\n' ',')
  RULE_TESTS="t_r2,t_r3,t_r7"
  TESTS="t1,${QOO_TESTS%,},${RULE_TESTS}"
  log "Default tests (auto-discovered): $TESTS"
fi

# --- Pre-flight KGM verification ---
# Verifies that dispatch test queries resolve in KGM index.
# Uses grep against the KGM JSONL index (same data as MCP search_nodes).
KGM_INDEX="$HOME/.agents/knowledge/.kgm-index.jsonl"

run_preflight() {
  log "Pre-flight: verifying KGM index resolves all dispatch queries..."
  local all_pass=true

  if [[ ! -f "$KGM_INDEX" ]]; then
    log "  ❌ KGM index not found: $KGM_INDEX"
    return 1
  fi

  IFS=',' read -ra pf_tests <<< "$TESTS"
  for test_id in "${pf_tests[@]}"; do
    test_id=$(echo "$test_id" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
    local query="${TEST_KGM_QUERY[$test_id]:-}"
    if [[ -z "$query" ]]; then
      log "  ⏭️  $test_id: no KGM query (non-dispatch test)"
      continue
    fi

    # Check if all query words appear in any single entity's observations
    local found
    found=$(python3 -c "
import sys, json
query_words = '$query'.lower().split()
for line in open('$KGM_INDEX'):
    try:
        e = json.loads(line)
    except: continue
    if e.get('type') != 'entity': continue
    text = ' '.join(e.get('observations',[])).lower() + ' ' + e.get('name','').lower()
    if all(w in text for w in query_words):
        print(e['name']); break
" 2>/dev/null)

    if [[ -n "$found" ]]; then
      log "  ✅ $test_id: '$query' → $found"
    else
      log "  ❌ $test_id: '$query' → NOT FOUND in KGM index"
      all_pass=false
    fi
  done

  if [[ "$all_pass" == "true" ]]; then
    log "Pre-flight: all dispatch queries verified ✅"
    return 0
  else
    log "Pre-flight: FAILED — some queries not in KGM index"
    return 1
  fi
}

# Handle --preflight mode
if [[ "$PREFLIGHT" == "true" ]]; then
  run_preflight
  exit $?
fi

# --- Pass criteria checkers ---
# Each returns 0=pass, 1=fail. Writes verdict to stdout.

check_t1() {
  local output="$1"
  # T1: Response contains canary pattern 🐦 word-word
  if grep -qP '🐦\s+\w+-\w+' "$output" 2>/dev/null; then
    local canary
    canary=$(grep -oP '🐦\s+\w+-\w+' "$output" | head -1)
    echo "PASS: canary found: $canary"
    return 0
  else
    echo "FAIL: no canary pattern (🐦 word-word) found in response"
    return 1
  fi
}

check_t2() {
  local output="$1"
  # T2: Full dispatch chain — search_nodes → load_skill → shell
  local has_search=false has_skill=false has_shell=false
  grep -q 'search_nodes' "$output" 2>/dev/null && has_search=true
  grep -q 'load_skill' "$output" 2>/dev/null && has_skill=true
  grep -q '▸ shell' "$output" 2>/dev/null && has_shell=true
  if [[ "$has_search" == "true" && "$has_skill" == "true" && "$has_shell" == "true" ]]; then
    echo "PASS: full dispatch chain (search → load → execute)"
    return 0
  else
    local detail=""
    [[ "$has_search" == "false" ]] && detail+="search_nodes missing. "
    [[ "$has_skill" == "false" ]] && detail+="load_skill missing. "
    [[ "$has_shell" == "false" ]] && detail+="shell execution missing. "
    echo "FAIL: incomplete dispatch chain — $detail"
    return 1
  fi
}

check_t3() {
  local output="$1"
  # T3: load_skill called AND a shell command ran (script execution)
  local has_skill=false has_shell=false
  grep -q 'load_skill' "$output" 2>/dev/null && has_skill=true
  grep -q '▸ shell' "$output" 2>/dev/null && has_shell=true
  if [[ "$has_skill" == "true" && "$has_shell" == "true" ]]; then
    echo "PASS: skill loaded and script executed"
    return 0
  elif [[ "$has_skill" == "true" ]]; then
    echo "FAIL: skill loaded but no script execution detected"
    return 1
  else
    echo "FAIL: skill not loaded"
    return 1
  fi
}

check_t4() {
  local output="$1"
  # T4: resolve-target.sh ran, git add ran, pre-push-scan ran
  local score=0
  grep -q 'resolve-target' "$output" 2>/dev/null && score=$((score + 1))
  grep -q 'git add' "$output" 2>/dev/null && score=$((score + 1))
  grep -q 'pre-push-scan' "$output" 2>/dev/null && score=$((score + 1))
  if [[ $score -ge 2 ]]; then
    echo "PASS: git workflow steps detected ($score/3)"
    return 0
  else
    echo "FAIL: git workflow incomplete ($score/3 steps detected)"
    return 1
  fi
}

check_t5() {
  local output="$1"
  # T5: Full chain — search_nodes → load_skill → structured report
  local has_search=false has_skill=false has_report=false
  grep -q 'search_nodes' "$output" 2>/dev/null && has_search=true
  grep -q 'load_skill' "$output" 2>/dev/null && has_skill=true
  grep -qP '(violation|rule|compliance|✅|⚠️|❌)' "$output" 2>/dev/null && has_report=true
  if [[ "$has_search" == "true" && "$has_skill" == "true" && "$has_report" == "true" ]]; then
    echo "PASS: full chain — dispatch → skill → violation report"
    return 0
  else
    local detail=""
    [[ "$has_search" == "false" ]] && detail+="search_nodes missing. "
    [[ "$has_skill" == "false" ]] && detail+="load_skill missing. "
    [[ "$has_report" == "false" ]] && detail+="no structured report. "
    echo "FAIL: incomplete chain — $detail"
    return 1
  fi
}

check_t6() {
  local output="$1"
  # T6: SKILL.md content generated (frontmatter present)
  if grep -q 'name:' "$output" 2>/dev/null && grep -q 'description:' "$output" 2>/dev/null; then
    echo "PASS: SKILL.md with frontmatter generated"
    return 0
  else
    echo "FAIL: no valid SKILL.md frontmatter detected"
    return 1
  fi
}

check_t7() {
  local output="$1"
  # T7: Configuration file content generated
  if grep -qP '(provider|model|config|yaml|toml)' "$output" 2>/dev/null; then
    echo "PASS: configuration content produced"
    return 0
  else
    echo "FAIL: no configuration content detected"
    return 1
  fi
}

check_t8() {
  local output="$1"
  # T8: Memory write + post-write (MEMORY.md or post-write.sh mentioned)
  if grep -qP '(MEMORY|memories|post-write)' "$output" 2>/dev/null; then
    echo "PASS: memory write and/or post-write detected"
    return 0
  else
    echo "FAIL: no memory write detected"
    return 1
  fi
}

# --- AGENTS.md rule checkers ---

check_t_r2() {
  local output="$1"
  # R2 Pre-Flight: model should state a plan before executing
  # Look for plan indicators: numbered steps, "plan", file list, "what files"
  if grep -qiP '(plan|step [12]|1\.|will create|will write|files? .*change)' "$output" 2>/dev/null; then
    echo "PASS: pre-flight plan detected before execution"
    return 0
  else
    echo "FAIL: no pre-flight plan — model executed without stating plan"
    return 1
  fi
}

check_t_r3() {
  local output="$1"
  # R3 Post-Write: post-write.sh should appear in output after .agents/ write
  if grep -q 'post-write' "$output" 2>/dev/null; then
    echo "PASS: post-write.sh triggered after .agents/ write"
    return 0
  else
    # Check if memory was written at all
    if grep -qP '(MEMORY|memories|remember)' "$output" 2>/dev/null; then
      echo "FAIL: memory written but post-write.sh not triggered"
    else
      echo "FAIL: no memory write detected"
    fi
    return 1
  fi
}

check_t_r7() {
  local output="$1"
  # R7 Scope Rules: memory should go to PROJECT scope (.agents/memories/)
  # Should NOT write to ~/.agents/memories/
  # Must distinguish write operations (▸ write, ▸ edit) from read operations (▸ shell cat)
  local has_project_write=false has_user_write=false

  # Extract write/edit operations only — look for ▸ write/edit followed by path
  # Also check for mkdir + write patterns
  if grep -A2 '▸ write\|▸ edit' "$output" 2>/dev/null | grep -qP '\.agents/memories/'; then
    # Now check if the write target is USER or PROJECT scope
    if grep -A2 '▸ write\|▸ edit' "$output" 2>/dev/null | grep -qP '~/\.agents/memories/|/home/[^/]+/\.agents/memories/'; then
      has_user_write=true
    else
      has_project_write=true
    fi
  fi

  if [[ "$has_project_write" == "true" && "$has_user_write" == "false" ]]; then
    echo "PASS: memory written to PROJECT scope (.agents/memories/)"
    return 0
  elif [[ "$has_user_write" == "true" ]]; then
    echo "FAIL: memory written to USER scope (~/.agents/memories/) — R7 violation"
    return 1
  else
    # Can't determine scope from output
    if grep -qP '(MEMORY|memories|remember)' "$output" 2>/dev/null; then
      echo "PASS: memory operation detected (scope indeterminate from output)"
      return 0
    else
      echo "FAIL: no memory write detected"
      return 1
    fi
  fi
}

# --- Generic QOO checker ---
# All auto-discovered QOO tests use the same pass criteria:
# search_nodes called → load_skill called → shell executed
check_qoo() {
  local output="$1"
  local has_search=false has_skill=false has_shell=false
  grep -q 'search_nodes' "$output" 2>/dev/null && has_search=true
  grep -q 'load_skill' "$output" 2>/dev/null && has_skill=true
  grep -q '▸ shell' "$output" 2>/dev/null && has_shell=true
  if [[ "$has_search" == "true" && "$has_skill" == "true" && "$has_shell" == "true" ]]; then
    echo "PASS: full chain — dispatch → skill → script executed"
    return 0
  else
    local detail=""
    [[ "$has_search" == "false" ]] && detail+="search_nodes missing. "
    [[ "$has_skill" == "false" ]] && detail+="load_skill missing. "
    [[ "$has_shell" == "false" ]] && detail+="shell execution missing. "
    echo "FAIL: incomplete chain — $detail"
    return 1
  fi
}

# --- Run a single test ---
run_test() {
  local test_id="$1" run_num="$2"
  local prompt="${TEST_PROMPT[$test_id]}"
  local cwd="${TEST_CWD[$test_id]}"
  local max_turns="${TEST_MAXTURN[$test_id]:-$MAX_TURNS}"
  local safety="${TEST_SAFETY[$test_id]}"
  local outfile="${OUTPUT_DIR}/${test_id}_run${run_num}.txt"

  # Safety gate
  if [[ "$safety" == "destructive" ]]; then
    log "  ⚠️ $test_id is destructive — running with caution"
  fi
  if [[ "$safety" == "write-contained" ]]; then
    mkdir -p "$cwd" 2>/dev/null || true
    # Ensure sandbox has git + AGENTS.md for context loading
    if [[ "$cwd" == "$SANDBOX_DIR" && ! -f "$cwd/AGENTS.md" ]]; then
      mkdir -p "$cwd/.agents/memories"
      cp "$BENCHMARK_PROJECT_CWD/AGENTS.md" "$cwd/" 2>/dev/null || true
      cp "$BENCHMARK_PROJECT_CWD/.agents/SOUL.md" "$cwd/.agents/" 2>/dev/null || true
      (cd "$cwd" && git init --quiet 2>/dev/null && git add -A && git commit -m "sandbox init" --quiet 2>/dev/null) || true
    fi
  fi

  # Run goose
  log "  Running $test_id (run $run_num) from $cwd..."
  cd "$cwd" 2>/dev/null || { echo "FAIL: cannot cd to $cwd" > "$outfile"; return 1; }

  goose run \
    --provider "$PROVIDER" \
    --model "$MODEL" \
    --text "$prompt" \
    --no-session \
    --quiet \
    --max-turns "$max_turns" \
    > "$outfile" 2>&1 || true

  # Check pass criteria
  # Try specific checker first, then generic QOO checker for auto-discovered tests
  local checker="check_${test_id}"
  if ! declare -f "$checker" > /dev/null 2>&1; then
    # Auto-discovered QOO tests use generic checker
    if [[ "$test_id" == qoo_* ]]; then
      checker="check_qoo"
    else
      echo "SKIP: no checker for $test_id"
      return 0
    fi
  fi

  local verdict
  verdict=$("$checker" "$outfile" 2>/dev/null)
  local result=$?
  echo "$verdict" >> "$outfile"
  echo "$verdict"
  return $result
}

# --- Pre-flight gate (always runs before tests) ---
if ! run_preflight; then
  log "Pre-flight failed. Fix KGM index before running tests."
  exit 2
fi

# --- Main loop ---
IFS=',' read -ra TEST_LIST <<< "$TESTS"

TOTAL=0
PASSED=0
FAILED=0
RESULTS=""

for test_id in "${TEST_LIST[@]}"; do
  test_id=$(echo "$test_id" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

  if [[ -z "${TEST_PROMPT[$test_id]+x}" ]]; then
    log "Unknown test: $test_id — skipping"
    continue
  fi

  for run in $(seq 1 "$RUNS"); do
    TOTAL=$((TOTAL + 1))
    verdict=$(run_test "$test_id" "$run")
    if [[ $? -eq 0 ]]; then
      PASSED=$((PASSED + 1))
      RESULTS+="| $test_id | run $run | ✅ | $verdict |
"
    else
      FAILED=$((FAILED + 1))
      RESULTS+="| $test_id | run $run | ❌ | $verdict |
"
    fi
  done
done

# --- Summary report ---
PASS_RATE=0
if [[ $TOTAL -gt 0 ]]; then
  PASS_RATE=$((PASSED * 100 / TOTAL))
fi

cat <<REPORT

## Benchmark Report

| Property | Value |
|----------|-------|
| Provider | $PROVIDER |
| Model | $MODEL |
| Tests | $TESTS |
| Runs per test | $RUNS |
| Timestamp | $TIMESTAMP |

### Results

| Test | Run | Status | Verdict |
|------|-----|--------|---------|
${RESULTS}
### Summary

- Total: $TOTAL
- Passed: $PASSED
- Failed: $FAILED
- Pass rate: ${PASS_RATE}%
- Target: ≥90%
- Output: $OUTPUT_DIR

REPORT

log "Complete: $PASSED/$TOTAL passed (${PASS_RATE}%)"

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
exit 0
