#!/bin/bash
# check-dispatch-fidelity.sh — Dispatch chain fidelity checker
#
# Validates that a goose run output shows correct dispatch behavior:
#   Level 1 (Presence):   search_nodes appears in output
#   Level 2 (Invocation): search_nodes was called with correct params and succeeded
#   Level 3 (Utilization): load_skill loaded the skill that search_nodes returned
#
# Usage:
#   bash check-dispatch-fidelity.sh <output-file>
#
# Exit codes:
#   0 = PASS (all three levels)
#   1 = FAIL (with specific level and reason)
#
# Designed as an Executable Specification for benchmark.sh integration.
# Follows ES-First principle: verified failing against known-bad fixture
# before integration.

set -uo pipefail

OUTPUT="${1:?Usage: check-dispatch-fidelity.sh <output-file>}"

if [[ ! -f "$OUTPUT" ]]; then
  echo "FAIL: output file not found: $OUTPUT"
  exit 1
fi

# ── Level 1: Presence ─────────────────────────────────────────────
# Was search_nodes called at all?
if ! grep -q 'search_nodes' "$OUTPUT" 2>/dev/null; then
  echo "FAIL [L1-presence]: search_nodes never called — dispatch skipped entirely"
  exit 1
fi

# ── Level 2: Invocation Correctness ──────────────────────────────
# 2a: Was search_nodes the FIRST tool call?
# Extract the first ▸ line (first tool invocation)
first_tool=$(grep -m1 '▸ ' "$OUTPUT" 2>/dev/null | sed 's/.*▸ //' | awk '{print $1}')
if [[ "$first_tool" != "search_nodes" ]]; then
  echo "FAIL [L2-order]: first tool call was '$first_tool', not search_nodes — dispatch rule violated"
  exit 1
fi

# 2b: Was search_nodes called with the correct parameter name?
# Extract the search_nodes call line and check for "query" vs wrong params
search_call=$(grep '▸ search_nodes' "$OUTPUT" | head -1)
if echo "$search_call" | grep -q '"query"'; then
  : # correct parameter
elif echo "$search_call" | grep -q '"keywords"'; then
  echo "FAIL [L2-param]: search_nodes called with wrong parameter 'keywords' instead of 'query'"
  exit 1
elif echo "$search_call" | grep -q '"search"'; then
  echo "FAIL [L2-param]: search_nodes called with wrong parameter 'search' instead of 'query'"
  exit 1
else
  echo "FAIL [L2-param]: search_nodes call does not contain 'query' parameter"
  exit 1
fi

# 2c: Did search_nodes return successfully (no error)?
# Check for error indicators after the search_nodes call
# Look for error responses between search_nodes call and next tool call
search_line=$(grep -n '▸ search_nodes' "$OUTPUT" | head -1 | cut -d: -f1)
if [[ -n "$search_line" ]]; then
  # Check lines after search_nodes for error indicators
  tail -n +"$search_line" "$OUTPUT" | head -20 | \
    grep -q 'ERROR\|isError.*true\|not available\|Tool .* is not available' && {
    echo "FAIL [L2-error]: search_nodes called but returned error"
    exit 1
  }
fi

# ── Level 3: Result Utilization ──────────────────────────────────
# Did load_skill load a skill consistent with search_nodes results?
if ! grep -q 'load_skill' "$OUTPUT" 2>/dev/null; then
  echo "FAIL [L3-missing]: search_nodes succeeded but load_skill never called"
  exit 1
fi

# Extract what search_nodes returned (skill entity name)
# Look for skill name in search_nodes response
search_result_skill=$(grep -A5 '▸ search_nodes' "$OUTPUT" | \
  grep -oP 'load_skill\(name: \\"([^"\\]+)\\"\)' | head -1 | \
  sed 's/load_skill(name: \\"//' | sed 's/\\")//')

# Extract what load_skill actually loaded
loaded_skill=$(grep '▸ load_skill' "$OUTPUT" | head -1 | \
  grep -oP '"name":\s*"([^"]+)"' | sed 's/"name":\s*"//' | sed 's/"//')

if [[ -n "$search_result_skill" && -n "$loaded_skill" ]]; then
  if [[ "$search_result_skill" != "$loaded_skill" ]]; then
    echo "FAIL [L3-mismatch]: search_nodes returned '$search_result_skill' but load_skill loaded '$loaded_skill'"
    exit 1
  fi
fi

# All levels passed
echo "PASS: dispatch chain verified — search_nodes(query) → result → load_skill (all 3 levels)"
exit 0
