#!/usr/bin/env bash
# probe-models.sh — Discover available models on Corp endpoint
# Usage: bash probe-models.sh [--check] [--chat-only] [--json]
set -euo pipefail

source ~/.agents/scripts/trace-lib.sh 2>/dev/null || true
trace_init "goose-corp-provider" "probe-models" 2>/dev/null || true

HOST="https://models.corp.redhat.com"
ENDPOINT="${HOST}/oai/v1/models"
CHECK_ONLY=false
CHAT_ONLY=false
JSON_OUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) CHECK_ONLY=true; shift ;;
    --chat-only) CHAT_ONLY=true; shift ;;
    --json) JSON_OUT=true; shift ;;
    *) echo "Usage: probe-models.sh [--check] [--chat-only] [--json]" >&2; exit 2 ;;
  esac
done

trace_step "connectivity" "Testing endpoint connectivity" 2>/dev/null || true

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "$ENDPOINT" 2>/dev/null || echo "000")

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "❌ Corp endpoint unreachable (HTTP $HTTP_CODE)"
  echo "   URL: $ENDPOINT"
  echo "   Check VPN connection."
  trace_end 1 2>/dev/null || true
  exit 1
fi

if [[ "$CHECK_ONLY" == "true" ]]; then
  echo "✅ Corp endpoint reachable"
  trace_end 0 2>/dev/null || true
  exit 0
fi

trace_step "discovery" "Fetching model list" 2>/dev/null || true

RESPONSE=$(curl -s --connect-timeout 10 "$ENDPOINT" 2>/dev/null)

if [[ "$JSON_OUT" == "true" ]]; then
  echo "$RESPONSE" | jq '.'
  trace_end 0 2>/dev/null || true
  exit 0
fi

# Build jq filter
JQ_FILTER='.data[]'
if [[ "$CHAT_ONLY" == "true" ]]; then
  JQ_FILTER="${JQ_FILTER}"' | select((.id | test("embed|rerank|guardian|parse|diffusion"; "i")) | not)'
fi

echo "Available models on models.corp.redhat.com:"
echo ""
printf "%-50s %-10s %s\n" "MODEL ID" "TYPE" "DESCRIPTION"
printf "%-50s %-10s %s\n" "--------" "----" "-----------"

echo "$RESPONSE" | jq -r "[${JQ_FILTER}] | sort_by(.id) | .[] | \"\(.id)\t\(.type)\t\(.description)\"" \
  | while IFS=$'\t' read -r id type desc; do
    short_desc="${desc:0:60}"
    printf "%-50s %-10s %s\n" "$id" "$type" "$short_desc"
  done

TOTAL=$(echo "$RESPONSE" | jq "[${JQ_FILTER}] | length")
echo ""
echo "Total: $TOTAL models"

trace_end 0 2>/dev/null || true
