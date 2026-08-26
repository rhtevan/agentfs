#!/usr/bin/env bash
# start.sh — Start a deployment profile
# Usage: bash start.sh PROFILE
# Starts an existing (stopped) container for the given profile.
# Enforces mutual exclusion — stops other profiles on same host/port.

source "$(dirname "$0")/common.sh"

PROFILE="${1:-}"

if [[ -z "$PROFILE" ]]; then
  echo "Usage: start.sh PROFILE" >&2
  echo "" >&2
  list_profiles >&2
  exit 1
fi

parse_profile "$PROFILE"

echo "=== Start: $PROFILE ==="
echo "  $PROFILE_DESC ($PROFILE_SPEED)"
echo "  Host: $PROFILE_HOST"
echo "  Container: $CONTAINER"
echo "  Port: $PORT"
echo

if ! host_reachable "$PROFILE_HOST"; then
  echo "❌ Host $PROFILE_HOST is unreachable." >&2
  exit 1
fi

# Check container exists
status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
if [[ "$status" == "not found" ]]; then
  echo "❌ Container $CONTAINER not found on $PROFILE_HOST." >&2
  echo "   Run: setup.sh $PROFILE" >&2
  exit 1
fi

if [[ "$status" == *"Up"* ]]; then
  echo "✅ $CONTAINER is already running"
else
  # Mutual exclusion: stop other profiles on same host+port
  target_host="$PROFILE_HOST"
  target_port="$PORT"
  for other in "${ALL_PROFILES[@]}"; do
    [[ "$other" == "$PROFILE" ]] && continue
    parse_profile "$other" 2>/dev/null || continue
    [[ "$PROFILE_HOST" != "$target_host" ]] && continue
    [[ "$PORT" != "$target_port" ]] && continue
    other_status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
    if [[ "$other_status" == *"Up"* ]]; then
      echo "  Stopping conflicting $CONTAINER on port $PORT..."
      run_on_host "$PROFILE_HOST" "podman stop $CONTAINER 2>/dev/null" || true
    fi
  done

  # Re-parse our profile (vars were overwritten by loop)
  parse_profile "$PROFILE"
  run_on_host "$PROFILE_HOST" "podman start $CONTAINER"
  echo "✅ $CONTAINER started on $PROFILE_HOST"
fi

set_active_profile "$PROFILE_HOST" "$PROFILE"

case "$PROFILE" in
  g350m-2k)          WAIT=180 ;;
  g3b-16k)           WAIT=60 ;;
  g8b-spec-128k)     WAIT=600 ;;
  g8b-fp8-spec-128k) WAIT=600 ;;
  *)                 WAIT=300 ;;
esac

wait_for_model "$PROFILE_HOST" "$PORT" "$WAIT"
