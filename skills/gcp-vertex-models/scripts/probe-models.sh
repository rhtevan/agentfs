#!/usr/bin/env bash
# probe-models.sh — Discover which Anthropic Claude models a GCP project can
# actually call on Vertex AI, and in which region(s).
#
# Usage: bash probe-models.sh [--project P] [--regions r1,r2] [--models m1,m2]
#                             [--credentials FILE] [--format table|json|names]
#                             [--prefer global|regional] [--output FILE] [--no-cache]
#
# Exit codes: 0 = at least one model usable, 1 = none usable,
#             2 = usage error, 3 = authentication failure
#
# How it works
#   Vertex AI has no "what am I entitled to" API. So:
#   1. Candidate names = publisher catalog (v1beta1 publishers/anthropic/models,
#      names only — NOT entitlement) + built-in fallback list + --models extras.
#   2. Each candidate x region gets a 1-token rawPredict call. The HTTP status
#      is the only truthful availability signal.
#   3. The JSON result is also saved to the cache (default
#      ${XDG_CACHE_HOME:-~/.cache}/gcp-vertex-models/models.json) for list/default queries.
#
# Status codes per model/region
#   200 usable | 429 exists but quota-limited | 404 not offered to project/region
#   403 blocked (e.g. publisher data-sharing not enabled) | ERR network error
#
# Auth: google-auth. Credential order: --credentials, $GOOGLE_APPLICATION_CREDENTIALS,
#   ADC file. No dependency on `gcloud auth print-access-token`.
#
# Output contract (--format json) is consumed by setup.sh and other skills:
#   {"project","regions","credential":{"type","identity"},"generated_at",
#    "models":[{"model","status","region","regions":{"<region>":<code>}}]}
#   "region" = recommended region (usable one; see --prefer), or null.
#   Pass "global" to LiteLLM vertex_location / GCP_LOCATION for global.
set -euo pipefail

# Trace instrumentation (optional)
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "gcp-vertex-models" "1.0.0" 2>/dev/null || true

PROJECT="${ANTHROPIC_VERTEX_PROJECT_ID:-${GCP_PROJECT_ID:-}}"
REGIONS="global,us-east5"
EXTRA_MODELS=""
CREDS="${GOOGLE_APPLICATION_CREDENTIALS:-}"
FORMAT="table"
PREFER="global"
OUTPUT=""
CACHE_FILE="${GCP_VERTEX_MODELS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gcp-vertex-models/models.json}"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)     PROJECT="${2:?}"; shift 2 ;;
    --region|--regions) REGIONS="${2:?}"; shift 2 ;;
    --models)      EXTRA_MODELS="${2:?}"; shift 2 ;;
    --credentials) CREDS="${2:?}"; shift 2 ;;
    --format)      FORMAT="${2:?}"; shift 2 ;;
    --prefer)      PREFER="${2:?}"; shift 2 ;;
    --output)      OUTPUT="${2:?}"; shift 2 ;;
    --no-cache)    CACHE_FILE=""; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

case "$FORMAT" in table|json|names) ;; *) echo "bad --format: $FORMAT" >&2; exit 2 ;; esac
case "$PREFER" in global|regional) ;; *) echo "bad --prefer: $PREFER" >&2; exit 2 ;; esac

if [[ -z "$PROJECT" ]] && command -v gcloud >/dev/null 2>&1; then
  PROJECT=$(gcloud config get-value project 2>/dev/null || true)
fi
if [[ -z "$PROJECT" ]]; then
  echo "No project. Use --project or set ANTHROPIC_VERTEX_PROJECT_ID." >&2; exit 2
fi

# Pick a python that has google-auth (system first, then the litellm uv tool)
PY=""
for cand in python3 "${HOME}/.local/share/uv/tools/litellm/bin/python3"; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import google.auth' 2>/dev/null; then PY="$cand"; break; fi
done
if [[ -z "$PY" ]]; then
  echo "No python3 with google-auth found (pip install google-auth)." >&2; exit 3
fi

export PROBE_PROJECT="$PROJECT" PROBE_REGIONS="$REGIONS" PROBE_EXTRA="$EXTRA_MODELS" \
       PROBE_CREDS="$CREDS" PROBE_FORMAT="$FORMAT" PROBE_PREFER="$PREFER" PROBE_OUTPUT="$OUTPUT" \
       PROBE_CACHE="$CACHE_FILE"
trace_step 1 "probe" 0 "project=$PROJECT regions=$REGIONS" 2>/dev/null || true

set +e
"$PY" - <<'PYEOF'
import os, sys, json, datetime, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

project = os.environ["PROBE_PROJECT"]
regions = [r.strip() for r in os.environ["PROBE_REGIONS"].split(",") if r.strip()]
extra   = [m.strip() for m in os.environ["PROBE_EXTRA"].split(",") if m.strip()]
creds_file = os.environ.get("PROBE_CREDS", "")
fmt, prefer, out = os.environ["PROBE_FORMAT"], os.environ["PROBE_PREFER"], os.environ["PROBE_OUTPUT"]

def log(*a):
    print(*a, file=sys.stderr)

