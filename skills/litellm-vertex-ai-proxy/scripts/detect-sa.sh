#!/usr/bin/env bash
# detect-sa.sh — Detect GCP configuration and service account key files
# Usage: bash detect-sa.sh
# Exit codes: 0 = SA key found, 1 = no SA key found
# Read-only — does not modify any files
set -euo pipefail

echo "=== GCP Configuration ==="
echo ""

# Current project
PROJECT=$(gcloud config get-value project 2>/dev/null || echo "")
if [[ -n "$PROJECT" ]]; then
  echo "Project: $PROJECT"
else
  echo "Project: ❌ not set (run 'gcloud config set project <id>')"
fi

# Active account
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1 || echo "")
if [[ -n "$ACCOUNT" ]]; then
  echo "Account: $ACCOUNT"
else
  echo "Account: ❌ not authenticated (run 'gcloud auth login')"
fi

# Vertex AI region
REGION="${CLOUD_ML_REGION:-${ANTHROPIC_VERTEX_REGION:-}}"
if [[ -n "$REGION" ]]; then
  echo "Region:  $REGION (from env)"
else
  echo "Region:  not set (default: us-east5)"
fi

echo ""
echo "=== Service Account Keys ==="
echo ""

# Find SA key files
FOUND=0
for keyfile in $(find ~/.config/gcloud/legacy_credentials -name "adc.json" 2>/dev/null); do
  FOUND=$((FOUND + 1))
  # Extract metadata safely — NEVER print private_key
  python3 -c "
import json, sys
with open('$keyfile') as f:
    d = json.load(f)
print(f'  File:     $keyfile')
print(f'  Type:     {d.get(\"type\", \"unknown\")}')
print(f'  Email:    {d.get(\"client_email\", \"unknown\")}')
print(f'  Key ID:   {d.get(\"private_key_id\", \"\")[:12]}...')
print(f'  Project:  {d.get(\"project_id\", \"unknown\")}')
" 2>/dev/null || echo "  ⚠️  Could not parse: $keyfile"
  echo ""
done

# Also check GOOGLE_APPLICATION_CREDENTIALS
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "GOOGLE_APPLICATION_CREDENTIALS=$GOOGLE_APPLICATION_CREDENTIALS"
  if [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
    python3 -c "
import json
with open('$GOOGLE_APPLICATION_CREDENTIALS') as f:
    d = json.load(f)
print(f'  Type:     {d.get(\"type\", \"unknown\")}')
print(f'  Email:    {d.get(\"client_email\", \"unknown\")}')
" 2>/dev/null || echo "  ⚠️  Could not parse"
  else
    echo "  ❌ File not found"
  fi
  echo ""
fi

if [[ "$FOUND" -eq 0 && -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "❌ No service account key files found."
  echo "   Place a SA key JSON in ~/.config/gcloud/legacy_credentials/<email>/adc.json"
  echo "   or set GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json"
  exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Found $FOUND service account key(s)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
