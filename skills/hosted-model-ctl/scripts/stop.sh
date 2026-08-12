#!/usr/bin/env bash
# stop.sh — Stop a running model container
# Usage: bash stop.sh ALIAS [--remove]
#   Or: bash stop.sh all [--remove]
# --remove: also delete the container after stopping

source "$(dirname "$0")/common.sh"

ALIAS="${1:?Usage: stop.sh ALIAS|all [--remove]}"
REMOVE=false
[[ "${2:-}" == "--remove" ]] && REMOVE=true

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
    if [[ "$REMOVE" == "true" ]]; then
      run_on_host "$HOST" "podman rm -f $CONTAINER 2>/dev/null" || true
      echo "  🗑️  $CONTAINER removed"
    fi
  done
  if [[ "$REMOVE" == "true" ]]; then
    echo "✅ All reachable models stopped and removed"
  else
    echo "✅ All reachable models stopped"
  fi
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

if [[ "$REMOVE" == "true" ]]; then
  run_on_host "$HOST" "podman rm -f $CONTAINER 2>/dev/null" || true
  echo "🗑️  $CONTAINER removed"
fi
