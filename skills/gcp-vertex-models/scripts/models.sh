#!/usr/bin/env bash
# models.sh — Read-only queries over the probe cache (or any model-name list).
# Usage:
#   bash models.sh list    [--json] [--region R] [--max-age-days N]
#   bash models.sh default [--family opus|sonnet|haiku] [--region R] [--max-age-days N]
#   <names on stdin> | bash models.sh rank [--family F]
# Exit codes: 0 = ok, 1 = no cache / no usable model, 2 = usage error
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "gcp-vertex-models" "1.0.0" 2>/dev/null || true

CACHE_FILE="${GCP_VERTEX_MODELS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gcp-vertex-models/models.json}"
MODE="${1:-}"; [[ $# -gt 0 ]] && shift
JSON=false; FAMILY=""; REGION=""; MAX_AGE=7

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)         JSON=true; shift ;;
    --family)       FAMILY="${2:?}"; shift 2 ;;
    --region)       REGION="${2:?}"; shift 2 ;;
    --max-age-days) MAX_AGE="${2:?}"; shift 2 ;;
    --cache)        CACHE_FILE="${2:?}"; shift 2 ;;
    -h|--help)      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$MODE" in list|default|rank) ;; *) echo "Usage: models.sh list|default|rank [options]" >&2; exit 2 ;; esac
case "$FAMILY" in ""|opus|sonnet|haiku) ;; *) echo "bad --family: $FAMILY (opus|sonnet|haiku)" >&2; exit 2 ;; esac

if [[ "$MODE" != rank && ! -f "$CACHE_FILE" ]]; then
  echo "❌ No probe cache at $CACHE_FILE — run: refresh vertex models (scripts/probe-models.sh)"
  trace_step 1 "$MODE" 1 "no cache" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
fi

M_NAMES=""
[[ "$MODE" == rank ]] && M_NAMES="$(cat)"
export M_NAMES
export M_MODE="$MODE" M_JSON="$JSON" M_FAMILY="$FAMILY" M_REGION="$REGION" M_MAX_AGE="$MAX_AGE" M_CACHE="$CACHE_FILE"
set +e
python3 - <<'PYEOF'
import os, sys, json, re, datetime
mode, fam, region = os.environ["M_MODE"], os.environ["M_FAMILY"], os.environ["M_REGION"]
as_json, max_age = os.environ["M_JSON"] == "true", int(os.environ["M_MAX_AGE"])

FAMILY_ORDER = {"opus": 0, "sonnet": 1, "haiku": 2}
def parse(name):
    # claude-<family>-<major>[-<minor>] ; anything else is unrankable
    m = re.fullmatch(r"claude-(opus|sonnet|haiku)-(\d+)(?:-(\d+))?", name)
    if not m:
        return None
    return m.group(1), int(m.group(2)), int(m.group(3) or 0)
def rank(names):
    ranked = [(parse(n), n) for n in names if parse(n)]
    if fam:
        ranked = [x for x in ranked if x[0][0] == fam]
    ranked.sort(key=lambda x: (FAMILY_ORDER[x[0][0]], -x[0][1], -x[0][2]))
    return [n for _, n in ranked]

if mode == "rank":
    names = [l.split()[0] for l in os.environ.get("M_NAMES", "").splitlines() if l.strip()]
    out = rank(names)
    print("\n".join(out))
    sys.exit(0 if out else 1)

doc = json.load(open(os.environ["M_CACHE"]))
gen = datetime.datetime.strptime(doc["generated_at"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
age = (datetime.datetime.now(datetime.timezone.utc) - gen).total_seconds() / 86400
stale = age > max_age
def usable_region(m):
    if region:
        return region if m["regions"].get(region) == 200 else None
    return m["region"]
usable = {m["model"]: usable_region(m) for m in doc["models"] if usable_region(m)}
header = f'Probed: {doc["generated_at"]} ({age:.1f} days ago) project={doc["project"]} credential={doc["credential"]["identity"]}'
warn = f"⚠️  Cache older than {max_age} days — run: refresh vertex models" if stale else ""

if mode == "list":
    if as_json:
        print(json.dumps({**doc, "age_days": round(age, 2), "stale": stale}, indent=2)); sys.exit(0 if usable else 1)
    regions = doc["regions"]
    w = max(len(m["model"]) for m in doc["models"]) + 2
    print(header)
    if warn: print(warn)
    print()
    print(f'{"MODEL":<{w}}' + "".join(f"{r:<12}" for r in regions) + "STATUS / RECOMMENDED")
    for m in doc["models"]:
        cells = "".join(f'{str(m["regions"].get(r, "-")):<12}' for r in regions)
        rec = f'-> {usable_region(m)}' if usable_region(m) else ""
        print(f'{m["model"]:<{w}}{cells}{m["status"]} {rec}')
    print(f"\nUsable: {len(usable)}" + (f" (region filter: {region})" if region else ""))
    sys.exit(0 if usable else 1)

# default
order = rank(list(usable))
if not order:
    print("❌ No usable model" + (f" in family {fam}" if fam else "") + (f" in region {region}" if region else ""))
    sys.exit(1)
best = order[0]
print(f"{best} {usable[best]}")
print(header, file=sys.stderr)
if warn: print(warn, file=sys.stderr)
print("Ranking (family opus>sonnet>haiku, then newest version): " + ", ".join(order), file=sys.stderr)
PYEOF
rc=$?
set -e
trace_step 1 "$MODE" "$rc" "family=$FAMILY region=$REGION" 2>/dev/null || true
trace_end 2>/dev/null || true
exit $rc
