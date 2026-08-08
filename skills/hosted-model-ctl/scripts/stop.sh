#!/usr/bin/env bash
# stop.sh — Stop a running model container
# Usage: bash stop.sh ALIAS
#   Or: bash stop.sh all     — stop all models on all hosts

source "$(dirname "$0")/common.sh"

ALIAS="${1:?Usage: stop.sh ALIAS|all}"

if [[ "$ALIAS" == "all" ]]; then
  echo "Stopping all model containers..."
  for alias in g350m g1b g8b g8b-128k g30b-96k; do
    parse_model "$alias"
    if ! host_reachable "$HOST"; then
      echo "  ⚠️  $HOST unreachable — skipping $CONTAINER"
      continue
    fi
    status=$(check_container_status "$HOST" "$CONTAINER")
    if [[ "$status" == *"Up"* ]]; then
      echo "  Stopping $CONTAINER on $HOST..."
      run_on_host "$HOST" "podman stop $CONTAINER" 2>/dev/null
      echo "  ✅ $CONTAINER stopped"
    fi
  done
  echo "✅ All reachable models stopped"
  exit 0
fi

parse_model "$ALIAS"

if ! host_reachable "$HOST"; then
  echo "❌ Host $HOST is unreachable." >&2
  exit 1
fi

status=$(check_container_status "$HOST" "$CONTAINER")
if [[ "$status" == *"Up"* ]]; then
  echo "Stopping $CONTAINER on $HOST..."
  run_on_host "$HOST" "podman stop $CONTAINER"
  echo "✅ $CONTAINER stopped"
else
  echo "$CONTAINER is not running ($status)"
fi
