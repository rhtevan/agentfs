#!/usr/bin/env bash
# update-compliance.sh — Run AGENTS.md rule benchmarks for one model tier
# and record the results in compliance-profile.yaml.
#
# Usage:
#   update-compliance.sh --tier T2                 (tier representative from profile)
#   update-compliance.sh --tier T3 --runs 5
#   update-compliance.sh --tier T2 --provider custom_corp --model <id>   (override)
#   update-compliance.sh --tier T2 --dry-run       (show plan, write nothing)
#   update-compliance.sh --check                   (show profile + staleness)
#
# Options:
#   --tier T1|T2|T3|T4  Required (except --check). Results are never
#                       recorded without a tier.
#   --provider/--model  Override the tier representative (both or neither).
#   --runs N            Runs per test (default 3; see --runs-override).
#   --runs-override L   Per-test runs (cap 5, sized per rule — agreed 2026-11-17):
#                       default t1=5,t_r1=5,t_r6=5 (single-test rules),
#                       t_r2=4,t_r2b=4,t_r2git=4 (R2 = 12), R4/R7 tests 3
#                       each (9 per rule), diagnostics t_r3c_*=2. 49 runs/model.
#   --tests LIST        Default: t1,t_r1,t_r2,t_r2b,t_r2git,t_r6,t_r3c_implicit,
#                       t_r3c_explicit,t_r4x,t_r4s,t_ii,t_r7dry,t_r7dry_conv,t_r7dry_pend
#   --dry-run           Print plan + DRY_RUN_RESULT=CONVERGED|PENDING|UNKNOWN.
#   --check             Show the profile and whether it is stale.
#
# Environment:
#   PROFILE_YAML           Profile path (default: agentfs-setup/compliance-profile.yaml)
#   BENCHMARK_PROJECT_CWD  Project with the AGENTS.md under test (default: git root).
#                          The rules hash/version are read from THIS AGENTS.md.
#   BENCHMARK_OUTPUT_FILE  Replay: parse this saved benchmark report instead of
#                          running benchmark.sh (BENCHMARK_OUTPUT_DIR = its output dir).
#                          A 'benchmark.sh --regrade DIR' report works as input.
#
# Per-rule mapping (each rule pools its tests' runs):
#   t_r1 → R1 Signal Dispatch      t_r2 + t_r2b + t_r2git → R2 Pre-Flight
#   t1 → R3 Session Canary         t_r4x + t_r4s + t_ii → R4 Conflict Resolution
#   t_r6 → R6 Scope & Post-Write (one run graded on scope AND post-write)
#   t_r7dry + t_r7dry_conv + t_r7dry_pend → R7 Dry-Run Gate
#   R5 Checkpoint: no test (by decision).
#   Diagnostics (reported, NOT pooled): t_r3c_implicit / t_r3c_explicit
#   — user request vs the R3 canary. They
#   measure how binding a model treats R3, not R4 (vehicle-dependent).
#
# Dry-run staleness: an entry is PENDING if the rules hash, model,
# provider, test coverage OR the benchmark.sh blob sha (harness_sha)
# differs — a changed grader makes a recorded score stale.
# overall = mean of the tested rules' rates (each rule weighs the same,
# regardless of run counts); overall_runs_weighted is kept for reference.
#
# Staleness: each tier records the rules hash it was measured against.
# The top-level agents_md_rules_hash (read by sync-agents-md.sh) only
# moves when EVERY tier in required_tiers matches the current hash, so
# the profile never reads "current" while a tier is still stale.
#
# Exit codes:
#   0 — Profile updated (or dry-run/check completed)
#   1 — Benchmark failed to produce parseable results / update failed
#   2 — Configuration/usage error
#   3 — Dry-run could not determine state (UNKNOWN)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_YAML="${PROFILE_YAML:-${HOME}/.agents/skills/agentfs-setup/compliance-profile.yaml}"
BENCHMARK_SH="${SCRIPT_DIR}/benchmark.sh"

