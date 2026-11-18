#!/usr/bin/env bash
# runtime-compliance.sh — Deterministic runtime CECX dimensions for AGENTS.md,
# computed from the compliance profile (no LLM, no benchmark run).
#
# Usage:
#   runtime-compliance.sh [--frontier T4] [--targets T3,T2] [--yaml]
#
# Source: PROFILE_YAML (default ~/.agents/skills/agentfs-setup/compliance-profile.yaml),
# written by update-compliance.sh / run-parallel.sh. Read-only.
#
# Dimensions (schema: skills/schemas/operable-agents-md.yaml, phase runtime),
# evaluated per target tier against the frontier tier:
#   rule_pass_rate          mean of tested per_rule rates (R5 'not_tested' excluded)  >= 0.90
#   frontier_target_delta   frontier rule_pass_rate - target rule_pass_rate             <= 0.10
#   per_rule_comprehension  count of tested rules with target rate < 80%                == 0
#   stochastic_variance     share of pooled tests with mixed outcomes (0 < k < n)        <= 0.20
#   no_fabrication          not computed here — the benchmark graders require the full
#                           tool chain per run, so fabrication shows up as rule FAILs.
#
# Exit: 0 printed; 2 profile missing / tier not recorded.

set -euo pipefail
FRONTIER=T4; TARGETS=T3,T2; FMT=text
while [[ $# -gt 0 ]]; do
  case "$1" in
    --frontier) FRONTIER="$2"; shift 2 ;;
    --targets)  TARGETS="$2"; shift 2 ;;
    --yaml)     FMT=yaml; shift ;;
    -h|--help)  sed -n 2,20p "$0"; exit 0 ;;
    *) echo "ERROR: unknown argument '$1'" >&2; exit 2 ;;
  esac
done
PROFILE="${PROFILE_YAML:-$HOME/.agents/skills/agentfs-setup/compliance-profile.yaml}"
[[ -f "$PROFILE" ]] || { echo "ERROR: profile not found: $PROFILE" >&2; exit 2; }

python3 - "$PROFILE" "$FRONTIER" "$TARGETS" "$FMT" <<'PY'
import sys, re, yaml
path, frontier, targets, fmt = sys.argv[1], sys.argv[2], sys.argv[3].split(","), sys.argv[4]
d = yaml.safe_load(open(path)) or {}
vt = d.get("validated_tiers") or {}
for t in [frontier] + targets:
    if t not in vt:
        sys.exit(f"ERROR: tier {t} not recorded in {path}")

def pct(v):
    m = re.match(r"^\s*([0-9.]+)\s*%?\s*$", str(v))
    return float(m.group(1)) / 100 if m else None

def rules(t):
    return {k: pct(v) for k, v in (vt[t].get("per_rule") or {}).items() if pct(v) is not None}

def mean(xs): return sum(xs) / len(xs) if xs else 0.0

def kn(v):
    m = re.match(r"^\s*(\d+)\s*/\s*(\d+)", str(v))
    return (int(m.group(1)), int(m.group(2))) if m else None

def variance_share(t):
    diag = set((vt[t].get("diagnostics") or {}).keys())
    pairs = [kn(v) for k, v in (vt[t].get("per_test") or {}).items() if k not in diag]
    pairs = [p for p in pairs if p and p[1] > 1]
    return (sum(1 for k, n in pairs if 0 < k < n) / len(pairs)) if pairs else 0.0, len(pairs)

f_rate = mean(list(rules(frontier).values()))
out = {"source": path, "frontier": {"tier": frontier, "model": vt[frontier].get("model"),
       "rule_pass_rate": round(f_rate, 3)}, "targets": {}}
for t in targets:
    r = rules(t); rate = mean(list(r.values()))
    weak = sorted(k for k, v in r.items() if v < 0.80)
    var, ntests = variance_share(t)
    dims = {
        "rule_pass_rate":         {"value": round(rate, 3), "target": ">= 0.90", "pass": rate >= 0.90},
        "frontier_target_delta":  {"value": round(f_rate - rate, 3), "target": "<= 0.10", "pass": (f_rate - rate) <= 0.10},
        "per_rule_comprehension": {"value": len(weak), "target": "0", "pass": not weak, "rules": weak},
        "stochastic_variance":    {"value": round(var, 3), "target": "<= 0.20", "pass": var <= 0.20, "tests": ntests},
    }
    out["targets"][t] = {"model": vt[t].get("model"), "agents_md_version": vt[t].get("agents_md_version"),
                         "date": str(vt[t].get("date")), "per_rule": vt[t].get("per_rule"),
                         "dimensions": dims, "pass": all(x["pass"] for x in dims.values())}

if fmt == "yaml":
    print(yaml.safe_dump(out, sort_keys=False, allow_unicode=True).rstrip())
else:
    print(f"Runtime compliance (source: {path})")
    print(f"Frontier {frontier} {out['frontier']['model']}: rule_pass_rate {f_rate:.0%}")
    for t, e in out["targets"].items():
        print(f"\n{t} {e['model']} (v{e['agents_md_version']}, {e['date']}) — {'PASS' if e['pass'] else 'FAIL'}")
        for n, x in e["dimensions"].items():
            v = f"{x['value']:.0%}" if isinstance(x["value"], float) else x["value"]
            extra = f" {x['rules']}" if x.get("rules") else ""
            print(f"  {'✅' if x['pass'] else '❌'} {n:24s} {v:>5}  (target {x['target']}){extra}")
PY
