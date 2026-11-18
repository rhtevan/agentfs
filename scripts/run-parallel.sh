#!/usr/bin/env bash
# run-parallel.sh — sharded parallel compliance campaign (T4/T3/T2 at once).
#
# Usage:
#   run-parallel.sh smoke|real [--shards "T4=2,T3=6,T2=4"] [--tiers T4,T3,T2]
#     smoke : 1 run/test, records into a scratch copy of the profile
#     real  : update-compliance defaults (49 runs/tier), real profile
#
# Each tier's units ('<test> <run>') go into one queue, longest tests
# first. N workers per tier (benchmark.sh --queue) pop units under flock,
# each with its OWN project copy, sandbox and scratch dir — session
# evidence matches sessions by working dir, so same-model workers must
# never share a directory. When a tier's workers finish, transcripts are
# merged, checked for completeness (every unit exactly once), regraded
# with the current checkers and recorded via update-compliance replay.
#
# Exit: 0 all tiers recorded; 1 any tier failed (not recorded); 2 usage/gate.
set -uo pipefail
MODE=${1:-}; [[ $MODE == smoke || $MODE == real ]] || { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
shift
SHARDS="T4=2,T3=6,T2=4"; TIERS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shards) SHARDS="$2"; shift 2 ;;
    --tiers)  TIERS="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
S=${AGENTFS_BENCH_DIR:-$HOME/.local/state/agentfs/benchmarks}; mkdir -p "$S"
TS=$(date +%Y%m%d_%H%M%S)
UC=$HOME/.agents/scripts/update-compliance.sh; BS=$HOME/.agents/scripts/benchmark.sh
PROJ=${BENCHMARK_PROJECT_CWD:-$HOME/app/playground/context-eng}
P=$S/run-parallel-$MODE-$TS.log; echo "$P" > "$S/run-parallel-latest"
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$P"; }
cd "$PROJ" || { echo "ERROR: project '$PROJ' not found" >&2; exit 2; }
[[ -f AGENTS.md ]] || { echo "ERROR: '$PROJ' has no AGENTS.md" >&2; exit 2; }

# Longest-first (measured 2026-11-17, T3): long units start early so the
# tail of the run is made of short ones.
ORDER="t_r2git t_r3c_explicit t_r6 t_r2b t_r7dry t_r4s t_r1 t_r2 t_r7dry_conv t_r7dry_pend t_r4x t_r3c_implicit t_ii t1"

if [[ $MODE == smoke ]]; then
  export PROFILE_YAML=$S/smoke-profile-$TS.yaml
  cp "$HOME/.agents/skills/agentfs-setup/compliance-profile.yaml" "$PROFILE_YAML"
  UARGS=(--remeasure --runs 1 --runs-override ""); RUNS=1; OVR=""
else
  UARGS=(--remeasure)   # running a campaign IS the explicit re-measure decision
  OVR=$(grep -oP '^RUNS_OVERRIDE="\K[^"]*' "$UC"); RUNS=$(grep -oP 'MODEL=""; RUNS=\K\d+' "$UC")
