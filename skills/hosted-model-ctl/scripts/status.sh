#!/usr/bin/env bash
# status.sh — Show status of deployment profiles
# Usage: bash status.sh [PROFILE]
# Without arguments: shows all profiles.
# With PROFILE: shows detailed status + recent logs.

source "$(dirname "$0")/common.sh"

PROFILE="${1:-}"

if [[ -z "$PROFILE" ]]; then
  # Show all profiles
  bash "$(dirname "$0")/list.sh"
  exit 0
fi

# Detailed status for a specific profile
parse_profile "$PROFILE"

echo "=== Status: $PROFILE ==="
echo "  Description: $PROFILE_DESC"
echo "  Speed:       $PROFILE_SPEED"
echo "  Host:        $PROFILE_HOST"
echo "  Container:   $CONTAINER"
echo "  Model:       $MODEL_ID"
echo "  Engine:      $ENGINE"
echo "  Port:        $PORT"
echo "  TP:          $TP"
echo "  Context:     $CONTEXT"
echo

if ! host_reachable "$PROFILE_HOST"; then
  echo "❌ Host $PROFILE_HOST is unreachable."
  exit 1
fi

# Container status
status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
if [[ "$status" == *"Up"* ]]; then
  echo "Container: 🟢 $status"
elif [[ "$status" == *"Exited"* ]]; then
  echo "Container: 🔴 $status"
else
  echo "Container: ⚪ $status"
fi

# Active profile
active=$(get_active_profile "$PROFILE_HOST")
if [[ "$active" == "$PROFILE" ]]; then
  echo "Profile:   🟢 active"
else
  echo "Profile:   ⚪ not active (active: ${active:-none})"
fi

# API check
if [[ "$status" == *"Up"* ]]; then
  code=$(run_on_host "$PROFILE_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT}/v1/models 2>/dev/null" || echo "000")
  if [[ "$code" == "200" ]]; then
    model_id=$(run_on_host "$PROFILE_HOST" "curl -s http://localhost:${PORT}/v1/models 2>/dev/null" | jq -r '.data[0].id' 2>/dev/null)
    echo "API:       ✅ HTTP $code — serving $model_id"
  else
    echo "API:       ❌ HTTP $code"
  fi
fi

# Recent logs
echo
echo "--- Recent Logs (last 10 lines) ---"
run_on_host "$PROFILE_HOST" "podman logs $CONTAINER 2>&1 | tail -10" || echo "(no logs available)"
