#!/usr/bin/env bash
# refresh-models.sh — Re-probe Vertex, regenerate the LiteLLM model_list, restart, and
# chat-test every served model. Preserves the live bind host/port and SA key.
# Usage: bash refresh-models.sh [--apply] [--project P] [--sa-key PATH] [--regions R1,R2]
#   (default = dry run; prints DRY_RUN_RESULT=CONVERGED|PENDING)
# Exit codes: 0 = success/converged, 1 = failure, 2 = usage error
set -euo pipefail

source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "litellm-vertex-ai-proxy" "3.4.0" 2>/dev/null || true

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVC="$HOME/.config/systemd/user/litellm-proxy.service"
APPLY=false; PROJECT=""; SA_KEY=""; REGIONS="global,us-east5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)   APPLY=true; shift ;;
    --project) PROJECT="${2:?}"; shift 2 ;;
    --sa-key)  SA_KEY="${2:?}"; shift 2 ;;
    --regions) REGIONS="${2:?}"; shift 2 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -f "$SVC" ]]; then
  echo "❌ No live service unit at $SVC — run the full setup (setup litellm vertex) first"
  exit 1
fi

# Live settings are the source of truth so a refresh never changes binding or credentials.
EXEC=$(grep '^ExecStart=' "$SVC")
HOST=$(sed -n 's/.*--host \([^ ]*\).*/\1/p' <<<"$EXEC"); HOST=${HOST:-127.0.0.1}
PORT=$(sed -n 's/.*--port \([^ ]*\).*/\1/p' <<<"$EXEC"); PORT=${PORT:-4000}
[[ -z "$SA_KEY" ]] && SA_KEY=$(sed -n 's/^Environment=GOOGLE_APPLICATION_CREDENTIALS=//p' "$SVC")
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(awk '/vertex_project:/{print $2; exit}' "$HOME/.config/litellm/config.yaml" 2>/dev/null || true)
fi
if [[ -z "$PROJECT" || -z "$SA_KEY" ]]; then
  echo "❌ Could not detect project or SA key from live config — pass --project and --sa-key"
  exit 2
fi
echo "Live settings: project=$PROJECT host=$HOST port=$PORT key=$SA_KEY"
trace_step 1 "detect" 0 "host=$HOST port=$PORT" 2>/dev/null || true

# Step: dry run (also refreshes the gcp-vertex-models cache)
DRY=$(bash "$DIR/setup.sh" --project "$PROJECT" --sa-key "$SA_KEY" --host "$HOST" --port "$PORT" \
        --regions "$REGIONS" --dry-run 2>&1) || { echo "$DRY"; echo "❌ Dry run failed"; exit 1; }
echo "$DRY" | grep -E '✅ claude|^Model/region changes|^  [-+]|service unit differs|DRY_RUN_RESULT' || true
RESULT=$(grep -o 'DRY_RUN_RESULT=[A-Z]*' <<<"$DRY" | tail -1)
trace_step 2 "dry-run" 0 "$RESULT" 2>/dev/null || true

if [[ "$RESULT" == "DRY_RUN_RESULT=CONVERGED" ]]; then
  echo "✅ Proxy model list already matches Vertex — nothing to do"
  trace_end 2>/dev/null || true; exit 0
fi
if ! $APPLY; then
  echo "ℹ️  Re-run with --apply to write config, restart the proxy, and test each model"
  trace_end 2>/dev/null || true; exit 0
fi

# Step: apply
bash "$DIR/setup.sh" --project "$PROJECT" --sa-key "$SA_KEY" --host "$HOST" --port "$PORT" \
  --regions "$REGIONS" --force | tail -8 || { echo "❌ setup.sh --force failed"; exit 1; }
trace_step 3 "apply" 0 "" 2>/dev/null || true

# Step: wait for readiness, then chat-test every served model
for _ in $(seq 1 40); do curl -sf "http://127.0.0.1:$PORT/health/liveliness" >/dev/null && break; sleep 2; done
MODELS=$(curl -sf "http://127.0.0.1:$PORT/v1/models" | python3 -c 'import sys,json;print(" ".join(m["id"] for m in json.load(sys.stdin)["data"]))') \
  || { echo "❌ Proxy not answering /v1/models after restart"; exit 1; }
FAILED=0
for m in $MODELS; do
  R=$(curl -s -m 90 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'content-type: application/json' \
      -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":10}" \
      | python3 -c 'import sys,json;d=json.load(sys.stdin);print("ok" if "choices" in d else "fail")' 2>/dev/null || echo fail)
  if [[ "$R" == ok ]]; then echo "  ✅ $m"; else echo "  ❌ $m"; FAILED=$((FAILED + 1)); fi
done
trace_step 4 "chat-test" "$FAILED" "failed=$FAILED" 2>/dev/null || true

echo ""
echo "Downstream (not changed by this script):"
echo "  goose custom_redhat: models auto-discovered; refresh fallback list with"
echo "    bash ~/.agents/skills/goose-litellm-provider/scripts/restore.sh"
echo "  hermes / dsh: static model lists — update via hermes-litellm-provider / dsh-litellm-provider"
trace_end 2>/dev/null || true
[[ $FAILED -eq 0 ]] && exit 0 || { echo "❌ $FAILED model(s) failed chat test"; exit 1; }
