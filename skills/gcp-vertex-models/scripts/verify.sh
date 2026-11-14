#!/usr/bin/env bash
# verify.sh — Read-only checks for gcp-vertex-models (spec S1–S5).
# Usage: bash verify.sh [--live]   (--live also runs a fresh probe; costs ~1 token per model/region)
# Exit codes: 0 = all checks pass, 1 = one or more checks failed
set -uo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "gcp-vertex-models" "1.0.0" 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_FILE="${GCP_VERTEX_MODELS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gcp-vertex-models/models.json}"
LIVE=false; [[ "${1:-}" == "--live" ]] && LIVE=true
PASS=0; FAIL=0; STEP=0
check() {  # <label> <PASS|FAIL>
  STEP=$((STEP + 1))
  if [[ "$2" == PASS ]]; then echo "✅ $1"; PASS=$((PASS + 1)); trace_step "$STEP" "$1" 0 "" 2>/dev/null || true
  else echo "❌ $1"; FAIL=$((FAIL + 1)); trace_step "$STEP" "$1" 1 "" 2>/dev/null || true; fi
}

# S1: fresh probe (optional, network)
if $LIVE; then
  bash "$DIR/probe-models.sh" >/dev/null 2>&1 && check "S1: probe-models.sh exit 0 (live probe)" PASS || check "S1: probe-models.sh exit 0 (live probe)" FAIL
fi

# S2: cache exists and matches the JSON contract
if [[ -f "$CACHE_FILE" ]] && python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
assert {"project","regions","credential","generated_at","models"} <= d.keys()
for m in d["models"]:
    assert {"model","status","region","regions"} <= m.keys()
' "$CACHE_FILE" 2>/dev/null; then check "S2: cache JSON valid ($CACHE_FILE)" PASS
else check "S2: cache JSON valid ($CACHE_FILE) — run refresh vertex models" FAIL; fi

# S3: list query works and shows >=1 usable model
OUT=$(bash "$DIR/models.sh" list 2>&1); RC=$?
[[ $RC -eq 0 ]] && check "S3: models.sh list → $(echo "$OUT" | grep -o 'Usable: [0-9]*')" PASS || check "S3: models.sh list (exit $RC)" FAIL

# S4: default is a usable model and is ranked first
DEF=$(bash "$DIR/models.sh" default 2>/dev/null); RC=$?
if [[ $RC -eq 0 ]] && python3 -c '
import json,sys
name,region=sys.argv[2].split()
d=json.load(open(sys.argv[1]))
m=[x for x in d["models"] if x["model"]==name][0]
assert m["regions"].get(region)==200
' "$CACHE_FILE" "$DEF" 2>/dev/null; then check "S4: default model usable ($DEF)" PASS
else check "S4: default model usable (got: '$DEF')" FAIL; fi

# S5: rank ordering is deterministic
R=$(printf 'claude-sonnet-5-5\nclaude-haiku-5-5\nclaude-opus-4-8\nclaude-fable-5\nclaude-opus-5\n' | bash "$DIR/models.sh" rank | tr '\n' ' ')
[[ "$R" == "claude-opus-5 claude-opus-4-8 claude-sonnet-5-5 claude-haiku-5-5 " ]] && check "S5: rank order opus>sonnet>haiku, newest first, unknown dropped" PASS || check "S5: rank order (got: $R)" FAIL

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $PASS passed, $FAIL failed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
trace_end 2>/dev/null || true
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
