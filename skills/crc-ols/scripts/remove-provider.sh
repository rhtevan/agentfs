#!/usr/bin/env bash
# remove-provider.sh — Remove a provider from OLSConfig
# Usage: bash remove-provider.sh PROVIDER [--delete-secret] [--context CONTEXT]
# Cannot remove the current default provider — switch first.
# Exit: 0 = success, 1 = failure, 2 = usage error
set -euo pipefail

PROVIDER=""
DELETE_SECRET=false
OC_CONTEXT_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-secret) DELETE_SECRET=true; shift ;;
    --context) OC_CONTEXT_ARG="--context $2"; shift 2 ;;
    *)         PROVIDER="$1"; shift ;;
  esac
done

if [[ -z "$PROVIDER" ]]; then
  echo "Usage: remove-provider.sh PROVIDER [--delete-secret] [--context CONTEXT]" >&2
  echo "" >&2
  echo "Available providers:" >&2
  # shellcheck disable=SC2086
  oc ${OC_CONTEXT_ARG} get olsconfig cluster \
    -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\n"}{end}' 2>/dev/null >&2 || true
  exit 2
fi

OC_CONTEXT="${OC_CONTEXT_ARG:-$([ -n "${CRC_OC_CONTEXT:-}" ] && echo "--context $CRC_OC_CONTEXT" || echo "")}"

# Check if provider exists and find its index
# shellcheck disable=SC2086
PROVIDER_NAMES=$(oc ${OC_CONTEXT} get olsconfig cluster \
  -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\n"}{end}')

INDEX=-1
i=0
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ "$name" == "$PROVIDER" ]]; then
    INDEX=$i
    break
  fi
  ((i++)) || true
done <<< "$PROVIDER_NAMES"

if [[ $INDEX -lt 0 ]]; then
  echo "❌ Provider '$PROVIDER' not found in OLSConfig." >&2
  echo "   Available: $(echo "$PROVIDER_NAMES" | tr '\n' ' ')" >&2
  exit 1
fi

# Check if it's the default
# shellcheck disable=SC2086
DEFAULT=$(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.spec.ols.defaultProvider}')
if [[ "$DEFAULT" == "$PROVIDER" ]]; then
  echo "❌ Cannot remove '$PROVIDER' — it is the current default provider." >&2
  echo "   Switch to another provider first: bash switch-provider.sh OTHER_PROVIDER MODEL" >&2
  exit 1
fi

# Get the secret name before removing
# shellcheck disable=SC2086
SECRET_NAME=$(oc ${OC_CONTEXT} get olsconfig cluster \
  -o jsonpath="{.spec.llm.providers[$INDEX].credentialsSecretRef.name}" 2>/dev/null || echo "")

echo "Removing provider '$PROVIDER' (index $INDEX)..."

# Remove via JSON patch
# shellcheck disable=SC2086
oc ${OC_CONTEXT} patch olsconfig cluster --type=json \
  -p "[{\"op\": \"remove\", \"path\": \"/spec/llm/providers/$INDEX\"}]" \
  || { echo "❌ Patch failed"; exit 1; }

echo "✅ Provider '$PROVIDER' removed from OLSConfig"

# Optionally delete the secret
if [[ "$DELETE_SECRET" == "true" && -n "$SECRET_NAME" ]]; then
  # shellcheck disable=SC2086
  oc ${OC_CONTEXT} delete secret "$SECRET_NAME" -n openshift-lightspeed 2>/dev/null || true
  echo "🗑️  Secret '$SECRET_NAME' deleted"
fi

# Show remaining providers
echo ""
echo "=== Remaining Providers ==="
# shellcheck disable=SC2086
oc ${OC_CONTEXT} get olsconfig cluster \
  -o jsonpath='{range .spec.llm.providers[*]}{.name}{"\n"}{end}'
# shellcheck disable=SC2086
echo "Status: $(oc ${OC_CONTEXT} get olsconfig cluster -o jsonpath='{.status.overallStatus}' 2>/dev/null || echo 'checking...')"
