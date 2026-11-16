#!/usr/bin/env bash
# list.sh — List all OLS providers, models, and active default
# Usage: bash list.sh [--context CONTEXT]
# Exit: 0 = success, 1 = OLSConfig not found or not ready
set -euo pipefail

# Trace instrumentation
# shellcheck source=~/.agents/scripts/trace-lib.sh
source "${HOME}/.agents/scripts/trace-lib.sh" 2>/dev/null || true
trace_init "crc-ols" "3.4.0" 2>/dev/null || true

OC_CONTEXT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) OC_CONTEXT="--context $2"; shift 2 ;;
    *)         shift ;;
  esac
done
OC_CONTEXT="${OC_CONTEXT:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"

# shellcheck disable=SC2086
if ! oc ${OC_CONTEXT} get olsconfig cluster &>/dev/null; then
  echo "❌ OLSConfig 'cluster' not found. Is OLS installed?"
  exit 1
fi

echo "=== Default ==="
# shellcheck disable=SC2086
echo "Provider: $(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')"
# shellcheck disable=SC2086
echo "Model:    $(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultModel}')"
echo ""

echo "=== All Providers ==="
# shellcheck disable=SC2086
oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{range .spec.llm.providers[*]}{"Provider: "}{.name}{"\n"}{"  Type:   "}{.type}{"\n"}{"  URL:    "}{.url}{"\n"}{"  Secret: "}{.credentialsSecretRef.name}{"\n"}{"  Models: "}{range .models[*]}{.name}{", "}{end}{"\n\n"}{end}'

echo "=== Status ==="
# shellcheck disable=SC2086
oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.status.overallStatus}'
echo ""

# === Credential health ===
# Two independent checks per provider:
#   Age  — crc-ols/rotated-at (+ rotation-days), else creationTimestamp.
#          A self-reported stamp: only accurate if every rotation went
#          through rotate-key.sh. Treat as an early warning, not truth.
#   Auth — probe the provider endpoint from inside the app-server pod,
#          using the mounted key. This exercises the exact credential,
#          network path and CA trust OLS itself uses. This is the truth.
# OLS reports overallStatus Ready even when a provider key is dead, so
# without this an expired credential is invisible.
echo ""
echo "=== Credential Health ==="
# shellcheck disable=SC2086
oc ${OC_CONTEXT} get olsconfig cluster -o json > /tmp/.ols-list-$$.json 2>/dev/null || true
PROV_JSON=$(python3 - "/tmp/.ols-list-$$.json" <<'PYEOF' 2>/dev/null || echo ""
import json,sys
d=json.load(open(sys.argv[1]))
for p in d['spec']['llm']['providers']:
    models=p.get('models') or [{}]
    print('\t'.join([p['name'],
                     p['credentialsSecretRef']['name'],
                     p.get('credentialKey','apitoken'),
                     p.get('url','-') or '-',
                     models[0].get('name','-')]))
PYEOF
)
rm -f "/tmp/.ols-list-$$.json"