TIER=""; PROVIDER=""; MODEL=""; RUNS=3
TESTS="t1,t_r1,t_r2,t_r2b,t_r2git,t_r6,t_r3c_implicit,t_r3c_explicit,t_r4x,t_r4s,t_ii,t_r7dry,t_r7dry_conv,t_r7dry_pend"
RUNS_OVERRIDE="t1=5,t_r1=5,t_r6=5,t_r2=4,t_r2b=4,t_r2git=4,t_r3c_implicit=2,t_r3c_explicit=2"
CHECK_ONLY=false; DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)     TIER="${2:-}"; shift 2 ;;
    --provider) PROVIDER="${2:-}"; shift 2 ;;
    --model)    MODEL="${2:-}"; shift 2 ;;
    --runs)     RUNS="${2:-}"; shift 2 ;;
    --tests)    TESTS="${2:-}"; shift 2 ;;
    --runs-override) RUNS_OVERRIDE="${2:-}"; shift 2 ;;
    --check)    CHECK_ONLY=true; shift ;;
    --dry-run)  DRY_RUN=true; shift ;;
    -h|--help)  sed -n '2,/^$/p' "$0" | sed 's/^# //;s/^#//'; exit 0 ;;
    *)          echo "ERROR: unknown option: $1" >&2; exit 2 ;;
  esac
done

[[ -f "$PROFILE_YAML" ]] || { echo "ERROR: profile not found: $PROFILE_YAML" >&2; exit 2; }

# --- AGENTS.md under test (same resolution as benchmark.sh) ---
PROJECT_CWD="${BENCHMARK_PROJECT_CWD:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
AGENTS_MD="${PROJECT_CWD:+$PROJECT_CWD/AGENTS.md}"
AGENTS_MD_VERSION="unknown"; RULES_HASH=""
if [[ -n "$AGENTS_MD" && -f "$AGENTS_MD" ]]; then
  AGENTS_MD_VERSION=$(grep -oP 'agentfs-template-version:\s*\K[0-9.]+' "$AGENTS_MD" 2>/dev/null || echo unknown)
  RULES_HASH=$(bash "${SCRIPT_DIR}/rules-hash.sh" "$AGENTS_MD" 2>/dev/null || echo "")
fi

# --- Profile reader (prints KEY=VALUE lines) ---
profile_query() {
  python3 - "$PROFILE_YAML" "$@" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1])) or {}
mode = sys.argv[2]
if mode == "rep":
    r = (d.get("representatives") or {}).get(sys.argv[3]) or {}
    print(f"REP_PROVIDER={r.get('provider','')}"); print(f"REP_MODEL={r.get('model','')}")
elif mode == "tier":
    t = (d.get("validated_tiers") or {}).get(sys.argv[3]) or {}
    for k in ("model", "provider", "rules_hash", "overall", "date", "harness_sha"):
        print(f"T_{k.upper()}={t.get(k,'')}")
    print(f"T_TESTS={','.join(sorted((t.get('per_test') or {}).keys()))}")
elif mode == "check":
    cur = sys.argv[3]
    print(f"Profile rules hash: {d.get('agents_md_rules_hash','')} (v{d.get('agents_md_version','')})")
    print(f"Minimum tier:       {d.get('minimum_tier','')} ({d.get('minimum_tier_rate','')}) target {d.get('compliance_target','')}")
    print("Validated tiers:")
    for name, t in sorted((d.get("validated_tiers") or {}).items(), reverse=True):
        st = "current" if cur and t.get("rules_hash") == cur else "STALE"
        print(f"  {name}: {t.get('model')} ({t.get('provider')}) {t.get('overall')} "
              f"runs={t.get('runs_per_test', t.get('runs'))} date={t.get('date')} [{st}]")
    missing = [x for x in d.get("required_tiers", []) if x not in (d.get("validated_tiers") or {})]
    if missing: print(f"  Not yet measured: {', '.join(missing)}")
PY
}

