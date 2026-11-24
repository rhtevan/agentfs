#!/usr/bin/env bash
# t4-static-score.sh — Calibrated T4 scoring of the base skill's static record
# while SDM is unavailable (F30, option C, decided 2026-11-24).
#
# Runs sdm-evaluate.sh N times with the T4 drop-in backend (t4-score-call.sh,
# a model family different from the prose author), keeps the MEDIAN run by
# aggregate score and reports per-dimension agreement (share of runs that gave
# the median run's score). Never writes anything: the caller (agentfs-setup
# "upgrade agentfs" Step 4) persists, and only after calibration passed.
#
# Usage:
#   t4-static-score.sh <AGENTS.md> <schema.yaml> --evidence FILE
#                      [--phase build] [--runs 3]
#                      [--calibrate REF_SCORE] [--tolerance 3]
#
# --calibrate: compare the median aggregate with REF_SCORE (an SDM score of
#   the SAME template version and schema). Last line: T4_CALIBRATION=PASS|FAIL.
#   Without --calibrate the last line is T4_SCORE=<median aggregate>.
# Output: JSON {scorer, runs, aggregates, median, agreement, record} then the
#   signal line.
# Exit: 0 ran (read the signal) · 1 a run failed · 3 usage error.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ $# -ge 2 ]] || { sed -n 2,22p "$0"; exit 3; }
TARGET="$1" SCHEMA="$2"; shift 2
EVIDENCE="" PHASE="" RUNS=3 REF="" TOL=3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence) EVIDENCE="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --calibrate) REF="$2"; shift 2 ;;
    --tolerance) TOL="$2"; shift 2 ;;
    *) echo "t4-static-score: unknown argument $1" >&2; exit 3 ;;
  esac
done
[[ -f "$EVIDENCE" ]] || { echo "t4-static-score: --evidence FILE required" >&2; exit 3; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for i in $(seq 1 "$RUNS"); do
  SDM_CALL="$SCRIPT_DIR/t4-score-call.sh" bash "$SCRIPT_DIR/sdm-evaluate.sh" "$TARGET" "$SCHEMA" \
    --evidence "$EVIDENCE" ${PHASE:+--phase "$PHASE"} > "$TMP/run$i.json" 2> "$TMP/run$i.err" || true
  if ! jq -e '.aggregate_score >= 0' "$TMP/run$i.json" >/dev/null 2>&1; then
    echo "t4-static-score: run $i failed:" >&2; tail -5 "$TMP/run$i.err" >&2; exit 1
  fi
done

python3 - "$TMP" "$RUNS" "$REF" "$TOL" <<'PY'
import sys, json, statistics
tmp, runs, ref, tol = sys.argv[1], int(sys.argv[2]), sys.argv[3], float(sys.argv[4])
recs = [json.load(open(f"{tmp}/run{i}.json")) for i in range(1, runs + 1)]
aggs = [r["aggregate_score"] for r in recs]
med = statistics.median(aggs)
pick = min(recs, key=lambda r: abs(r["aggregate_score"] - med))
agree = {}
for d in pick["dimensions"]:
    same = sum(1 for r in recs for e in r["dimensions"] if e["name"] == d["name"] and e["score"] == d["score"])
    agree[d["name"]] = round(same / runs, 2)
out = {"scorer": pick.get("scorer"), "runs": runs, "aggregates": [round(a, 1) for a in aggs],
       "median": round(med, 1), "agreement": agree, "record": pick}
print(json.dumps(out, indent=2))
if ref:
    delta = med - float(ref)
    print(f"# calibration: median {med:.1f} vs reference {float(ref):.1f} → delta {delta:+.1f} (tolerance ±{tol:g})")
    print("T4_CALIBRATION=" + ("PASS" if abs(delta) <= tol else "FAIL"))
else:
    print(f"T4_SCORE={med:.1f}")
PY
