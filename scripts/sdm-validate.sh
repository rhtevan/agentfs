#!/bin/bash
# sdm-validate.sh — Validate a candidate SDM endpoint for AgentFS usability
#
# Runs the same sdm-evaluate.sh calls as score-all.sh (quality, observable,
# operable --phase build) against a candidate and a baseline SDM, then
# reports:
#   1. Pass/fail agreement with the baseline, per schema and per dimension
#   2. Ground-truth accuracy on dimensions whose answer is stated verbatim
#      in gather-skill-state.sh evidence (baseline is not assumed correct)
#   3. Completion (no SDM errors) and mean latency per evaluation
#
# Usage:
#   sdm-validate.sh --candidate <url> [--baseline <url>] [--sample N]
#                   [--gate 0.90] [--out <dir>]
#   sdm-validate.sh --baseline-only [--baseline <url>] --out <dir>
#   sdm-validate.sh --candidate <url> --baseline-dir <dir> [--gate 0.90]
#
#   --candidate URL  SDM base URL to validate (required)
#   --baseline  URL  Trusted SDM base URL (default: http://localhost:9000)
#   --sample N       Evaluate the first N skills only (default: all)
#   --gate F         Minimum agreement and ground-truth accuracy (default: 0.90)
#   --out DIR        Output directory (default: /tmp/sdm-validate-<timestamp>)
#   --baseline-only  Evaluate the baseline only and stop. The output directory
#                    (evidence/ + baseline/ + meta.json) is reusable with
#                    --baseline-dir — use it before replacing the baseline SDM.
#   --baseline-dir D Reuse a saved baseline instead of calling --baseline.
#                    The candidate is evaluated on the SAVED evidence, so both
#                    sides judge identical inputs even if skills changed since.
#
# Isolation: schemas are copied into the output directory, so operable
# persistence lands there. No scores.yaml or observations/ are written.
#
# Exit codes:
#   0 — PASS (all gates met)
#   1 — FAIL (one or more gates missed)
#   2 — An endpoint is unreachable
#   3 — Usage error
#
# Validated: 2026-11-16. d3-mini (4B, llama.cpp) vs Qwen3-14B (vLLM):
#   agreement 69.7%, ground truth 9/61 vs 56/61 → FAIL.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDM_EVALUATE="${SCRIPT_DIR}/sdm-evaluate.sh"
GATHER="${SCRIPT_DIR}/gather-skill-state.sh"
SKILLS_DIR="${HOME}/.agents/skills"

die() { echo "ERROR: $*" >&2; exit 3; }
log() { echo "[sdm-validate] $*" >&2; }

CANDIDATE=""; BASELINE="http://localhost:9000"; SAMPLE=0; GATE="0.90"
OUT="/tmp/sdm-validate-$(date +%Y%m%d-%H%M%S)"
BASELINE_ONLY=0; BASELINE_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --candidate) CANDIDATE="${2:-}"; shift 2 ;;
    --baseline)  BASELINE="${2:-}"; shift 2 ;;
    --sample)    SAMPLE="${2:-0}"; shift 2 ;;
    --gate)      GATE="${2:-0.90}"; shift 2 ;;
    --out)       OUT="${2:-}"; shift 2 ;;
    --baseline-only) BASELINE_ONLY=1; shift ;;
    --baseline-dir)  BASELINE_DIR="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done
if [[ "$BASELINE_ONLY" -eq 1 ]]; then
  [[ -z "$CANDIDATE" && -z "$BASELINE_DIR" ]] || die "--baseline-only takes no --candidate/--baseline-dir"
else
  [[ -n "$CANDIDATE" ]] || die "--candidate <url> is required"
fi
if [[ -n "$BASELINE_DIR" ]]; then
  [[ -d "$BASELINE_DIR/baseline" && -d "$BASELINE_DIR/evidence" && -f "$BASELINE_DIR/baseline/timing.txt" ]] \
    || die "--baseline-dir $BASELINE_DIR is not a saved baseline (needs evidence/, baseline/, baseline/timing.txt)"
fi
command -v jq >/dev/null || die "jq is required"
command -v python3 >/dev/null || die "python3 is required"
[[ -x "$SDM_EVALUATE" || -f "$SDM_EVALUATE" ]] || die "sdm-evaluate.sh not found"

ENDPOINTS=()
[[ -n "$CANDIDATE" ]] && ENDPOINTS+=("$CANDIDATE")
[[ -z "$BASELINE_DIR" ]] && ENDPOINTS+=("$BASELINE")
for ep in "${ENDPOINTS[@]}"; do
  if ! curl -s --max-time 10 "$ep/v1/models" | jq -e '.data[0].id' >/dev/null 2>&1; then
    echo "❌ SDM endpoint unreachable: $ep" >&2; exit 2
  fi
