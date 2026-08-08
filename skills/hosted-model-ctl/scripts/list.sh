#!/usr/bin/env bash
# list.sh — List all hosted model containers and their status
# Usage: bash list.sh

source "$(dirname "$0")/common.sh"

echo "=== Hosted Model Status ==="
echo

for host in rhtevan-work rhel-ai; do
  echo "--- ${host} ---"
  case "$host" in
    rhtevan-work)
      aliases=(g350m g1b g8b)
      ;;
    rhel-ai)
      aliases=(g30b-96k g8b-128k)
      ;;
  esac

  # Check host reachability once
  if host_reachable "$host"; then
    host_status="online"
  else
    host_status="unreachable"
    echo "  ⚠️  Host $host is unreachable — showing last known config"
  fi

  printf "  %-12s %-35s %-8s %s\n" "ALIAS" "MODEL" "PORT" "STATUS"
  printf "  %-12s %-35s %-8s %s\n" "-----" "-----" "----" "------"

  for alias in "${aliases[@]}"; do
    parse_model "$alias"
    if [[ "$host_status" == "unreachable" ]]; then
      icon="⚪"
      status="unknown (host unreachable)"
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
    printf "  %-12s %-35s %-8s %s %s\n" "$alias" "$MODEL_ID" "$PORT" "$icon" "$status"
  done
  echo
done
