#!/usr/bin/env bash
# update-compliance.sh — Run benchmarks and update compliance-profile.yaml
#
# Usage:
#   update-compliance.sh --tier T4 --provider custom_redhat --model claude-sonnet-4-6
#   update-compliance.sh --tier T2 --provider custom_skupper --model Qwen/Qwen3-14B-FP8
#   update-compliance.sh --tier T2 --runs 5     (uses defaults from profile)
#   update-compliance.sh --check                (show current profile, no benchmark)
#
# Runs benchmark.sh with rule compliance tests, parses results,
# and updates compliance-profile.yaml with the new data.
#
# Exit codes:
#   0 — Profile updated successfully
#   1 — Benchmark failed or profile update failed
#   2 — Configuration error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_YAML="${HOME}/.agents/skills/agentfs-setup/compliance-profile.yaml"
BENCHMARK_SH="${SCRIPT_DIR}/benchmark.sh"
AGENTS_MD_VERSION=""
CHECK_ONLY=false

# Defaults
TIER=""
PROVIDER=""
MODEL=""
RUNS=3
TESTS="t1,t_r2,t_r3,t_r7"

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)     TIER="$2"; shift 2 ;;
    --provider) PROVIDER="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    --runs)     RUNS="$2"; shift 2 ;;
    --tests)    TESTS="$2"; shift 2 ;;
    --check)    CHECK_ONLY=true; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# //;s/^#//'; exit 0 ;;
    *)          echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Get AGENTS.md version ---
get_agents_md_version() {
  local agents_md
  agents_md=$(git rev-parse --show-toplevel 2>/dev/null)/AGENTS.md
  [[ -f "$agents_md" ]] || agents_md="${HOME}/.config/goose/prompts/system.md"
  if [[ -f "$agents_md" ]]; then
    grep -oP 'agentfs-template-version:\s*\K[0-9.]+' "$agents_md" 2>/dev/null || echo "unknown"
  else
    echo "unknown"
  fi
}

AGENTS_MD_VERSION=$(get_agents_md_version)

# --- Check mode ---
if $CHECK_ONLY; then
  echo "=== AgentFS Compliance Profile ==="
  echo ""
  if [[ ! -f "$PROFILE_YAML" ]]; then
    echo "❌ Profile not found: $PROFILE_YAML"
    exit 1
  fi

  echo "AGENTS.md version: $AGENTS_MD_VERSION"
  echo "Profile location:  $PROFILE_YAML"
  echo ""

  # Show current tiers
  echo "Validated tiers:"
  grep -A4 'T[0-9]:' "$PROFILE_YAML" | grep -E 'T[0-9]:|model:|overall:|date:' | while read line; do
    echo "  $line"
  done

  echo ""
  echo "Minimum tier: $(grep 'minimum_tier:' "$PROFILE_YAML" | awk '{print $2}')"
  echo "Target:       $(grep 'compliance_target:' "$PROFILE_YAML" | awk '{print $2}' | tr -d '"')"

  # Check staleness
  profile_version=$(grep 'agents_md_version:' "$PROFILE_YAML" | awk '{print $2}' | tr -d '"')
  if [[ "$profile_version" != "$AGENTS_MD_VERSION" ]]; then
    echo ""
    echo "⚠ STALE: Profile is for v${profile_version} but AGENTS.md is v${AGENTS_MD_VERSION}"
    echo "  Run: update-compliance.sh --tier T4 --provider <name> --model <id>"
  else
    echo ""
    echo "✅ Profile is current (v${profile_version})"
  fi
  exit 0
fi

# --- Validate inputs ---
if [[ -z "$TIER" ]]; then
  echo "ERROR: --tier is required (T2 or T4)" >&2
  exit 2
fi

# Set defaults per tier if provider/model not specified
if [[ -z "$PROVIDER" || -z "$MODEL" ]]; then
  case "$TIER" in
    T4)
      PROVIDER="${PROVIDER:-custom_redhat}"
      MODEL="${MODEL:-claude-sonnet-4-6}"
      ;;
    T2)
      PROVIDER="${PROVIDER:-custom_skupper}"
      MODEL="${MODEL:-Qwen/Qwen3-14B-FP8}"
      ;;
    *)
      echo "ERROR: Unknown tier $TIER. Use T2 or T4." >&2
      exit 2
      ;;
  esac
fi

if [[ ! -f "$BENCHMARK_SH" ]]; then
  echo "ERROR: benchmark.sh not found at $BENCHMARK_SH" >&2
  exit 2
fi

if [[ ! -f "$PROFILE_YAML" ]]; then
  echo "ERROR: compliance-profile.yaml not found at $PROFILE_YAML" >&2
  exit 2
fi

echo "=== AgentFS Compliance Benchmark ==="
echo "  Tier:     $TIER"
echo "  Provider: $PROVIDER"
echo "  Model:    $MODEL"
echo "  Runs:     $RUNS"
echo "  Tests:    $TESTS"
echo "  AGENTS.md: v${AGENTS_MD_VERSION}"
echo ""