done

mkdir -p "$OUT"/{schemas,evidence,baseline,candidate}
cp "$SKILLS_DIR"/schemas/{quality,observable,operable}.yaml "$OUT/schemas/"
log "Output: $OUT"
if [[ -n "$BASELINE_DIR" ]]; then
  log "Baseline:  saved $BASELINE_DIR ($(jq -r '.model // "unknown"' "$BASELINE_DIR/meta.json" 2>/dev/null))"
else
  BASELINE_MODEL=$(curl -s "$BASELINE/v1/models" | jq -r '.data[0].id')
  log "Baseline:  $BASELINE ($BASELINE_MODEL)"
fi
[[ -n "$CANDIDATE" ]] && log "Candidate: $CANDIDATE ($(curl -s "$CANDIDATE/v1/models" | jq -r '.data[0].id'))"

# --- Collect skills and evidence ---
SKILLS=()
if [[ -n "$BASELINE_DIR" ]]; then
  # Reuse saved evidence + baseline results (identical inputs for both sides)
  for f in "$BASELINE_DIR"/evidence/*.txt; do
    n=$(basename "$f" .txt)
    [[ -f "$BASELINE_DIR/baseline/$n.operable.json" ]] || continue
    cp "$f" "$OUT/evidence/"
    cp "$BASELINE_DIR"/baseline/"$n".*.json "$OUT/baseline/"
    grep "^$n " "$BASELINE_DIR/baseline/timing.txt" >> "$OUT/baseline/timing.txt" || true
    SKILLS+=("$n")
    [[ "$SAMPLE" -gt 0 && ${#SKILLS[@]} -ge "$SAMPLE" ]] && break
  done
else
  for d in "$SKILLS_DIR"/*/; do
    n=$(basename "$d")
    [[ "$n" == "schemas" || ! -f "$d/SKILL.md" ]] && continue
    bash "$GATHER" "$d" > "$OUT/evidence/$n.txt" 2>/dev/null || continue
    [[ -s "$OUT/evidence/$n.txt" ]] || continue
    SKILLS+=("$n")
    [[ "$SAMPLE" -gt 0 && ${#SKILLS[@]} -ge "$SAMPLE" ]] && break
  done
fi
log "Skills: ${#SKILLS[@]}"

# --- Run evaluations (same invocations as score-all.sh) ---
run_side() {
  local label="$1" ep="$2" n d s
  for n in "${SKILLS[@]}"; do
    d="$SKILLS_DIR/$n"
    for sch in quality observable; do
      s=$(date +%s%N)
      SDM_ENDPOINT="$ep" SDM_MODEL="" SDM_TIMEOUT="${SDM_TIMEOUT:-60}" \
        bash "$SDM_EVALUATE" "$d" "$OUT/schemas/$sch.yaml" \
        --evidence "$OUT/evidence/$n.txt" > "$OUT/$label/$n.$sch.json" 2>/dev/null
      echo "$n $sch $(( ($(date +%s%N) - s) / 1000000 ))" >> "$OUT/$label/timing.txt"
    done
    s=$(date +%s%N)
    SDM_ENDPOINT="$ep" SDM_MODEL="" SDM_TIMEOUT="${SDM_TIMEOUT:-60}" \
      bash "$SDM_EVALUATE" "$OUT/evidence/$n.txt" "$OUT/schemas/operable.yaml" \
      --phase build > "$OUT/$label/$n.operable.json" 2>/dev/null
    echo "$n operable $(( ($(date +%s%N) - s) / 1000000 ))" >> "$OUT/$label/timing.txt"
  done
  log "$label done"
}
if [[ -z "$BASELINE_DIR" ]]; then
  run_side baseline "$BASELINE"
  jq -n --arg m "$BASELINE_MODEL" --arg e "$BASELINE" --arg t "$(date -Iseconds)" --argjson n "${#SKILLS[@]}" \
    '{model: $m, endpoint: $e, captured: $t, skills: $n}' > "$OUT/meta.json"
fi
if [[ "$BASELINE_ONLY" -eq 1 ]]; then
  log "Baseline saved: $OUT (reuse with --baseline-dir $OUT)"
  exit 0
fi
run_side candidate "$CANDIDATE"

# --- Analyze ---
python3 - "$OUT" "$GATE" <<'PY'
import json, glob, os, re, sys, collections, statistics as st
out, gate = sys.argv[1], float(sys.argv[2])

def load(p):
    try: return json.load(open(p))
    except Exception: return None

# Ground truth: facts stated verbatim in gather-skill-state.sh evidence.
# Observable evidence is stripped at "Step excerpts:" (same as sdm-evaluate.sh).
FACTS = {
    ("observable", "trace_instrumentation"): (r"Trace instrumentation: (true|false)", ("true",)),
    ("observable", "sdm_delegation"):        (r"sdm_delegation: (YES|NO)",          ("YES",)),
}

agree = total = errors = 0
per_schema = collections.defaultdict(lambda: [0, 0])
per_dim = collections.defaultdict(lambda: [0, 0])
gt = collections.defaultdict(lambda: [0, 0, 0])   # baseline_ok, candidate_ok, n
for a in sorted(glob.glob(f"{out}/baseline/*.json")):
    f = os.path.basename(a); A = load(a); B = load(f"{out}/candidate/{f}")
    skill, sch = f.split(".")[0], f.split(".")[-2]
    if not A or not B or B.get("band") == "SDM_UNAVAILABLE":
        errors += 1; continue
    da = {d["name"]: d for d in A.get("dimensions", [])}
    db = {d["name"]: d for d in B.get("dimensions", [])}
    ev = open(f"{out}/evidence/{skill}.txt").read().split("Step excerpts:")[0]
    for name, x in da.items():
        y = db.get(name)
        if not y or x.get("pass") is None or y.get("pass") is None:
            continue
        ok = x["pass"] == y["pass"]
        total += 1; agree += ok
        per_schema[sch][0] += ok; per_schema[sch][1] += 1
        per_dim[(sch, name)][0] += ok; per_dim[(sch, name)][1] += 1
        if (sch, name) in FACTS:
            pat, true_vals = FACTS[(sch, name)]
            m = re.search(pat, ev)
            if m:
                truth = m.group(1) in true_vals
                g = gt[name]; g[2] += 1
                g[0] += x["pass"] == truth; g[1] += y["pass"] == truth

def lat(label):
    t = collections.defaultdict(list)
    for line in open(f"{out}/{label}/timing.txt"):
        n, s, ms = line.split(); t[s].append(int(ms))
    return {k: round(st.mean(v)) for k, v in t.items()}

agreement = agree / total if total else 0.0
gt_cand = sum(g[1] for g in gt.values()); gt_n = sum(g[2] for g in gt.values())
gt_acc = gt_cand / gt_n if gt_n else None
gates = {
    "agreement": agreement >= gate,
    "ground_truth": gt_acc is None or gt_acc >= gate,
    "completion": errors == 0,
}
verdict = "PASS" if all(gates.values()) else "FAIL"

print(f"\n=== SDM Validation: {verdict} ===")
print(f"Agreement with baseline: {agree}/{total} = {agreement:.1%} (gate {gate:.0%}) {'✅' if gates['agreement'] else '❌'}")
for s, (g, t) in sorted(per_schema.items()):
    print(f"  {s:11} {g}/{t} = {g/t:.1%}")
if gt_n:
    print(f"Ground truth (candidate): {gt_cand}/{gt_n} = {gt_acc:.1%} {'✅' if gates['ground_truth'] else '❌'}")
    for name, (b, c, n) in gt.items():
        print(f"  {name:22} baseline {b}/{n} | candidate {c}/{n}")
print(f"Completion: {errors} failed evaluations {'✅' if gates['completion'] else '❌'}")
print("Worst dimensions:")
for (s, n), (g, t) in sorted(per_dim.items(), key=lambda kv: kv[1][0] / kv[1][1])[:5]:
    print(f"  {s}/{n}: {g}/{t} = {g/t:.0%}")
lb, lc = lat("baseline"), lat("candidate")
print("Mean latency per evaluation (ms): " + ", ".join(f"{k} {lb.get(k)}→{lc.get(k)}" for k in sorted(lb)))

json.dump({"verdict": verdict, "gate": gate, "agreement": agreement,
           "per_schema": {k: v[0] / v[1] for k, v in per_schema.items()},
           "ground_truth": {k: {"baseline": v[0], "candidate": v[1], "n": v[2]} for k, v in gt.items()},
           "errors": errors, "latency_ms": {"baseline": lb, "candidate": lc}},
          open(f"{out}/summary.json", "w"), indent=2)
print(f"\nSummary: {out}/summary.json")
sys.exit(0 if verdict == "PASS" else 1)
PY
