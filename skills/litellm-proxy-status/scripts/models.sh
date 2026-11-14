#!/usr/bin/env bash
# models.sh — Read-only model queries against the local LiteLLM proxy.
# Usage: bash models.sh list    [--json] [--url URL]
#        bash models.sh default [--family opus|sonnet|haiku] [--url URL]
# Exit codes: 0 = ok, 1 = proxy unreachable / no model, 2 = usage error
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "litellm-proxy-status" "1.2.0" 2>/dev/null || true

URL="${LITELLM_URL:-http://127.0.0.1:4000}"
RANK="${HOME}/.agents/skills/gcp-vertex-models/scripts/models.sh"
MODE="${1:-}"; [[ $# -gt 0 ]] && shift
JSON=false; FAMILY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)   JSON=true; shift ;;
    --family) FAMILY="${2:?}"; shift 2 ;;
    --url)    URL="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
case "$MODE" in list|default) ;; *) echo "Usage: models.sh list|default [options]" >&2; exit 2 ;; esac

# /model/info carries vertex_location and context limits; /v1/models is the served set.
INFO=$(curl -sf -m 10 "$URL/model/info" 2>/dev/null) || {
  echo "❌ LiteLLM proxy unreachable at $URL — check: litellm status"
  trace_step 1 "$MODE" 1 "unreachable" 2>/dev/null || true; trace_end 2>/dev/null || true
  exit 1
}
trace_step 1 "fetch" 0 "$URL" 2>/dev/null || true

if [[ "$MODE" == list ]]; then
  if $JSON; then
    python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
print(json.dumps([{"model":m["model_name"],"backend":m["litellm_params"].get("model"),
  "vertex_location":m["litellm_params"].get("vertex_location"),
  "max_input_tokens":(m.get("model_info") or {}).get("max_input_tokens"),
  "max_output_tokens":(m.get("model_info") or {}).get("max_output_tokens")} for m in d],indent=2))' <<<"$INFO"
  else
    python3 -c '
import sys,json
d=sorted(json.load(sys.stdin)["data"], key=lambda m:m["model_name"])
fmt="%-22s%-12s%10s%10s"
print(fmt % ("MODEL","REGION","CONTEXT","MAX OUT"))
for m in d:
    p=m["litellm_params"]; i=m.get("model_info") or {}
    print(fmt % (m["model_name"], p.get("vertex_location","-"), i.get("max_input_tokens","-"), i.get("max_output_tokens","-")))
print("\nServed: %d model(s)" % len(d))' <<<"$INFO"
  fi
  rc=$?
else
  if [[ ! -f "$RANK" ]]; then
    echo "❌ Dependency missing: gcp-vertex-models skill ($RANK)"; exit 1
  fi
  NAMES=$(python3 -c 'import sys,json;[print(m["model_name"]) for m in json.load(sys.stdin)["data"]]' <<<"$INFO")
  set +e
  ORDER=$(printf '%s\n' "$NAMES" | bash "$RANK" rank ${FAMILY:+--family "$FAMILY"} 2>/dev/null)
  rc=$?
  set -e
  if [[ $rc -ne 0 || -z "$ORDER" ]]; then
    echo "❌ No rankable Claude model served${FAMILY:+ in family $FAMILY}"; rc=1
  else
    echo "$(head -1 <<<"$ORDER")"
    echo "Ranking (family opus>sonnet>haiku, then newest version): $(paste -sd, <<<"$ORDER" | sed 's/,/, /g')" >&2
  fi
fi
trace_step 2 "$MODE" "$rc" "family=$FAMILY" 2>/dev/null || true
trace_end 2>/dev/null || true
exit $rc
