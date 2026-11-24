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

python3 - "$SHEET" "$SKILL_MD" "$QUIET" <<'PY'
import sys, re, yaml
sheet, skill_md, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
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

if not is_ref:
    sig = "INVALID"
elif ver != tmpl:
    sig = "STALE"
else:
    sig = "CURRENT"

if not quiet:
    print(f"Static sheet: {sheet}")
    print(f"  sheet version     v{ver}   template v{tmpl}")
    print(f"  quality           {q.get('aggregate_score', '—')} ({q.get('band', '—')}), evaluated {q.get('evaluated', '—')}")
    print(f"  operable.build    evaluated {b.get('evaluated', '—')}")
    if is_ref:
        print(f"  operable.runtime  reference → {rt.get('derived_from')} via {rt.get('computed_by')}")
    else:
        print(f"  operable.runtime  NOT a stateless reference (stored fields: {', '.join(stateful) or 'missing derived_from/computed_by'})")
    if sig == "STALE":
        print('  → run "upgrade agentfs" to refresh (needs SDM; T4 fallback is report-only)')
print(f"STATIC_SHEET={sig}")
PY
