#!/usr/bin/env bash
# 2026-11-24-ge-score-map.sh — Recompute stored '>=' dimension scores after the
# sdm-evaluate.sh score-map fix. No re-grade: the old '>=' score was exactly
# round(raw / max_scale * 100), so the model's raw bucket is recovered from it.
#
# Usage: 2026-11-24-ge-score-map.sh [--dry-run | --apply] [--root DIR]
#   --dry-run (default) list every change; write nothing
#   --apply             edit scores.yaml files in place (score/pass lines,
#                       aggregate_score/band/pass_rate of the changed axis)
#                       and append one history entry (type score-map)
#   --root              skills root (default ~/.agents/skills)
#
# Dimensions ('>=' targets; target bucket; max_scale):
#   quality.yaml       script_coverage 4/4 · step_clarity 2/3 · prose_executability 2/3
#   observable.yaml    cnl_compliance 4/4 (old == new: listed for completeness)
#   operable-agents-md build: has_bones 1/4 · has_muscle 4/4 · has_harness 4/4
# Only these schemas are matched (a dimension under another schema is skipped,
# e.g. ordinary skills' boolean has_* build dimensions).
#
# Output: one line per change, a summary, then DRY_RUN_RESULT=PENDING|CONVERGED
# (dry run) or APPLIED=<n files>. Exit 0 ran · 1 error.
set -euo pipefail
MODE=dry ROOT="$HOME/.agents/skills"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE=dry; shift ;;
    --apply) MODE=apply; shift ;;
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) sed -n 2,22p "$0"; exit 0 ;;
    *) echo "unknown argument $1" >&2; exit 1 ;;
  esac
done
MODE="$MODE" ROOT="$ROOT" python3 - <<'PY'
import os, re, glob, yaml, datetime
MODE, ROOT = os.environ["MODE"], os.environ["ROOT"]
# (axis path, schema) -> {dim: (target_bucket, max_scale)}
MAP = {
    (("quality",), "quality.yaml"): {"script_coverage": (4, 4), "step_clarity": (2, 3), "prose_executability": (2, 3)},
    (("observable",), "observable.yaml"): {"cnl_compliance": (4, 4)},
    (("operable", "build"), "operable-agents-md.yaml"): {"has_bones": (1, 4), "has_muscle": (4, 4), "has_harness": (4, 4)},
}
def new_score(raw, tb): return 100 if raw >= tb else round(100 * raw / tb)
def band(a): return "Operable" if a >= 90 else "Tunable" if a >= 75 else "Re-engineer" if a >= 50 else "Redesign"

