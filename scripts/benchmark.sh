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
TESTS="t1,t2,t3,t5,t9"
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

declare -A TEST_PROMPT TEST_CWD TEST_MAXTURN TEST_SAFETY

# T1 — Session Canary (needs AGENTS.md in CWD for context loading)
TEST_PROMPT[t1]="hello"
TEST_CWD[t1]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t1]=5
TEST_SAFETY[t1]="read-only"

# T2 — Signal Dispatch → Skill Load → Script (Pattern A)
TEST_PROMPT[t2]="hey headroom status"
TEST_CWD[t2]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t2]=10
TEST_SAFETY[t2]="read-only"

# T3 — Single Script (Pattern A)
TEST_PROMPT[t3]="hey crc status"
TEST_CWD[t3]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t3]=10
TEST_SAFETY[t3]="read-only"

# T4 — Multi-step (Pattern B) — DESTRUCTIVE
TEST_PROMPT[t4]="hey git"
TEST_CWD[t4]="$HOME/.agents"
TEST_MAXTURN[t4]=20
TEST_SAFETY[t4]="destructive"

# T5 — Prose Analysis (Pattern C)
TEST_PROMPT[t5]="hey check violations"
TEST_CWD[t5]="$HOME/.agents"
TEST_MAXTURN[t5]=15
TEST_SAFETY[t5]="read-only"

# T6 — Generative (Pattern D) — WRITE
TEST_PROMPT[t6]="hey create skill"
TEST_CWD[t6]="/tmp/benchmark-scratch"
TEST_MAXTURN[t6]=25
TEST_SAFETY[t6]="write-contained"

# T7 — Configuration (Pattern E) — DESTRUCTIVE
TEST_PROMPT[t7]="hey configure goose litellm"
TEST_CWD[t7]="$HOME"
TEST_MAXTURN[t7]=15
TEST_SAFETY[t7]="destructive"

# T8 — Write Rules (R3+R7) — WRITE
TEST_PROMPT[t8]="hey remember that benchmark testing started today"
TEST_CWD[t8]="/tmp/benchmark-scratch"
TEST_MAXTURN[t8]=10
TEST_SAFETY[t8]="write-contained"

# T9 — Operable Skill: README Audit (Pattern A — Phase 2 converted skill)
TEST_PROMPT[t9]="hey check readme"
TEST_CWD[t9]="$BENCHMARK_PROJECT_CWD"
TEST_MAXTURN[t9]=15
TEST_SAFETY[t9]="read-only"

# --- KGM query mapping (for preflight verification) ---
# Maps test IDs to the expected search_nodes query.
# T1 has no dispatch (no KGM query). Only dispatch tests need verification.
declare -A TEST_KGM_QUERY
TEST_KGM_QUERY[t2]="headroom status"
TEST_KGM_QUERY[t3]="crc status"
TEST_KGM_QUERY[t5]="check violations"
TEST_KGM_QUERY[t9]="check readme"

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

check_t9() {
  local output="$1"
  # T9: Full chain — search_nodes → load_skill → shell (gather-state.sh)
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
  local checker="check_${test_id}"
  if declare -f "$checker" > /dev/null 2>&1; then
    local verdict
    verdict=$("$checker" "$outfile" 2>/dev/null)
    local result=$?
    echo "$verdict" >> "$outfile"
    echo "$verdict"
    return $result
  else
    echo "SKIP: no checker for $test_id"
    return 0
  fi
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
