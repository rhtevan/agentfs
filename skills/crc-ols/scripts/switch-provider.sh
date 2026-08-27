#!/usr/bin/env bash
# switch-provider.sh — Switch the active OLS provider and model
# Usage: bash switch-provider.sh PROVIDER MODEL [--context CONTEXT]
# The target provider and model must already be configured in OLSConfig.
# Exit: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

PROVIDER=""
MODEL=""
OC_CONTEXT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) OC_CONTEXT_ARG="--context $2"; shift 2 ;;
    *)
      if [[ -z "$PROVIDER" ]]; then
        PROVIDER="$1"
      elif [[ -z "$MODEL" ]]; then
        MODEL="$1"
      fi
      shift ;;
  esac
done

if [[ -z "$PROVIDER" || -z "$MODEL" ]]; then
  echo "Usage: switch-provider.sh PROVIDER MODEL [--context CONTEXT]" >&2
  echo "" >&2
  echo "Available providers and models:" >&2
  # shellcheck disable=SC2086
  oc ${OC_CONTEXT_ARG} get olsconfig cluster \
    -o jsonpath='{range .spec.llm.providers[*]}{"  "}{.name}{": "}{range .models[*]}{.name}{", "}{end}{"\n"}{end}' 2>/dev/null >&2 || true
  exit 2
fi

OC_CONTEXT="${OC_CONTEXT_ARG:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"

# Verify provider exists
# shellcheck disable=SC2086
PROVIDERS=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.llm.providers[*].name}')
if ! echo "$PROVIDERS" | tr ' ' '\n' | grep -qx "$PROVIDER"; then
  echo "❌ Provider '$PROVIDER' not found in OLSConfig." >&2
  echo "   Available: $PROVIDERS" >&2
  exit 1
fi

# Verify model exists under the target provider
# shellcheck disable=SC2086
PROVIDER_MODELS=$(oc ${OC_CONTEXT} get olsconfig cluster \
  -o jsonpath="{range .spec.llm.providers[?(@.name=='$PROVIDER')].models[*]}{.name}{'\n'}{end}")
if ! echo "$PROVIDER_MODELS" | grep -qx "$MODEL"; then
  echo "❌ Model '$MODEL' not found under provider '$PROVIDER'." >&2
  echo "   Available models for $PROVIDER:" >&2
  echo "$PROVIDER_MODELS" | sed 's/^/     /' >&2
  exit 1
fi

# Get current defaults
# shellcheck disable=SC2086
CURRENT_PROVIDER=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')
# shellcheck disable=SC2086
CURRENT_MODEL=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultModel}')

if [[ "$CURRENT_PROVIDER" == "$PROVIDER" && "$CURRENT_MODEL" == "$MODEL" ]]; then
  echo "⏭️  Already active: provider=$PROVIDER model=$MODEL"
  exit 0
fi

echo "Switching OLS default:"
echo "  From: provider=$CURRENT_PROVIDER model=$CURRENT_MODEL"
echo "  To:   provider=$PROVIDER model=$MODEL"

# Patch
# shellcheck disable=SC2086
oc ${OC_CONTEXT} patch olsconfig cluster --type=merge -p "{
  \"spec\": {
    \"ols\": {
      \"defaultProvider\": \"$PROVIDER\",
      \"defaultModel\": \"$MODEL\"
    }
  }
}" || { echo "❌ Patch failed"; exit 1; }

# Wait for Ready
echo "Waiting for OLS to reconcile..."
ATTEMPTS=0
while [[ $ATTEMPTS -lt 20 ]]; do
  sleep 5
  # shellcheck disable=SC2086
  STATUS=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.status.overallStatus}' 2>/dev/null || echo "Unknown")
  if [[ "$STATUS" == "Ready" ]]; then
    break
  fi
  ((ATTEMPTS++)) || true
done

# Verify
# shellcheck disable=SC2086
NEW_PROVIDER=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')
# shellcheck disable=SC2086
NEW_MODEL=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultModel}')
# shellcheck disable=SC2086
FINAL_STATUS=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.status.overallStatus}' 2>/dev/null || echo "Unknown")

echo ""
echo "=== Result ==="
echo "Provider: $NEW_PROVIDER"
echo "Model:    $NEW_MODEL"
echo "Status:   $FINAL_STATUS"

if [[ "$NEW_PROVIDER" == "$PROVIDER" && "$FINAL_STATUS" == "Ready" ]]; then
  echo "✅ Switch complete"
  exit 0
else
  echo "⚠️  Switch applied but status is $FINAL_STATUS (may need more time)"
  exit 0
fi
