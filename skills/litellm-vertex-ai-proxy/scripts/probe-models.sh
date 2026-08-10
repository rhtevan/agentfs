#!/usr/bin/env bash
# probe-models.sh — Probe Vertex AI for available Anthropic Claude models
# Usage: bash probe-models.sh [--project PROJECT] [--region REGION]
# Exit codes: 0 = at least one model found, 1 = no models found, 2 = usage error
#
# Note: There is no Vertex AI API to list available publisher models.
# This script probes known model names with a minimal rawPredict request.
set -euo pipefail

PROJECT="${ANTHROPIC_VERTEX_PROJECT_ID:-}"
REGION="us-east5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2 ;;
    --region)  REGION="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: bash probe-models.sh [--project PROJECT] [--region REGION]"
      echo "  --project PROJECT  GCP project ID (default: \$ANTHROPIC_VERTEX_PROJECT_ID)"
      echo "  --region  REGION   Vertex AI region (default: us-east5)"
      echo ""
      echo "Probes known Claude model names against the Vertex AI rawPredict endpoint."
      echo "There is no listing API — this is the only discovery method."
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

if [[ -z "$PROJECT" ]]; then
  # Try to detect from gcloud
  PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "$PROJECT" ]]; then
  echo "❌ No project specified. Use --project or set ANTHROPIC_VERTEX_PROJECT_ID"
  exit 2
fi

# Get access token
TOKEN=$(gcloud auth print-access-token 2>/dev/null || echo "")
if [[ -z "$TOKEN" ]]; then
  echo "❌ Could not get access token. Run 'gcloud auth login' first."
  exit 1
fi

echo "Project: $PROJECT"
echo "Region:  $REGION"
echo ""

# Known Claude model names to probe
MODELS=(
  claude-opus-4-6
  claude-sonnet-4-6
  claude-sonnet-4-5
  claude-haiku-4-5
  claude-opus-4-7
  claude-opus-4-8
  claude-opus-5
  claude-sonnet-5
  claude-fable-5
)

URL_BASE="https://${REGION}-aiplatform.googleapis.com/v1/projects/$PROJECT/locations/$REGION/publishers/anthropic/models"

FOUND=0
echo "Probing models on $REGION..."
echo ""

for model in "${MODELS[@]}"; do
  RESP=$(curl -sf -w "%{http_code}" -o /dev/null \
    -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "$URL_BASE/$model:rawPredict" \
    -d '{"anthropic_version":"vertex-2023-10-16","messages":[{"role":"user","content":"hi"}],"max_tokens":5}' 2>/dev/null || echo "000")
  if [[ "$RESP" == "200" ]]; then
    echo "  ✅ $model"
    FOUND=$((FOUND + 1))
  else
    echo "  ❌ $model ($RESP)"
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Found: $FOUND available model(s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[[ "$FOUND" -ge 1 ]] && exit 0 || exit 1
