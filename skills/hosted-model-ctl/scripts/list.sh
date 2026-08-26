#!/usr/bin/env bash
# list.sh — List all deployment profiles and their status
# Usage: bash list.sh

source "$(dirname "$0")/common.sh"

echo "=== Hosted Model Deployment Profiles ==="
echo

# Show active profiles
for host in rhtevan-work rhel-ai; do
  active=$(get_active_profile "$host")
  if [[ -n "$active" ]]; then
    parse_profile "$active" 2>/dev/null || continue
    echo "  $host: 🟢 $active ($PROFILE_DESC — $PROFILE_SPEED)"
  else
    default=$(get_default_profile "$host")
    echo "  $host: ⚪ no active profile (default: $default)"
  fi
done
echo

# List all profiles with container status
for host in rhtevan-work rhel-ai; do
  echo "--- ${host} ---"

  if host_reachable "$host"; then
    host_status="online"
  else
    host_status="unreachable"
    echo "  ⚠️  Host $host is unreachable"
  fi

  printf "  %-22s %-42s %-6s %-15s %s\n" "PROFILE" "MODEL" "PORT" "SPEED" "STATUS"
  printf "  %-22s %-42s %-6s %-15s %s\n" "-------" "-----" "----" "-----" "------"

  for profile in "${ALL_PROFILES[@]}"; do
    parse_profile "$profile" 2>/dev/null || continue
    [[ "$PROFILE_HOST" != "$host" ]] && continue

    if [[ "$host_status" == "unreachable" ]]; then
      icon="⚪"
      status="unknown"
    else
      status=$(check_container_status "$host" "$CONTAINER")
      if [[ "$status" == *"Up"* ]]; then
        icon="🟢"
      elif [[ "$status" == *"Exited"* ]]; then
        icon="🔴"
      elif [[ "$status" == *"Created"* ]]; then
        icon="🟡"
      else
        icon="⚪"
      fi
    fi

    default_marker=""
    [[ "$profile" == "$DEFAULT_PROFILE_RHTEVAN" || "$profile" == "$DEFAULT_PROFILE_RHELAI" ]] && default_marker=" ✅"

    printf "  %-22s %-42s %-6s %-15s %s %s%s\n" "$profile" "$MODEL_ID" "$PORT" "$PROFILE_SPEED" "$icon" "$status" "$default_marker"
  done
  echo
done