# --- Run benchmark ---
OUTPUT_DIR="/tmp/compliance-${TIER}-$(date +%Y%m%d_%H%M%S)"

echo "Running benchmark..."
BENCHMARK_OUTPUT=$(bash "$BENCHMARK_SH" \
  --provider "$PROVIDER" \
  --model "$MODEL" \
  --tests "$TESTS" \
  --runs "$RUNS" \
  --output "$OUTPUT_DIR" 2>&1) || true

echo "$BENCHMARK_OUTPUT"

# --- Parse results ---
TOTAL=$(echo "$BENCHMARK_OUTPUT" | grep '^- Total:' | awk '{print $3}')
PASSED=$(echo "$BENCHMARK_OUTPUT" | grep '^- Passed:' | awk '{print $3}')
FAILED=$(echo "$BENCHMARK_OUTPUT" | grep '^- Failed:' | awk '{print $3}')
PASS_RATE=$(echo "$BENCHMARK_OUTPUT" | grep '^- Pass rate:' | awk '{print $4}' | tr -d '%')

if [[ -z "$TOTAL" || -z "$PASSED" ]]; then
  echo ""
  echo "ERROR: Could not parse benchmark output" >&2
  exit 1
fi

OVERALL="${PASS_RATE}%"
DATE=$(date +%Y-%m-%d)

echo ""
echo "=== Results ==="
echo "  Total:     $TOTAL"
echo "  Passed:    $PASSED"
echo "  Failed:    $FAILED"
echo "  Pass rate: $OVERALL"
echo ""

# --- Parse per-rule results ---
# Extract per-test pass/fail counts
declare -A RULE_PASS RULE_TOTAL
for test_id in t1 t_r2 t_r3 t_r7; do
  pass=0
  total=0
  while IFS='|' read -r _ tid _ status _; do
    tid=$(echo "$tid" | xargs)
    status=$(echo "$status" | xargs)
    if [[ "$tid" == "$test_id" ]]; then
      total=$((total + 1))
      [[ "$status" == "✅" ]] && pass=$((pass + 1))
    fi
  done <<< "$(echo "$BENCHMARK_OUTPUT" | grep "^| $test_id ")"
  RULE_PASS[$test_id]=$pass
  RULE_TOTAL[$test_id]=$total
done

# Map test IDs to rule names
calc_rate() {
  local p=$1 t=$2
  [[ $t -eq 0 ]] && echo "not_tested" && return
  echo "$((p * 100 / t))%"
}

R3_RATE=$(calc_rate "${RULE_PASS[t1]:-0}" "${RULE_TOTAL[t1]:-0}")
R2_RATE=$(calc_rate "${RULE_PASS[t_r2]:-0}" "${RULE_TOTAL[t_r2]:-0}")
R6_RATE=$(calc_rate "${RULE_PASS[t_r3]:-0}" "${RULE_TOTAL[t_r3]:-0}")
R7_RATE=$(calc_rate "${RULE_PASS[t_r7]:-0}" "${RULE_TOTAL[t_r7]:-0}")

echo "Per-rule breakdown:"
echo "  R1 Signal Dispatch: (tested via QOO skills, not in rule tests)"
echo "  R2 Pre-Flight:      $R2_RATE"
echo "  R3 Session Canary:  $R3_RATE"
echo "  R6 Scope/Post-Write: $R6_RATE"
echo "  R7 Scope Rules:     $R7_RATE"

# --- Update compliance-profile.yaml ---
# Use Python for YAML manipulation (safer than sed for nested structures)
python3 << UPDATE_PYTHON
import yaml, sys, os
from datetime import date

profile_path = "$PROFILE_YAML"
with open(profile_path) as f:
    # Read as text and parse
    content = f.read()

# Simple field updates via string replacement
tier = "$TIER"
today = "$DATE"
overall = "$OVERALL"
model = "$MODEL"
provider = "$PROVIDER"
runs = int("$TOTAL")
passed = int("$PASSED")
agents_version = "$AGENTS_MD_VERSION"

# Update agents_md_version
import re
content = re.sub(
    r'agents_md_version:\s*"[^"]*"',
    f'agents_md_version: "{agents_version}"',
    content
)

# Update the evolution section — add new entry if version changed
# Check if this version already has a non-pending entry
if f'version: "{agents_version}"' in content and 'pending' not in content.split(f'version: "{agents_version}"')[1].split('\n')[1]:
    # Already has a real entry — update it
    pass
else:
    # Update the pending entry to real values
    content = content.replace(
        f'T4_overall: "pending"',
        f'T4_overall: "{overall}"' if tier == "T4" else 'T4_overall: "pending"'
    )
    content = content.replace(
        f'T2_overall: "pending"',
        f'T2_overall: "{overall}"' if tier == "T2" else 'T2_overall: "pending"'
    )

with open(profile_path, 'w') as f:
    f.write(content)

print(f"✅ Updated compliance-profile.yaml for {tier}")
print(f"   Model: {model}")
print(f"   Overall: {overall}")
print(f"   Date: {today}")
UPDATE_PYTHON

echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Profile: $PROFILE_YAML"