# ---- auth ------------------------------------------------------------
try:
    import google.auth, google.auth.transport.requests
    if creds_file:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = os.path.expanduser(creds_file)
    creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(google.auth.transport.requests.Request())
except Exception as e:
    log(f"AUTH FAILED: {e}")
    sys.exit(3)
ident = getattr(creds, "service_account_email", None) or getattr(creds, "_account", None) or "user-credential"
ctype = type(creds).__module__.split(".")[-1]
token = creds.token

def host(region):
    return "aiplatform.googleapis.com" if region == "global" else f"{region}-aiplatform.googleapis.com"

# ---- candidates --------------------------------------------------------
fallback = ["claude-opus-5-5","claude-opus-5","claude-opus-4-8","claude-opus-4-7","claude-opus-4-6",
            "claude-opus-4-5","claude-sonnet-5-5","claude-sonnet-5","claude-sonnet-4-6","claude-sonnet-4-5",
            "claude-haiku-5-5","claude-haiku-5","claude-haiku-4-5","claude-fable-5","claude-fable-5-1","claude-fable-5-2"]
catalog = []
try:
    req = urllib.request.Request(
        "https://us-central1-aiplatform.googleapis.com/v1beta1/publishers/anthropic/models?pageSize=200",
        headers={"Authorization": "Bearer " + token})
    data = json.load(urllib.request.urlopen(req, timeout=30))
    for m in data.get("publisherModels", []):
        catalog.append(m["name"].rsplit("/", 1)[-1])
except Exception as e:
    log(f"note: publisher catalog unavailable ({str(e)[:80]}); using built-in list")

seen, candidates = set(), []
for m in catalog + fallback + extra:
    m = m.split("@")[0]
    if m not in seen:
        seen.add(m); candidates.append(m)

# ---- probe ---------------------------------------------------------------
body = json.dumps({"anthropic_version": "vertex-2023-10-16",
                   "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1}).encode()

def probe(args):
    m, r = args
    url = f"https://{host(r)}/v1/projects/{project}/locations/{r}/publishers/anthropic/models/{m}:rawPredict"
    req = urllib.request.Request(url, data=body, headers={
        "Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        return m, r, urllib.request.urlopen(req, timeout=60).status
    except urllib.error.HTTPError as e:
        return m, r, e.code
    except Exception:
        return m, r, "ERR"

pairs = [(m, r) for m in candidates for r in regions]
with ThreadPoolExecutor(max_workers=6) as ex:
    results = list(ex.map(probe, pairs))

table = {m: {} for m in candidates}
for m, r, c in results:
    table[m][r] = c

def recommended(rmap):
    ok = [r for r in regions if rmap.get(r) == 200]
    if not ok:
        return None
    if prefer == "global" and "global" in ok:
        return "global"
    reg = [r for r in ok if r != "global"]
    if prefer == "regional" and reg:
        return reg[0]
    return ok[0]

def status(rmap):
    vals = list(rmap.values())
    if 200 in vals: return "available"
    if 429 in vals: return "quota-limited"
    if 403 in vals: return "blocked"
    if all(v == 404 for v in vals): return "not-offered"
    return "error"

order = {"available": 0, "quota-limited": 1, "blocked": 2, "not-offered": 3, "error": 4}
rows = [{"model": m, "status": status(table[m]), "region": recommended(table[m]), "regions": table[m]}
        for m in candidates]
rows.sort(key=lambda x: (order[x["status"]], x["model"]))

doc = {"project": project, "regions": regions,
       "credential": {"type": ctype, "identity": ident},
       "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "models": rows}
usable = [r for r in rows if r["region"]]

cache = os.environ.get("PROBE_CACHE", "")
if cache:
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    tmp = cache + ".tmp"
    with open(tmp, "w") as f:
        json.dump(doc, f, indent=2)
    os.replace(tmp, cache)
    log(f"cache updated: {cache}")

if fmt == "json":
    text = json.dumps(doc, indent=2)
elif fmt == "names":
    text = "\n".join(f'{r["model"]} {r["region"]}' for r in usable)
else:
    w = max(len(m) for m in candidates) + 2
    lines = [f"Project:    {project}", f"Credential: {ident} ({ctype})", f"Generated:  {doc['generated_at']}", "",
             f'{"MODEL":<{w}}' + "".join(f"{r:<12}" for r in regions) + "STATUS / RECOMMENDED"]
    for r in rows:
        cells = "".join(f'{str(r["regions"].get(g, "-")):<12}' for g in regions)
        rec = f'-> {r["region"]}' if r["region"] else ""
        lines.append(f'{r["model"]:<{w}}{cells}{r["status"]} {rec}')
    lines += ["", "200=usable 429=quota-limited 404=not offered 403=blocked ERR=network",
              f"Usable: {len(usable)} of {len(candidates)} candidates"]
    text = "\n".join(lines)

if out:
    with open(out, "w") as f:
        f.write(text + "\n")
    log(f"wrote {out}")
else:
    print(text)
sys.exit(0 if usable else 1)
PYEOF
rc=$?
trace_step 2 "result" "$rc" "exit=$rc" 2>/dev/null || true
trace_end 2>/dev/null || true
exit $rc
