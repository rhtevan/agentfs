#!/usr/bin/env bash
# static-sheet-status.sh — Staleness and shape check for the base skill's
# static record (artifacts/agents-md/scores.yaml). Read-only.
#
# Usage:
#   static-sheet-status.sh [--quiet]
#
# Compares the sheet's `version` with the template version
# (agentfs-setup SKILL.md metadata.version, the same value template-check.sh
# A9 enforces) and checks that operable.runtime is a stateless reference
# (derived_from + computed_by only; no pass/evaluated/score/note), per
# evaluation-methodology.md §4.
#
# Output (last line is the signal):
#   STATIC_SHEET=CURRENT | STALE | INVALID
#   CURRENT  sheet version == template version and runtime entry is a reference
#   STALE    sheet version != template version → run "upgrade agentfs"
#   INVALID  runtime entry stores state (pass/evaluated/...) or sheet unreadable
#
# Content hash (2026-11-24): when the sheet records template_hash {rules,
# soul}, the hashes from template-hash.sh decide CURRENT/STALE (a version
# bump with unchanged prose stays CURRENT; changed prose with the same
# version is STALE). Without template_hash the version comparison applies.
# A referenced evidence file that does not exist makes the sheet INVALID.
#
# Scorer (F30): quality.scorer / operable.build.scorer absent = SDM. A value
# "t4-fallback:<model>" means a calibrated T4 score (t4-static-score.sh);
# the sheet is still CURRENT, the detail line says T4 and that an SDM
# re-score is pending. A T4 score without a passing quality.calibration
# is INVALID.
#
# --quiet prints only the signal line.
# Exit: 0 always when the check ran (read the signal); 2 file missing.
#
# Env overrides: SCORES_YAML, SETUP_SKILL_MD.

set -euo pipefail
QUIET=false
[[ "${1:-}" == "--quiet" ]] && QUIET=true
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && { sed -n 2,23p "$0"; exit 0; }

SHEET="${SCORES_YAML:-$HOME/.agents/skills/agentfs-setup/artifacts/agents-md/scores.yaml}"
SKILL_MD="${SETUP_SKILL_MD:-$HOME/.agents/skills/agentfs-setup/SKILL.md}"
[[ -f "$SHEET" ]]    || { echo "ERROR: static sheet not found: $SHEET" >&2; exit 2; }
[[ -f "$SKILL_MD" ]] || { echo "ERROR: agentfs-setup SKILL.md not found: $SKILL_MD" >&2; exit 2; }

HASHES="$(bash "$(dirname "${BASH_SOURCE[0]}")/template-hash.sh" 2>/dev/null || true)"
python3 - "$SHEET" "$SKILL_MD" "$QUIET" "$HASHES" <<'PY'
import sys, re, os, yaml
sheet, skill_md, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
cur = dict(l.split("=", 1) for l in sys.argv[4].split() if "=" in l)
m = re.search(r'^\s*version:\s*"?([0-9.]+)"?', open(skill_md).read(), re.M)
tmpl = m.group(1) if m else "unknown"
try:
    d = yaml.safe_load(open(sheet)) or {}
except yaml.YAMLError as e:
    print(f"ERROR: {e}"); print("STATIC_SHEET=INVALID"); sys.exit(0)

ver = str(d.get("version", "unknown"))
q = (d.get("quality") or {})
b = ((d.get("operable") or {}).get("build") or {})
rt = ((d.get("operable") or {}).get("runtime") or {})
stateful = sorted(k for k in rt if k in ("pass", "evaluated", "score", "aggregate_score", "note", "dimensions"))
is_ref = bool(rt.get("derived_from")) and bool(rt.get("computed_by")) and not stateful

scorers = {q.get("scorer") or "sdm", b.get("scorer") or "sdm"}
t4 = any(x.startswith("t4-fallback") for x in scorers)
cal_ok = ((q.get("calibration") or {}).get("result") == "PASS")
th = d.get("template_hash") or {}
base = os.path.dirname(sheet)
ev = [x for x in {q.get("evidence"), b.get("evidence"), (q.get("calibration") or {}).get("evidence")} if x]
ev_missing = [x for x in ev if not os.path.isfile(os.path.join(base, x))]
if th and cur.get("RULES_HASH") and cur.get("SOUL_HASH"):
    changed = [k for k, c in (("rules", "RULES_HASH"), ("soul", "SOUL_HASH")) if str(th.get(k)) != cur[c]]
    hash_note = "content unchanged" if not changed else "changed since scoring: " + ", ".join(changed)
else:
    changed = None
    hash_note = "not recorded (version comparison only)" if not th else "current hash unavailable"
if not is_ref or (t4 and not cal_ok) or ev_missing:
    sig = "INVALID"
elif (changed if changed is not None else ver != tmpl):
    sig = "STALE"
else:
    sig = "CURRENT"

if not quiet:
    print(f"Static sheet: {sheet}")
    print(f"  sheet version     v{ver}   template v{tmpl}")
    print(f"  quality           {q.get('aggregate_score', '—')} ({q.get('band', '—')}), evaluated {q.get('evaluated', '—')}")
    print(f"  operable.build    evaluated {b.get('evaluated', '—')}")
    print(f"  template hash     {hash_note}")
    if ev:
        print(f"  evidence          {', '.join(sorted(ev))}" + (f"  MISSING: {', '.join(ev_missing)}" if ev_missing else ""))
    if t4:
        c = q.get("calibration") or {}
        print(f"  scorer            {', '.join(sorted(scorers))} — calibration {c.get('result', 'MISSING')}"
              f" ({c.get('t4_median', '—')} vs SDM {c.get('reference', '—')}); SDM re-score pending")
    else:
        print("  scorer            sdm")
    if is_ref:
        print(f"  operable.runtime  reference → {rt.get('derived_from')} via {rt.get('computed_by')}")
    else:
        print(f"  operable.runtime  NOT a stateless reference (stored fields: {', '.join(stateful) or 'missing derived_from/computed_by'})")
    if sig == "STALE":
        print('  → run "upgrade agentfs" to refresh (SDM, or the calibrated T4 fallback when SDM is down)')
print(f"STATIC_SHEET={sig}")
PY