# --- Check mode ---
if $CHECK_ONLY; then
  echo "=== AgentFS Compliance Profile ==="
  echo "AGENTS.md under test: ${AGENTS_MD:-<none>} (v${AGENTS_MD_VERSION}, rules hash ${RULES_HASH:-unavailable})"
  profile_query check "$RULES_HASH"
  profile_hash=$(grep -m1 '^agents_md_rules_hash:' "$PROFILE_YAML" | awk '{print $2}' | tr -d '"' || true)
  echo ""
  if [[ -z "$RULES_HASH" ]]; then
    echo "⚠ Cannot verify: rules hash unavailable (no readable AGENTS.md)"
  elif [[ "$profile_hash" != "$RULES_HASH" ]]; then
    echo "⚠ STALE: AGENTS.md rules changed since this profile was measured"
    echo "  Run: update-compliance.sh --tier <T2|T3|T4> --runs 5   (for each stale tier)"
  else
    echo "✅ Profile is current (rules hash ${RULES_HASH})"
  fi
  exit 0
fi

# --- Validate inputs ---
case "$TIER" in
  T1|T2|T3|T4) ;;
  "") echo "ERROR: --tier is required (T1|T2|T3|T4)" >&2; exit 2 ;;
  *)  echo "ERROR: unknown tier '$TIER' (use T1|T2|T3|T4)" >&2; exit 2 ;;
esac
if [[ -n "$PROVIDER" && -z "$MODEL" ]] || [[ -z "$PROVIDER" && -n "$MODEL" ]]; then
  echo "ERROR: --provider and --model must be given together (or neither)" >&2; exit 2
fi
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: --runs must be a positive integer" >&2; exit 2; }
if [[ -z "$PROVIDER" ]]; then
  eval "$(profile_query rep "$TIER")"
  PROVIDER="$REP_PROVIDER"; MODEL="$REP_MODEL"
  if [[ -z "$PROVIDER" || -z "$MODEL" ]]; then
    echo "ERROR: no representative for $TIER in $PROFILE_YAML (representatives.$TIER)" >&2; exit 2
  fi
  MODEL_SOURCE="tier representative"
else
  MODEL_SOURCE="explicit override"
fi

print_plan() {
  echo "=== AgentFS Compliance Benchmark ==="
  echo "  Tier:      $TIER"
  echo "  Provider:  $PROVIDER"
  echo "  Model:     $MODEL ($MODEL_SOURCE)"
  echo "  Runs:      $RUNS per test${RUNS_OVERRIDE:+ (override: $RUNS_OVERRIDE)}"
  echo "  Tests:     $TESTS"
  echo "  AGENTS.md: ${AGENTS_MD:-<none>} (v${AGENTS_MD_VERSION}, rules hash ${RULES_HASH:-unavailable})"
  echo "  Profile:   $PROFILE_YAML"
}

