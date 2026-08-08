#!/usr/bin/env bash
# status.sh — Check status of a specific model or all models
# Usage: bash status.sh [ALIAS]
#   No alias: show all models
#   With alias: show specific model + logs

source "$(dirname "$0")/common.sh"

ALIAS="${1:-}"

if [[ -z "$ALIAS" ]]; then
  # Show all
  exec bash "$(dirname "$0")/list.sh"
fi

parse_model "$ALIAS"

echo "=== Model Status: $ALIAS ==="
echo "  Model:     $MODEL_ID"
echo "  Container: $CONTAINER"
echo "  Host:      $HOST"
echo "  Port:      $PORT"
echo "  Engine:    $ENGINE"
echo "  TP:        $TP"
echo "  Context:   $CONTEXT"
echo

if ! host_reachable "$HOST"; then
  echo "  ⚠️  Host $HOST is unreachable"
  echo "  Status:    unknown"
  exit 0
fi

status=$(check_container_status "$HOST" "$CONTAINER")
echo "  Status:    $status"
echo

if [[ "$status" == *"Up"* ]]; then
  echo "  API check:"
  code=$(run_on_host "$HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/v1/models 2>/dev/null" || echo "000")
  echo "    HTTP $code on ${HOST}:${PORT}"
  
  if [[ "$code" == "200" ]]; then
    echo "  Model ID:"
    run_on_host "$HOST" "curl -s http://localhost:${PORT}/v1/models" | \
      python3 -c "import json,sys; d=json.load(sys.stdin); print('    ' + d['data'][0]['id'])" 2>/dev/null || echo "    (parse error)"
  fi
  
  echo
  echo "  Recent logs:"
  run_on_host "$HOST" "podman logs --tail 5 $CONTAINER 2>/dev/null" | sed 's/^/    /'
fi
