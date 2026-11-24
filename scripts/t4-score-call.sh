#!/usr/bin/env bash
# t4-score-call.sh — T4 drop-in for sdm-call.sh (F30, decided 2026-11-24).
#
# Answers SystemOne-format questions with a T4 model of a DIFFERENT family
# from the one that writes the AgentFS prose (Claude), to avoid self-grading
# bias. Same interface and response shape as sdm-call.sh, so sdm-evaluate.sh
# scores, bands and deterministic overrides apply unchanged:
#   SDM_CALL=~/.agents/scripts/t4-score-call.sh sdm-evaluate.sh ...
#
# Usage:
#   t4-score-call.sh --input "evidence text" --questions '<json-object>'
#
# Environment:
#   T4_SCORER_MODEL  Vertex publisher model (default gemini-3.1-pro-preview)
#   T4_SCORER_CRED   service-account JSON (default: the vertex-ai-sa ADC file)
#   T4_SCORER_PROJECT GCP project (default itpc-gcp-global-revenue-claude)
#
# Response: {answers: {name: {type, noul|score|choice, probabilities?,
#            confidence: null}}, diagnostics: {}, scorer: "t4:<model>"}
#   confidence is null: no logits, no calibrated confidence. t4-static-score.sh
#   derives agreement across runs instead.
#
# Exit codes: 0 success · 1 model error / unparseable answer · 2 endpoint
#             unreachable or auth failure · 3 usage error
set -euo pipefail
INPUT="" QUESTIONS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT="$2"; shift 2 ;;
    --questions) QUESTIONS="$2"; shift 2 ;;
    -h|--help) sed -n 2,24p "$0"; exit 0 ;;
    *) echo "t4-score-call: unsupported argument $1 (only --input/--questions)" >&2; exit 3 ;;
  esac
done
[[ -n "$INPUT" && -n "$QUESTIONS" ]] || { echo "t4-score-call: --input and --questions required" >&2; exit 3; }

INPUT="$INPUT" QUESTIONS="$QUESTIONS" python3 - <<'PY'
import os, sys, json, glob, re, urllib.request, urllib.error
model = os.environ.get("T4_SCORER_MODEL", "gemini-3.1-pro-preview")
project = os.environ.get("T4_SCORER_PROJECT", "itpc-gcp-global-revenue-claude")
cred = os.environ.get("T4_SCORER_CRED") or next(iter(glob.glob(os.path.expanduser(
    "~/.config/gcloud/legacy_credentials/vertex-ai-sa@*/adc.json"))), "")
qs = json.loads(os.environ["QUESTIONS"])
try:
    import google.auth.transport.requests
    from google.oauth2 import service_account
    c = service_account.Credentials.from_service_account_file(
        cred, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    c.refresh(google.auth.transport.requests.Request())
except Exception as e:
    print(f"t4-score-call: auth failed: {e}", file=sys.stderr); sys.exit(2)

lines = []
for name, q in qs.items():
    t = q["type"]
    if t == "noul":
        opts = 'answer "yes" or "no"'
    elif t == "score":
        crit = q["criteria"]
        opts = "answer the 0-based index of the best-matching level: " + \
               "; ".join(f"{i} = {c}" for i, c in enumerate(crit))
    elif t == "choice":
        opts = "answer exactly one of: " + ", ".join(q["criteria"].keys())
    else:
        print(f"t4-score-call: unknown question type {t}", file=sys.stderr); sys.exit(1)
    lines.append(f"- {name}: {q['instructions']}\n  ({opts})")
prompt = (
    "You are a strict, literal evaluator (a classifier, not an assistant).\n"
    "Answer every question ONLY from the EVIDENCE below. Do not reward or "
    "penalise anything the evidence does not state.\n\n"
    "QUESTIONS:\n" + "\n".join(lines) +
    "\n\nReturn ONLY a JSON object mapping each question name to its answer "
    '(a string for yes/no and choice, an integer index for levels), e.g. '
    '{"q1": "yes", "q2": 3}.\n\nEVIDENCE:\n' + os.environ["INPUT"])

url = (f"https://aiplatform.googleapis.com/v1/projects/{project}/locations/global/"
       f"publishers/google/models/{model}:generateContent")
body = {"contents": [{"role": "user", "parts": [{"text": prompt}]}],
        "generationConfig": {"responseMimeType": "application/json"}}
req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
    "Authorization": "Bearer " + c.token, "Content-Type": "application/json"})
# sdm-evaluate.sh discards this script's stderr, so failures are also logged
# to T4_SCORER_LOG. Transient failures (5xx/429, empty or unparseable answer,
# missing question) are retried up to 3 attempts.
LOG = os.environ.get("T4_SCORER_LOG", "/tmp/t4-score-call.log")
def fail(msg, code):
    with open(LOG, "a") as f: f.write(msg + "\n")
    print(f"t4-score-call: {msg}", file=sys.stderr); sys.exit(code)
raw, last = None, ""
for attempt in range(3):
    try:
        r = json.load(urllib.request.urlopen(req, timeout=300))
    except urllib.error.HTTPError as e:
        if e.code in (401, 403, 404): fail(f"HTTP {e.code}: {e.read()[:200]!r}", 2)
        last = f"HTTP {e.code}"; continue
    except Exception as e:
        last = f"unreachable: {e}"; continue
    try:
        text = "".join(p.get("text", "") for p in r["candidates"][0]["content"]["parts"])
        cand = json.loads(re.sub(r"^```(?:json)?|```$", "", text.strip()).strip())
        missing = [n for n in qs if n not in cand]
        if missing: last = f"no answer for {missing}"; continue
        raw = cand; break
    except Exception as e:
        last = f"unparseable answer: {e}: {json.dumps(r)[:300]}"; continue
if raw is None:
    fail(f"giving up after 3 attempts: {last}", 2 if last.startswith("unreachable") else 1)
with open(LOG, "a") as f:
    if attempt: f.write(f"ok after {attempt + 1} attempts (last error: {last})\n")

answers = {}
for name, q in qs.items():
    a = raw.get(name)
    t = q["type"]
    if t == "noul":
        yes = 1.0 if str(a).strip().lower() in ("yes", "true", "1") else 0.0
        answers[name] = {"type": "noul", "noul": yes,
                         "probabilities": {"yes": yes, "no": 1 - yes}, "confidence": None}
    elif t == "score":
        idx = int(a); idx = max(0, min(idx, len(q["criteria"]) - 1))
        answers[name] = {"type": "score", "score": idx, "confidence": None}
    else:
        answers[name] = {"type": "choice", "choice": str(a), "confidence": None}
print(json.dumps({"answers": answers, "diagnostics": {}, "scorer": f"t4:{model}"}))
PY