# --- Dry run ---
if $DRY_RUN; then
  print_plan
  if [[ -z "$RULES_HASH" ]]; then
    echo "DRY_RUN_RESULT=UNKNOWN"
    echo "DRY_RUN_REASON=agents-md-unreadable"
    exit 3
  fi
  eval "$(profile_query tier "$TIER")"
  CUR_HARNESS_SHA=$(git hash-object "$BENCHMARK_SH" 2>/dev/null | cut -c1-12)
  # Converged only if the entry also covers every requested test — a new
  # test (e.g. t_r1) leaves its rule unmeasured until the tier is rerun.
  MISSING_TESTS=""
  for _t in ${TESTS//,/ }; do [[ ",$T_TESTS," == *",$_t,"* ]] || MISSING_TESTS+="$_t "; done
  if [[ "$T_RULES_HASH" == "$RULES_HASH" && "$T_MODEL" == "$MODEL" && "$T_PROVIDER" == "$PROVIDER" && -z "$MISSING_TESTS" \
        && -n "$CUR_HARNESS_SHA" && "$T_HARNESS_SHA" == "$CUR_HARNESS_SHA" ]]; then
    echo "  $TIER already measured for this model at this rules hash ($T_OVERALL, $T_DATE)."
    echo "DRY_RUN_RESULT=CONVERGED"
  else
    echo "  Would run benchmark.sh and write validated_tiers.$TIER"
    echo "  (current entry: model='${T_MODEL:-none}' rules_hash='${T_RULES_HASH:-none}')."
    [[ -n "$MISSING_TESTS" && -n "$T_MODEL" ]] && echo "  (current entry lacks tests: ${MISSING_TESTS% })"
    [[ -n "$T_MODEL" && "$T_HARNESS_SHA" != "$CUR_HARNESS_SHA" ]] && echo "  (harness changed: entry harness_sha='${T_HARNESS_SHA:-none}', current='${CUR_HARNESS_SHA:-unknown}')"
    echo "DRY_RUN_RESULT=PENDING"
  fi
  exit 0
fi

[[ -n "$RULES_HASH" ]] || { echo "ERROR: cannot read AGENTS.md under test (${AGENTS_MD:-none}); set BENCHMARK_PROJECT_CWD" >&2; exit 2; }
print_plan
echo ""

# --- Run benchmark ---
# Persistent: recorded baselines must survive reboots (/tmp is tmpfs — 2026-11-17 crash lost all evidence)
BENCH_STATE_DIR="${AGENTFS_BENCH_DIR:-$HOME/.local/state/agentfs/benchmarks}"
mkdir -p "$BENCH_STATE_DIR"
OUTPUT_DIR="$BENCH_STATE_DIR/compliance-${TIER}-$(date +%Y%m%d_%H%M%S)"
if [[ -n "${BENCHMARK_OUTPUT_FILE:-}" ]]; then
  echo "REPLAY MODE: parsing $BENCHMARK_OUTPUT_FILE instead of running benchmark.sh"
  OUTPUT_DIR="${BENCHMARK_OUTPUT_DIR:-$OUTPUT_DIR}"
  BENCHMARK_OUTPUT=$(cat "$BENCHMARK_OUTPUT_FILE")
else
  echo "Running benchmark..."
  BENCH_RC=0
  BENCHMARK_OUTPUT=$(BENCHMARK_PROJECT_CWD="$PROJECT_CWD" bash "$BENCHMARK_SH" \
    --provider "$PROVIDER" --model "$MODEL" --tests "$TESTS" \
    --runs "$RUNS" ${RUNS_OVERRIDE:+--runs-override "$RUNS_OVERRIDE"} --output "$OUTPUT_DIR" 2>&1) || BENCH_RC=$?
  echo "$BENCHMARK_OUTPUT"
  if [[ $BENCH_RC -eq 2 ]]; then
    echo "ERROR: benchmark.sh configuration error (exit 2) — profile not updated" >&2; exit 1
  fi
fi

TOTAL=$(grep -m1 '^- Total:' <<< "$BENCHMARK_OUTPUT" | awk '{print $3}' || true)
PASSED=$(grep -m1 '^- Passed:' <<< "$BENCHMARK_OUTPUT" | awk '{print $3}' || true)
if [[ -z "$TOTAL" || -z "$PASSED" || "$TOTAL" == "0" ]]; then
  echo "ERROR: could not parse benchmark results (or zero tests ran) — profile not updated" >&2
  exit 1
fi

# --- Write profile ---
# Rows for exactly the requested tests (was a hardcoded list that silently
# dropped t_r1 — 2026-11-17). Fail loud if the row count disagrees with
# the benchmark's own total.
TESTS_RE=$(sed 's/,/|/g' <<< "$TESTS")
RESULT_ROWS=$(grep -E "^\| ($TESTS_RE) \|" <<< "$BENCHMARK_OUTPUT" || true)
ROWS_N=$(grep -c . <<< "$RESULT_ROWS" || true)
ERR_N=$(grep -m1 '^- Errored' <<< "$BENCHMARK_OUTPUT" | grep -oE '[0-9]+$' || echo 0)
if [[ "$ROWS_N" -ne $(( TOTAL + ${ERR_N:-0} )) ]]; then
  echo "ERROR: parsed $ROWS_N result rows but benchmark reports Total=$TOTAL + Errored=${ERR_N:-0} — profile not updated" >&2
  exit 1
fi
HARNESS_SHA=$(git hash-object "$BENCHMARK_SH" 2>/dev/null | cut -c1-12 || echo unknown)

# Tiers may record concurrently: serialize the profile read-modify-write.
exec 9>"${PROFILE_YAML}.lock"
flock -w 900 9 || { echo "ERROR: timed out waiting for profile lock ${PROFILE_YAML}.lock" >&2; exit 1; }
RESULT_ROWS="$RESULT_ROWS" python3 - "$PROFILE_YAML" "$TIER" "$PROVIDER" "$MODEL" "$RUNS" \
  "$AGENTS_MD_VERSION" "$RULES_HASH" "$HARNESS_SHA" "$OUTPUT_DIR" "$RUNS_OVERRIDE" <<'PY'
import os, re, sys, yaml, datetime
path, tier, provider, model, runs, ver, rhash, hsha, outdir, runs_override = sys.argv[1:11]
text = open(path).read()
d = yaml.safe_load(text) or {}

# per-test counts from report rows: | t_r2 | run 1 | ✅ | verdict |
cnt = {}; errored = {}
for line in os.environ.get("RESULT_ROWS", "").splitlines():
    cols = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cols) < 3: continue
    if cols[2].startswith("⚠"):   # provider error after retries — not a compliance result
        errored[cols[0]] = errored.get(cols[0], 0) + 1
        continue
    p, t = cnt.setdefault(cols[0], [0, 0])
    cnt[cols[0]] = [p + (cols[2] == "✅"), t + 1]

