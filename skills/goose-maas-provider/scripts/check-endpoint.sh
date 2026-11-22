#!/usr/bin/env bash
# check-endpoint.sh — Verify MaaS endpoint connectivity and authentication
#
# Usage: check-endpoint.sh [--url URL] [--key KEY]
#
#   --url  default: base_url of custom_maas.json, else the RHDP MaaS URL
#   --key  discouraged (visible in ps/history). Without it the key is read
#          from GNOME Keyring (CUSTOM_MAAS_API_KEY) and passed to curl via a
#          0600 header file. The key is never printed.
# Env: GOOSE_CONFIG_DIR (default ~/.config/goose)
#
# Exit codes:
#   0 — Endpoint reachable (and authenticated, if a key was available)
#   1 — Endpoint unreachable or authentication failed
#   3 — Keyring locked/unavailable (connectivity was still checked)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-keyring.sh"

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
MAAS_URL=""
MAAS_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) MAAS_URL="${2:?--url needs a value}"; shift 2 ;;
    --key) MAAS_KEY="${2:?--key needs a value}"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$MAAS_URL" ]]; then
  MAAS_URL=$(jq -r '.base_url // empty' "$GOOSE_CONFIG_DIR/custom_providers/custom_maas.json" 2>/dev/null || true)
  MAAS_URL="${MAAS_URL:-https://maas-rhdp.apps.maas.redhatworkshops.io}"
fi
MAAS_URL="${MAAS_URL%/}"

echo "MaaS Endpoint Check"
echo "════════════════════"
echo "URL: $MAAS_URL"
echo ""

# Step 1: Connectivity
echo "1. Connectivity..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$MAAS_URL/v1/models" 2>/dev/null || true)
HTTP_CODE="${HTTP_CODE:-000}"
if [[ "$HTTP_CODE" == "000" ]]; then
  echo "   ❌ UNREACHABLE — endpoint did not respond within 5s"
  exit 1
elif [[ "$HTTP_CODE" =~ ^(200|301|302|307|308|401|403)$ ]]; then
  echo "   ✅ Reachable (HTTP $HTTP_CODE without key)"
else
  echo "   ⚠️  Unexpected HTTP $HTTP_CODE"
fi

# Step 2: Authentication
echo ""
echo "2. Authentication..."
KEY_RC=0
if [[ -n "$MAAS_KEY" ]]; then
  echo "   (key from --key — prefer the keyring)"
else
  MAAS_KEY=$(keyring_get CUSTOM_MAAS_API_KEY) || KEY_RC=$?
fi
if [[ $KEY_RC -ne 0 ]]; then
  echo "   SKIPPED — $(keyring_explain "$KEY_RC" CUSTOM_MAAS_API_KEY)"
  [[ $KEY_RC -eq 1 ]] && echo "   Store it: bash $SCRIPT_DIR/store-key.sh --validate (your own terminal)"
  echo ""
  echo "════════════════════"
  [[ $KEY_RC -eq 3 ]] && exit 3
  echo "✅ Connectivity check complete (authentication not tested)"
  exit 0
fi

HDR=$(auth_header_file "$MAAS_KEY"); trap 'rm -f "$HDR"' EXIT
unset MAAS_KEY
RESP=$(curl -s --connect-timeout 5 --max-time 20 -H @"$HDR" -w $'\n%{http_code}' "$MAAS_URL/v1/models" 2>/dev/null || true)
CODE=$(tail -1 <<<"$RESP")
BODY=$(sed '$d' <<<"$RESP")
N=$(jq '.data | length' <<<"$BODY" 2>/dev/null || echo "")
if [[ "$CODE" == "200" && -n "$N" ]]; then
  echo "   ✅ Authenticated — $N models available"
  jq -r '.data[].id' <<<"$BODY" | sort | sed 's/^/     - /'
else
  echo "   ❌ Authentication failed (HTTP ${CODE:-000}) — check the key"
  echo "   Response: $(head -c 200 <<<"$BODY")"
  exit 1
fi

echo ""
echo "════════════════════"
echo "✅ Endpoint check complete"
