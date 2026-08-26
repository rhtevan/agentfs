#!/usr/bin/env bash
# stop.sh — Stop a deployment profile
# Usage: bash stop.sh PROFILE [--remove]
#    or: bash stop.sh all [--remove]
# --remove: also delete the container after stopping

source "$(dirname "$0")/common.sh"

PROFILE=""
REMOVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove) REMOVE=true; shift ;;
    *)        PROFILE="$1"; shift ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "Usage: stop.sh PROFILE [--remove]" >&2
  echo "   or: stop.sh all [--remove]" >&2
  echo "" >&2
  list_profiles >&2
  exit 1
fi

# ── Stop all ──────────────────────────────────────────────────
if [[ "$PROFILE" == "all" ]]; then
  echo "Stopping all model containers..."
  for p in "${ALL_PROFILES[@]}"; do
    parse_profile "$p" 2>/dev/null || continue
    if ! host_reachable "$PROFILE_HOST"; then
      echo "  ⚠️  $PROFILE_HOST unreachable — skipping $CONTAINER"
      continue
    fi
    status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
    if [[ "$status" == *"Up"* ]]; then
      echo "  Stopping $CONTAINER on $PROFILE_HOST..."
      run_on_host "$PROFILE_HOST" "podman stop $CONTAINER" 2>/dev/null || true
      echo "  ✅ $CONTAINER stopped"
    fi
    if [[ "$REMOVE" == "true" ]]; then
      run_on_host "$PROFILE_HOST" "podman rm -f $CONTAINER 2>/dev/null" || true
      echo "  🗑️  $CONTAINER removed"
    fi
  done
  for host in rhtevan-work rhel-ai; do
    clear_active_profile "$host"
  done
  if [[ "$REMOVE" == "true" ]]; then
    echo "✅ All reachable models stopped and removed"
  else
    echo "✅ All reachable models stopped"
  fi
  exit 0
fi

# ── Stop single profile ──────────────────────────────────────
parse_profile "$PROFILE"

echo "Stopping profile: $PROFILE ($PROFILE_DESC)"
echo "  Host: $PROFILE_HOST"
echo "  Container: $CONTAINER"

if ! host_reachable "$PROFILE_HOST"; then
  echo "❌ Host $PROFILE_HOST is unreachable." >&2
  exit 1
fi

status=$(check_container_status "$PROFILE_HOST" "$CONTAINER")
if [[ "$status" == *"Up"* ]]; then
  run_on_host "$PROFILE_HOST" "podman stop $CONTAINER" 2>/dev/null || true
  echo "✅ $CONTAINER stopped"
else
  echo "⏭️  $CONTAINER not running ($status)"
fi

if [[ "$REMOVE" == "true" ]]; then
  run_on_host "$PROFILE_HOST" "podman rm -f $CONTAINER 2>/dev/null" || true
  echo "🗑️  $CONTAINER removed"
fi

clear_active_profile "$PROFILE_HOST"
echo "✅ Profile '$PROFILE' stopped on $PROFILE_HOST"