files = sorted(set(glob.glob(f"{ROOT}/*/scores.yaml") + glob.glob(f"{ROOT}/*/artifacts/*/scores.yaml")))
changes, flips, applied, skipped = [], [], 0, []
now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
for f in files:
    try: d = yaml.safe_load(open(f)) or {}
    except Exception as e: skipped.append(f"{f}: unreadable ({e})"); continue
    rel = os.path.relpath(f, ROOT)
    edits = []   # (axis_path, dim, old, new, oldpass, newpass)
    axis_upd = {}
    for (path, schema), dims in MAP.items():
        node = d
        for k in path: node = (node or {}).get(k) if isinstance(node, dict) else None
        if not isinstance(node, dict) or node.get("schema") != schema: continue
        dd = node.get("dimensions") or {}
        for dim, (tb, mx) in dims.items():
            v = dd.get(dim)
            if not isinstance(v, dict) or "score" not in v: continue
            old = v["score"]
            raw = round(old * mx / 100)
            if not isinstance(old, (int, float)) or abs(raw * 100 / mx - old) > 1:
                skipped.append(f"{rel}: {'.'.join(path)}.{dim} score {old} is not on the {mx}-step grid"); continue
            ns, np_ = new_score(raw, tb), raw >= tb
            if ns != old or bool(v.get("pass")) != np_:
                edits.append((path, dim, old, ns, v.get("pass"), np_))
                dd[dim]["score"], dd[dim]["pass"] = ns, np_
        if any(e[0] == path for e in edits) and "aggregate_score" in node:
            sc = [x["score"] for x in dd.values() if isinstance(x, dict) and isinstance(x.get("score"), (int, float))]
            agg = sum(sc) / len(sc)
            pr = round(100 * sum(1 for x in dd.values() if isinstance(x, dict) and x.get("pass")) / len(sc), 1)
            axis_upd[path] = (node.get("aggregate_score"), agg, node.get("band"), band(agg), pr if "pass_rate" in node else None)
    if not edits: continue
    for p, dim, o, n, op, np_ in edits:
        changes.append(f"{rel}: {'.'.join(p)}.{dim} {o}->{n}" + (f" pass {op}->{np_}" if bool(op) != np_ else ""))
        if bool(op) != np_: flips.append(f"{rel}: {dim} {'pass->fail' if op else 'fail->pass'}")
    for p, (oa, na, ob, nb, pr) in axis_upd.items():
        changes.append(f"{rel}:   {'.'.join(p)} aggregate {round(oa,1) if isinstance(oa,(int,float)) else oa}->{round(na,1)} band {ob}->{nb}")
    if MODE != "apply": continue
    # ---- text edits (keep comments/format) ----
    L = open(f).read().split("\n")
    def find_block(path):
        """line range [start, end) of the mapping at path (block style)."""
        start, ind, lo = 0, -2, len(L)
        for k in path:
            for i in range(start, lo):
                m = re.match(r"^(\s*)" + re.escape(k) + r":\s*(#.*)?$", L[i])
                if m and len(m.group(1)) > ind:
                    ind, start = len(m.group(1)), i + 1
                    lo = next((j for j in range(start, len(L)) if L[j].strip() and not L[j].lstrip().startswith("#")
                               and len(L[j]) - len(L[j].lstrip()) <= ind), len(L))
                    break
            else: raise SystemExit(f"cannot locate {'.'.join(path)} in {f}")
        return start, lo
    for p, dim, o, n, op, np_ in edits:
        s0, e0 = find_block(p + ("dimensions",))
        for i in range(s0, e0):
            m = re.match(r"^(\s*)" + re.escape(dim) + r":\s*\{(.*)\}\s*(#.*)?$", L[i])
            if m:   # flow style
                L[i] = re.sub(r"score:\s*[0-9.]+", f"score: {n}", L[i], 1)
                L[i] = re.sub(r"pass:\s*(true|false)", f"pass: {str(np_).lower()}", L[i], 1); break
            if re.match(r"^\s*" + re.escape(dim) + r":\s*$", L[i]):
                ds, de = find_block(p + ("dimensions", dim))
                for j in range(ds, de):
                    L[j] = re.sub(r"^(\s*score:\s*)[0-9.]+", rf"\g<1>{n}", L[j])
                    L[j] = re.sub(r"^(\s*pass:\s*)(true|false)", rf"\g<1>{str(np_).lower()}", L[j])
                break
        else: raise SystemExit(f"cannot locate {dim} in {f}")
    for p, (oa, na, ob, nb, pr) in axis_upd.items():
        s0, e0 = find_block(p)
        for i in range(s0, e0):
            L[i] = re.sub(r"^(\s*aggregate_score:\s*)[0-9.]+", rf"\g<1>{round(na, 1)}", L[i])
            L[i] = re.sub(r"^(\s*band:\s*)\S+", rf"\g<1>{nb}", L[i]) if re.match(r"^\s*band:", L[i]) and len(L[i]) - len(L[i].lstrip()) == len(L[s0]) - len(L[s0].lstrip()) else L[i]
            if pr is not None: L[i] = re.sub(r"^(\s*pass_rate:\s*)[0-9.]+", rf"\g<1>{pr}", L[i])
    # history entry
    h = next((i for i, l in enumerate(L) if re.match(r"^history:\s*$", l)), None)
    note = "score-map fix (sdm-evaluate.sh '>=' targets: 100 at/above target, share of target below; ratio threshold = bucket containing t). Recomputed from stored scores, no re-grade."
    if h is not None:
        end = next((j for j in range(h + 1, len(L)) if L[j].strip() and not L[j].startswith((" ", "-", "#"))), len(L))
        while end > h + 1 and not L[end - 1].strip(): end -= 1
        item = next((re.match(r"^(\s*)-", L[j]).group(1) for j in range(h + 1, end) if re.match(r"^\s*-", L[j])), "  ")
        L[end:end] = [f'{item}- date: "{now}"', f"{item}  type: score-map", f'{item}  note: "{note}"']
    open(f, "w").write("\n".join(L))
    yaml.safe_load(open(f))   # must still parse
    applied += 1

for c in changes: print(c)
print(f"# files scanned {len(files)}; files changed {len({c.split(':')[0] for c in changes})}; dimension changes {sum(1 for c in changes if '->' in c and 'aggregate' not in c)}; pass/fail flips {len(flips)}")
for s in skipped: print("# skipped:", s)
if MODE == "apply": print(f"APPLIED={applied}")
else: print("DRY_RUN_RESULT=" + ("PENDING" if changes else "CONVERGED"))
PY
