#!/usr/bin/env bash
# start.sh — Start an existing model container
# Usage: bash start.sh ALIAS
# The container must already exist (created by setup.sh).
# Only one model can run per host/port at a time.

source "$(dirname "$0")/common.sh"

ALIAS="${1:?Usage: start.sh ALIAS}"
parse_model "$ALIAS"

echo "Starting model: $ALIAS ($MODEL_ID) on $HOST:$PORT"

# Check host reachable
if ! host_reachable "$HOST"; then
  echo "❌ Host $HOST is unreachable." >&2
  exit 1
fi

# Check container exists
status=$(check_container_status "$HOST" "$CONTAINER")
if [[ "$status" == "not found" || -z "$status" ]]; then
  echo "❌ Container '$CONTAINER' not found on $HOST." >&2
  echo "   Run setup.sh $ALIAS first." >&2
  exit 1
fi

if [[ "$status" == *"Up"* ]]; then
  echo "✅ Already running: $CONTAINER"
  exit 0
fi

# Stop any other model on the same host/port
case "$HOST" in
  rhtevan-work)
    for other in g350m g1b g8b; do
      [[ "$other" == "$ALIAS" ]] && continue
      parse_model "$other"
      other_status=$(check_container_status "$HOST" "$CONTAINER")
      if [[ "$other_status" == *"Up"* ]]; then
        echo "Stopping $CONTAINER (shares port $PORT)..."
        run_on_host "$HOST" "podman stop $CONTAINER" 2>/dev/null
      fi
    done
    ;;
  rhel-ai)
    for other in g8b-128k g30b-96k; do
      [[ "$other" == "$ALIAS" ]] && continue
      parse_model "$other"
      other_status=$(check_container_status "$HOST" "$CONTAINER")
      if [[ "$other_status" == *"Up"* ]]; then
        echo "Stopping $CONTAINER (shares port $PORT)..."
        run_on_host "$HOST" "podman stop $CONTAINER" 2>/dev/null
      fi
    done
    ;;
esac

# Re-parse the target model (parse_model was overwritten in the loop)
parse_model "$ALIAS"

# Start
run_on_host "$HOST" "podman start $CONTAINER"
echo "✅ $CONTAINER started on $HOST"

# Determine wait time
case "$ALIAS" in
  g350m|g1b)   WAIT=30 ;;
  g8b)         WAIT=15 ;;
  g8b-128k)    WAIT=180 ;;
  g30b-96k)    WAIT=1200 ;;
  *)           WAIT=60 ;;
esac

wait_for_model "$HOST" "$PORT" "$WAIT"