def rate(*tests):
    p = sum(cnt.get(t, [0, 0])[0] for t in tests); t = sum(cnt.get(t, [0, 0])[1] for t in tests)
    return (f"{p * 100 // t}%" if t else "not_tested"), p, t

RULE_TESTS = {
    "R1_signal_dispatch": ("t_r1",),
    "R2_pre_flight": ("t_r2", "t_r2b", "t_r2git"),
    "R3_session_canary": ("t1",),
    "R4_conflict_resolution": ("t_r4x", "t_r4s", "t_ii"),
    "R6_scope_post_write": ("t_r6",),
    "R7_dry_run_gate": ("t_r7dry", "t_r7dry_conv", "t_r7dry_pend"),
}
per_rule = {}; rule_rates = []
for r, ts in RULE_TESTS.items():
    lbl, p, t = rate(*ts)
    per_rule[r] = lbl
    if t: rule_rates.append(p / t)
per_rule["R5_checkpoint"] = "not_tested"
# Reported, not pooled into any rule.
DIAGNOSTIC_TESTS = {"t_r3c_implicit": "R3-diag", "t_r3c_explicit": "R3-diag"}
diagnostics = {t: f"{cnt[t][0]}/{cnt[t][1]}" for t in DIAGNOSTIC_TESTS if t in cnt}
per_rule = dict(sorted(per_rule.items()))
scored = {t: v for t, v in cnt.items() if t not in DIAGNOSTIC_TESTS}   # diagnostics excluded
total_p = sum(v[0] for v in scored.values()); total_t = sum(v[1] for v in scored.values())
if total_t == 0 or not rule_rates:
    sys.exit("ERROR: no per-test rows parsed")
overall = f"{int(sum(rule_rates) / len(rule_rates) * 100)}%"
overall_runs = f"{total_p * 100 // total_t}%"
rule_of = {t: r.split("_")[0] for r, ts in RULE_TESTS.items() for t in ts}
rule_of.update(DIAGNOSTIC_TESTS)
fms = [{"rule": rule_of.get(t, "?"), "test": t, "rate": f"{(c[1]-c[0]) * 100 // c[1]}% fail"}
       for t, c in sorted(cnt.items()) if c[0] < c[1]]

