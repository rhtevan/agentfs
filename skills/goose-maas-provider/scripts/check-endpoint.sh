#!/usr/bin/env bash
# check-endpoint.sh — Verify MaaS endpoint connectivity and authentication
#
# Usage: check-endpoint.sh [--url URL] [--key KEY]
#
# If --url and --key are not provided, reads from config files.
# Exit codes:
#   0 — Endpoint reachable and authenticated
#   1 — Endpoint unreachable or authentication failed

set -euo pipefail

MAAS_URL="${MAAS_URL:-https://maas-rhdp.apps.maas.redhatworkshops.io}"
MAAS_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MAAS_URL="$2"; shift 2 ;;
    --key) MAAS_KEY="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

echo "MaaS Endpoint Check"
echo "════════════════════"
echo "URL: $MAAS_URL"
echo ""

# Step 1: Connectivity
echo "1. Connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$MAAS_URL" 2>/dev/null || echo "000")
if [[ "$HTTP_CODE" == "000" ]]; then
  echo "   ❌ UNREACHABLE — endpoint did not respond within 5s"
  exit 1
elif [[ "$HTTP_CODE" =~ ^(200|301|302|307|308|401|403)$ ]]; then
  echo "   ✅ Reachable (HTTP $HTTP_CODE)"
else
  echo "   ⚠️  Unexpected HTTP $HTTP_CODE"
fi

# Step 2: Authentication (if key provided)
if [[ -n "$MAAS_KEY" ]]; then
  echo ""
  echo "2. Authentication..."
  MODELS_RESPONSE=$(curl -s --connect-timeout 5 \
    "$MAAS_URL/v1/models" \
    -H "Authorization: Bearer $MAAS_KEY" 2>/dev/null)
  
  if echo "$MODELS_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'   ✅ Authenticated — {len(d.get(\"data\",[]))} models available')" 2>/dev/null; then
    echo ""
    echo "   Available models:"
    echo "$MODELS_RESPONSE" | python3 -c "
import json,sys
d = json.load(sys.stdin)
for m in d.get('data',[]):
    print(f'     - {m[\"id\"]}')
" 2>/dev/null
  else
    echo "   ❌ Authentication failed — check API key"
    echo "   Response: $(echo "$MODELS_RESPONSE" | head -1)"
    exit 1
  fi
else
  echo ""
  echo "2. Authentication... SKIPPED (no --key provided)"
  echo "   Provide --key <sk-...> to test authentication"
fi

echo ""
echo "════════════════════"
echo "✅ Endpoint check complete"
