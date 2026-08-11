#!/usr/bin/env bash
# status.sh — Check Skupper VAN and model status
# Usage: bash status.sh [MODEL_ALIAS]
#   No alias: full status of all components
#   With alias: status of specific model path

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:-}"

echo "=== Skupper Model Provider Status ==="
echo

# ── Local Router ──────────────────────────────────────────────
echo "--- Local Router ---"
LOCAL_STATUS=$(check_router_status "localhost")
if [[ "$LOCAL_STATUS" == *"Up"* ]]; then
  echo "  🟢 Router: $LOCAL_STATUS"
  
  # Check established connections
  ESTAB_RTW=$(ss -tnp 2>/dev/null | grep '55671' | grep -c ESTAB 2>/dev/null || true)
  ESTAB_RTW=${ESTAB_RTW:-0}
  ESTAB_RAI=$(ss -tnp 2>/dev/null | grep '8000' | grep -c ESTAB 2>/dev/null || true)
  ESTAB_RAI=${ESTAB_RAI:-0}
  
  [[ "$ESTAB_RTW" -gt 0 ]] && echo "  🟢 Link rhtevan-work: $ESTAB_RTW connections" || echo "  🔴 Link rhtevan-work: not connected"
  [[ "$ESTAB_RAI" -gt 0 ]] && echo "  🟢 Link rhel-ai: $ESTAB_RAI connections" || echo "  🔴 Link rhel-ai: not connected"
  
  # Check listener ports
  PORT_10000=$(ss -tlnp 2>/dev/null | grep ':10000' | grep -c LISTEN 2>/dev/null || true)
  PORT_10000=${PORT_10000:-0}
  PORT_9000=$(ss -tlnp 2>/dev/null | grep ':9000' | grep -c LISTEN 2>/dev/null || true)
  PORT_9000=${PORT_9000:-0}
  
  [[ "$PORT_10000" -gt 0 ]] && echo "  🟢 Listener :10000 (model-api-rhtevan-work)" || echo "  🔴 Listener :10000 not open"
  [[ "$PORT_9000" -gt 0 ]]  && echo "  🟢 Listener :9000 (model-api-rhel-ai)" || echo "  🔴 Listener :9000 not open"
else
  echo "  🔴 Router: $LOCAL_STATUS"
fi
echo

# ── Remote Hubs ───────────────────────────────────────────────
for host in rhtevan-work rhel-ai; do
  echo "--- $host Hub ---"
  
  if ! host_reachable "$host"; then
    echo "  ⚠️  Host unreachable"
    echo
    continue
  fi
  
  ROUTER_STATUS=$(check_router_status "$host")
  if [[ "$ROUTER_STATUS" == *"Up"* ]]; then
    echo "  🟢 Router: $ROUTER_STATUS"
    
    IFS='|' read -r _ ir_port _ routing_key model_port <<< "${SITE_PROFILES[$host]}"
    
    # Check listening ports
    LISTENING=$(run_on_host "$host" "ss -tlnp | grep ${ir_port} | grep -c LISTEN" || echo "0")
    [[ "$LISTENING" -gt 0 ]] && echo "  🟢 Inter-router port $ir_port listening" || echo "  🔴 Port $ir_port not listening"
  else
    echo "  🔴 Router: $ROUTER_STATUS"
  fi
  echo
done

# ── Models ────────────────────────────────────────────────────
echo "--- Models ---"

if [[ -n "$MODEL_ALIAS" ]]; then
  # Specific model
  aliases=("$MODEL_ALIAS")
else
  # All models
  aliases=(g350m g1b g8b g30b-96k g8b-128k)
fi

for alias in "${aliases[@]}"; do
  host=$(alias_to_host "$alias") || continue
  container=$(alias_to_container "$alias")
  local_port=$(alias_to_local_port "$alias")
  
  if ! host_reachable "$host"; then
    printf "  %-12s %-12s %-6s %s\n" "$alias" "$host" "$local_port" "⚪ unknown (host unreachable)"
    continue
  fi
  
  status=$(run_on_host "$host" "podman ps -a --filter name=${container} --format '{{.Status}}'" || echo "not found")
  if [[ "$status" == *"Up"* ]]; then
    icon="🟢"
    # Check API
    code=$(run_on_host "$host" "curl -s -o /dev/null -w '%{http_code}' http://localhost:$(alias_to_local_port "$alias" | sed 's/10000/10000/;s/9000/9000/')" 2>/dev/null || echo "000")
    IFS='|' read -r _ _ _ _ model_port <<< "${SITE_PROFILES[$host]}"
    code=$(run_on_host "$host" "curl -s -o /dev/null -w '%{http_code}' http://localhost:${model_port}/v1/models" 2>/dev/null || echo "000")
    [[ "$code" == "200" ]] && status="$status (API: HTTP 200)" || status="$status (API: HTTP $code)"
  elif [[ "$status" == *"Exited"* ]]; then
    icon="🔴"
  else
    icon="⚪"
  fi
  printf "  %-12s %-12s %-6s %s %s\n" "$alias" "$host" "$local_port" "$icon" "$status"
done
echo

# ── End-to-End ────────────────────────────────────────────────
echo "--- End-to-End ---"
for port in 10000 9000; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${port}/v1/models" 2>/dev/null || echo "000")
  if [[ "$code" == "200" ]]; then
    model_id=$(curl -s "http://localhost:${port}/v1/models" | \
      python3 -c "import json,sys; print(json.load(sys.stdin)['data'][0]['id'])" 2>/dev/null || echo "unknown")
    echo "  🟢 localhost:${port} → $model_id"
  else
    echo "  🔴 localhost:${port} → HTTP $code"
  fi
done
