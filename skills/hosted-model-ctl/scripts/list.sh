#!/usr/bin/env bash
# list.sh — List all deployment profiles and their status
# Usage: bash list.sh [--names-only [HOST]]
#   --names-only         Print profile names only (for script consumption)
#   --names-only HOST    Print profile names for a specific host

source "$(dirname "$0")/common.sh"

# ── --names-only mode ──────────────────────────────────────────
if [[ "${1:-}" == "--names-only" ]]; then
  filter_host="${2:-}"
  for profile in "${ALL_PROFILES[@]}"; do
    if [[ -n "${COMPOSITE_PROFILES[$profile]:-}" ]]; then
      # Composite: resolve host from first sub-profile
      read -ra _subs <<< "${COMPOSITE_PROFILES[$profile]}"
      parse_profile "${_subs[0]}" 2>/dev/null || continue
    else
      parse_profile "$profile" 2>/dev/null || continue
    fi
    if [[ -z "$filter_host" || "$PROFILE_HOST" == "$filter_host" ]]; then
      echo "$profile"
    fi
  done
  exit 0
fi

echo "=== Hosted Model Deployment Profiles ==="
echo

# Show active profiles
for host in rhtevan-work rhel-ai; do
  active=$(get_active_profile "$host")
  if [[ -n "$active" ]]; then
    if [[ -n "${COMPOSITE_PROFILES[$active]:-}" ]]; then
      read -ra _subs <<< "${COMPOSITE_PROFILES[$active]}"
      _desc=""
      for _s in "${_subs[@]}"; do
        parse_profile "$_s" 2>/dev/null && _desc="${_desc:+$_desc + }$MODEL_ID"
      done
      echo "  $host: 🟢 $active (composite: $_desc)"
    else
      parse_profile "$active" 2>/dev/null || continue
      echo "  $host: 🟢 $active ($PROFILE_DESC — $PROFILE_SPEED)"
    fi
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

# Doc alignment check
check_doc_alignment || true
