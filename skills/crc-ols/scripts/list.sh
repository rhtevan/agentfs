#!/usr/bin/env bash
# list.sh — List all OLS providers, models, and active default
# Usage: bash list.sh [--context CONTEXT]
# Exit: 0 = success, 1 = OLSConfig not found or not ready
set -euo pipefail

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

# === Skupper provider liveness check ===
# For providers whose URL contains "model-listener" (Skupper routes),
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
  # Only check Skupper providers (in-cluster model-listener services)
  echo "$URL" | grep -q "model-listener" || continue

  FOUND_SKUPPER=true
  # shellcheck disable=SC2086
  PNAME=$(oc ${OC_CONTEXT} get olsconfig cluster \
    -o jsonpath="{.spec.llm.providers[$i].name}")
  # shellcheck disable=SC2086
  CONFIGURED_MODELS=$(oc ${OC_CONTEXT} get olsconfig cluster \
    -o jsonpath="{range .spec.llm.providers[$i].models[*]}{.name}{'\n'}{end}")

  # Extract host:port from URL (e.g., http://model-listener-rhel-ai.model-provider-crc:9000/v1)
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