while IFS=$'\t' read -r PNAME SECRET CKEY PURL PMODEL; do
  [[ -z "$PNAME" ]] && continue

  # --- age ---
  # shellcheck disable=SC2086
  META=$(oc ${OC_CONTEXT} get secret "$SECRET" -n openshift-lightspeed -o json 2>/dev/null \
    | python3 -c "
import json,sys
from datetime import datetime,timezone
try: m=json.load(sys.stdin)['metadata']
except Exception: print('MISSING -1 -1'); raise SystemExit
a=m.get('annotations') or {}
ref=a.get('crc-ols/rotated-at') or m['creationTimestamp']
src='rotated' if a.get('crc-ols/rotated-at') else 'created'
limit=int(a.get('crc-ols/rotation-days') or 0)
age=int((datetime.now(timezone.utc)-datetime.fromisoformat(ref.replace('Z','+00:00'))).total_seconds()//86400)
print(f'{src} {age} {limit}')
" 2>/dev/null || echo "MISSING -1 -1")
  read -r ASRC AGE LIMIT <<< "$META"

  if [[ "$ASRC" == "MISSING" ]]; then
    AGE_TXT="❌ secret $SECRET not found"
  elif [[ "$LIMIT" -gt 0 ]]; then
    LEFT=$(( LIMIT - AGE ))
    if   [[ $LEFT -lt 0 ]]; then AGE_TXT="❌ ${AGE}d old — OVERDUE by $(( -LEFT ))d"
    elif [[ $LEFT -le 7 ]]; then AGE_TXT="⚠️  ${AGE}d old — rotate within ${LEFT}d"
    else                         AGE_TXT="✅ ${AGE}d old — ${LEFT}d remaining"; fi
  else
    AGE_TXT="➖ ${AGE}d old (no rotation policy; from ${ASRC})"
  fi

  # --- auth (in-pod, external HTTP providers only) ---
  #
  # Probe chat/completions, NOT /models.
  #
  # /models is frequently UNAUTHENTICATED. Verified 2026-11-16 against
  # https://models.corp.redhat.com/oai/v1 :
  #     /models           with a garbage bearer token -> HTTP 200
  #     /chat/completions with a garbage bearer token -> HTTP 401
  # A 200 from /models therefore proves the endpoint is reachable, and
  # nothing whatsoever about the credential. Only an inference call
  # actually exercises authentication.
  AUTH_TXT="➖ not probed"
  if [[ "$PURL" == http* ]] && ! echo "$PURL" | grep -q "listener-"; then
    if [[ "$PMODEL" == "-" || -z "$PMODEL" ]]; then
      AUTH_TXT="➖ not probed (no model in CRD)"
    else
    # shellcheck disable=SC2086
    CODE=$(oc ${OC_CONTEXT} exec deployment/lightspeed-app-server -n openshift-lightspeed \
      -c lightspeed-service-api -- bash -c \
      "curl -s -o /dev/null -w '%{http_code}' --connect-timeout 8 --max-time 25 \
         -H \"Authorization: Bearer \$(cat /etc/apikeys/$SECRET/$CKEY 2>/dev/null)\" \
         -H 'Content-Type: application/json' \
         -d '{\"model\":\"$PMODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}' \
         ${PURL%/}/chat/completions" 2>/dev/null || echo "000")
    case "$CODE" in
      200)     AUTH_TXT="✅ HTTP 200 (inference accepted)" ;;
      401|403) AUTH_TXT="❌ HTTP $CODE — credential rejected" ;;
      404)     AUTH_TXT="⚠️  HTTP 404 — model '$PMODEL' not served here" ;;
      000)     AUTH_TXT="⚠️  unreachable (network or CA trust)" ;;
      *)       AUTH_TXT="⚠️  HTTP $CODE" ;;
    esac
    fi
  fi

  echo "  $PNAME ($SECRET)"
  echo "    Age:  $AGE_TXT"
  echo "    Auth: $AUTH_TXT"
done <<< "$PROV_JSON"

# === Skupper provider liveness check ===
# For providers whose URL contains "listener-" (Skupper routes),
# probe the /v1/models endpoint to verify the configured model is actually served.
echo ""
echo "=== Skupper Provider Liveness ==="

# shellcheck disable=SC2086
PROVIDER_COUNT=$(oc ${OC_CONTEXT} get olsconfig cluster \
  -o jsonpath='{.spec.llm.providers[*].name}' | wc -w)

FOUND_SKUPPER=false
for i in $(seq 0 $((PROVIDER_COUNT - 1))); do
  # shellcheck disable=SC2086
  URL=$(oc ${OC_CONTEXT} get olsconfig cluster \
    -o jsonpath="{.spec.llm.providers[$i].url}" 2>/dev/null)
  [[ -z "$URL" ]] && continue
  # Only check Skupper providers (in-cluster listener- services)
  echo "$URL" | grep -q "listener-" || continue

  FOUND_SKUPPER=true
  # shellcheck disable=SC2086
  PNAME=$(oc ${OC_CONTEXT} get olsconfig cluster \
    -o jsonpath="{.spec.llm.providers[$i].name}")
  # shellcheck disable=SC2086
  CONFIGURED_MODELS=$(oc ${OC_CONTEXT} get olsconfig cluster \
    -o jsonpath="{range .spec.llm.providers[$i].models[*]}{.name}{'\n'}{end}")

  # Extract host:port from URL (e.g., http://listener-model-api-rhel-ai.model-provider-crc:9000/v1)
  ENDPOINT=$(echo "$URL" | sed 's|/v1$||; s|^http://||')

  # Probe the model endpoint from inside the router pod
  # shellcheck disable=SC2086
  LIVE_MODELS=$(oc ${OC_CONTEXT} exec deployment/skupper-router \
    -n model-provider-crc -- \
    curl -s --connect-timeout 3 "http://${ENDPOINT}/v1/models" 2>/dev/null \
    | grep -o '"id":"[^"]*"' | sed 's/"id":"//;s/"$//' || echo "")

  if [[ -z "$LIVE_MODELS" ]]; then
    echo "  $PNAME: ⚠️  UNREACHABLE ($ENDPOINT)"
  else
    # Check each configured model against live models
    while IFS= read -r model; do
      [[ -z "$model" ]] && continue
      if echo "$LIVE_MODELS" | grep -qxF "$model"; then
        echo "  $PNAME/$model: ✅ Live"
      else
        echo "  $PNAME/$model: ❌ MISMATCH — configured but not served"
        echo "    Live models: $LIVE_MODELS"
      fi
    done <<< "$CONFIGURED_MODELS"
  fi
done

if [[ "$FOUND_SKUPPER" == "false" ]]; then
  echo "  (no Skupper providers configured)"
fi