fi
PROFILE=${PROFILE_YAML:-$HOME/.agents/skills/agentfs-setup/compliance-profile.yaml}
declare -A NSH=() RUNS_FOR=()
IFS=',' read -ra _kv <<< "$SHARDS"
for kv in "${_kv[@]}"; do [[ $kv =~ ^(T[1-4])=([1-9][0-9]?)$ ]] || { echo "ERROR: bad --shards entry '$kv'" >&2; exit 2; }; NSH[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}; done
TIERS=${TIERS:-T4,T3,T2}; IFS=',' read -ra TIER_LIST <<< "$TIERS"
IFS=',' read -ra _ro <<< "$OVR"; for kv in "${_ro[@]}"; do RUNS_FOR[${kv%%=*}]=${kv#*=}; done

# --- Gate (Rule 7): every tier must be PENDING ---
declare -A MODEL_OF PROV_OF TESTS_OF
for T in "${TIER_LIST[@]}"; do
  [[ -n "${NSH[$T]:-}" ]] || { echo "ERROR: no shard count for $T" >&2; exit 2; }
  out=$(bash "$UC" --tier "$T" --dry-run "${UARGS[@]}" 2>&1)
  sig=$(grep -oP '^DRY_RUN_RESULT=\K\w+' <<< "$out")
  [[ $sig == PENDING ]] || { say "$T dry-run=${sig:-none} — STOP (nothing launched)"; echo "$out" | tail -5 >> "$P"; exit 2; }
  MODEL_OF[$T]=$(grep -oP '^  Model: +\K\S+' <<< "$out"); PROV_OF[$T]=$(grep -oP '^  Provider: +\K\S+' <<< "$out")
  TESTS_OF[$T]=$(grep -oP '^  Tests: +\K\S+' <<< "$out")
  [[ -n ${MODEL_OF[$T]} && -n ${PROV_OF[$T]} && -n ${TESTS_OF[$T]} ]] || { say "$T: cannot parse model/provider/tests from dry-run — STOP"; exit 2; }
done
say "mode=$MODE shards=$SHARDS tiers=$TIERS runs=$RUNS override='${OVR}' profile=$PROFILE"

build_queue() {  # tests -> lines '<test> <run>' longest-first
  local tests=",$1," t r
  for t in $ORDER $(tr ',' ' ' <<< "$1"); do
    [[ $tests == *",$t,"* ]] || continue; tests=${tests/,$t,/,}
    for ((r=1; r<=${RUNS_FOR[$t]:-$RUNS}; r++)); do echo "$t $r"; done
  done
}

run_tier() {
  local T=$1 n=${NSH[$1]} model=${MODEL_OF[$1]} prov=${PROV_OF[$1]} tests=${TESTS_OF[$1]}
  local TD=$S/shards-$T-$TS D=$S/compliance-$T-$TS w pids=() t0=$SECONDS
  mkdir -p "$TD" "$D"
  build_queue "$tests" > "$TD/queue"; cp "$TD/queue" "$TD/expected"
  say "$T start: $model, $(wc -l < "$TD/expected") units, $n workers"
  for ((w=1; w<=n; w++)); do
    local pc=/tmp/benchmark-proj-$T-w$w
    rm -rf "$pc" && cp -a "$PROJ" "$pc"
    ( export BENCHMARK_PROJECT_CWD=$pc BENCHMARK_SANDBOX_DIR=/tmp/benchmark-sandbox-$T-w$w BENCHMARK_SCRATCH_DIR=/tmp/benchmark-scratch-$T-w$w
      cd "$pc" && bash "$BS" --provider "$prov" --model "$model" --tests "$tests" --runs "$RUNS" \
        ${OVR:+--runs-override "$OVR"} --queue "$TD/queue" --output "$TD/w$w" > "$TD/w$w.log" 2>&1 ) &
    pids+=($!); sleep 1
  done
  wait "${pids[@]}"
  say "$T workers done in $(( (SECONDS - t0) / 60 ))m$(( (SECONDS - t0) % 60 ))s :: $(grep -h 'Session cleanup' "$TD"/w*.log | grep -c FAILED) cleanup failure(s)"
  # --- Merge + completeness ---
  local f b dup
  for ((w=1; w<=n; w++)); do
    for f in "$TD/w$w"/*.txt; do [[ -e $f ]] || continue
      b=$(basename "$f"); [[ -e "$D/$b" ]] && { say "$T: DUPLICATE transcript $b — not recorded"; return 1; }
      cp "$f" "$D/"; done
  done
  cp "$TD/w1/.benchmark.frozen.sh" "$D/" 2>/dev/null
  local got missing extra
  got=$(ls "$D"/*_run*.txt 2>/dev/null | grep -vE '_phase[12]\.txt$|\.discarded[0-9]+\.txt$' | xargs -n1 basename | sed -E 's/_run([0-9]+)\.txt$/ \1/' | sort)
  missing=$(comm -23 <(sort "$TD/expected") <(echo "$got")); extra=$(comm -13 <(sort "$TD/expected") <(echo "$got"))
  [[ -s "$TD/queue" ]] && { say "$T: queue not drained ($(wc -l < "$TD/queue") left) — not recorded"; return 1; }
  [[ -z $missing && -z $extra ]] || { say "$T: INCOMPLETE — missing [$(echo $missing)] extra [$(echo $extra)] — not recorded"; return 1; }
  # --- Regrade (current checkers) + record ---
  (cd "$PROJ" && bash "$BS" --regrade "$D" --tests "$tests" --provider "$prov" --model "$model" > "$D.regrade.log" 2>&1)
  grep -q '^## Benchmark Report' "$D.regrade.log" || { say "$T: regrade produced no report — not recorded"; return 1; }
  BENCHMARK_OUTPUT_FILE="$D.regrade.log" BENCHMARK_OUTPUT_DIR="$D" bash "$UC" --tier "$T" "${UARGS[@]}" > "$S/record-$MODE-$T-$TS.log" 2>&1
  local rc=$?
  say "$T recorded rc=$rc :: $(grep -m1 '^- Passed:' "$D.regrade.log") / $(grep -m1 '^- Total:' "$D.regrade.log") ($(( (SECONDS - t0) / 60 ))m$(( (SECONDS - t0) % 60 ))s)"
  return $rc
}

declare -A TPID
for T in "${TIER_LIST[@]}"; do run_tier "$T" & TPID[$T]=$!; done
fail=0
for T in "${TIER_LIST[@]}"; do wait "${TPID[$T]}" || { fail=1; say "$T FAILED"; }; done

# --- Cleanup + leak check ---
for T in "${TIER_LIST[@]}"; do rm -rf /tmp/benchmark-proj-"$T"-w* /tmp/benchmark-sandbox-"$T"-w* /tmp/benchmark-scratch-"$T"-w*; done
rm -f "$PROFILE.lock"
left=$(sqlite3 -cmd ".timeout 15000" "$HOME/.local/share/goose/sessions/sessions.db" \
  "SELECT count(*) FROM sessions WHERE working_dir LIKE '/tmp/benchmark-%-w%'" 2>/dev/null)
say "ALL DONE fail=$fail leaked_sessions=${left:-?} log=$P"
exit $fail