rep = (d.get("representatives") or {}).get(tier) or {}
entry = {
    "model": model, "provider": provider,
    "date": datetime.date.today().isoformat(),
    "agents_md_version": ver, "rules_hash": rhash, "harness_sha": hsha,
    "runs_per_test": int(runs), "runs_override": runs_override or None,
    "tests": total_t, "pass": total_p, "overall": overall,
    "overall_basis": "mean of per-rule rates", "overall_runs_weighted": overall_runs,
    "per_test": {t: f"{c[0]}/{c[1]}" for t, c in sorted(cnt.items())},
    # ~-relative: absolute /home/<user> paths trip pre-push-scan (hardcoded paths)
    "per_rule": per_rule, "failure_modes": fms,
    "output_dir": ("~" + outdir[len(os.path.expanduser("~")):]) if outdir.startswith(os.path.expanduser("~") + "/") else outdir,
}
if diagnostics:
    entry["diagnostics"] = diagnostics
if errored:
    entry["provider_errors_excluded"] = errored
if rep.get("model") == model and rep.get("served_model"):
    entry["served_model"] = rep["served_model"]
d.setdefault("validated_tiers", {})[tier] = entry

required = d.get("required_tiers", ["T2", "T3", "T4"])
vt = d["validated_tiers"]
all_current = all(vt.get(t, {}).get("rules_hash") == rhash for t in required)
mt = d.get("minimum_tier", "T2")
if tier == mt:
    d["minimum_tier_rate"] = overall
d["pending_benchmarks"] = [t for t in required if vt.get(t, {}).get("rules_hash") != rhash]

# evolution: one entry per rules hash
evo = d.setdefault("evolution", [])
e = next((x for x in evo if x.get("rules_hash") == rhash), None)
if e is None:
    e = {"version": ver, "rules_hash": rhash, "date": entry["date"], "note": "pending note"}
    evo.append(e)
e[f"{tier}_overall"] = overall
e[f"{tier}_model"] = model

# --- Re-emit: header (everything before the Validated Tiers marker) is
# preserved verbatim except version/hash; data sections are regenerated.
marker = "# ── Validated Tiers"
if marker not in text:
    sys.exit(f"ERROR: profile lacks '{marker}' section marker (schema ≥1.2 required)")
head = text[:text.index(marker)]
head = re.sub(r'agents_md_version:\s*"[^"]*"', f'agents_md_version: "{ver}"', head) if all_current else head
if all_current:
    head = re.sub(r'agents_md_rules_hash:\s*"[^"]*"', f'agents_md_rules_hash: "{rhash}"', head)

def dump(obj):
    return yaml.safe_dump(obj, sort_keys=False, allow_unicode=True, width=88, default_flow_style=False)

order = ["T4", "T3", "T2", "T1"]
vt_sorted = {k: vt[k] for k in order if k in vt}
tail = (
    "# ── Validated Tiers ──────────────────────────────────────────────────────\n"
    "# Written by update-compliance.sh. Do not hand-edit.\n\n"
    + dump({"validated_tiers": vt_sorted}) +
    "\n# ── Summary ──────────────────────────────────────────────────────────────\n\n"
    + dump({"minimum_tier": mt, "minimum_tier_rate": d.get("minimum_tier_rate", "")}) +
    "\n# ── Evolution History ────────────────────────────────────────────────────\n\n"
    + dump({"evolution": evo})
)
if d.get("archived_baselines"):
    tail += ("\n# ── Archived Baselines (superseded tier representatives) ─────────────────\n\n"
             + dump({"archived_baselines": d["archived_baselines"]}))
tail += ("\n# ── Pending ──────────────────────────────────────────────────────────────\n\n"
         + dump({"pending_benchmarks": d["pending_benchmarks"]}))
new = head + tail
yaml.safe_load(new)  # must still parse
open(path, "w").write(new)

print(f"✅ validated_tiers.{tier}: {model} ({provider}) {overall} [{total_p}/{total_t}]")
for k, v in per_rule.items(): print(f"   {k}: {v}")
if all_current:
    print(f"   All required tiers current → top-level rules hash set to {rhash}")
else:
    print(f"   Still pending at this rules hash: {', '.join(d['pending_benchmarks'])} (top-level hash unchanged)")
PY

echo ""
echo "Output directory: $OUTPUT_DIR"
echo "Profile: $PROFILE_YAML"
