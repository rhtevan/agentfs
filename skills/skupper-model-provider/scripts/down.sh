#!/usr/bin/env bash
# down.sh — Stop model and optionally Skupper services
# Usage:
#   bash down.sh MODEL_ALIAS       — stop one model container only
#   bash down.sh all                — stop all models + all routers
#   bash down.sh all --keep-van     — stop all models, keep VAN running

source "$(dirname "$0")/common.sh"

ARG="${1:?Usage: down.sh MODEL_ALIAS|all [--keep-van]}"
KEEP_VAN=false
[[ "${2:-}" == "--keep-van" ]] && KEEP_VAN=true

if [[ "$ARG" == "all" ]]; then
  echo "=== Skupper Model Provider — DOWN ALL ==="
  echo

  # Phase 1: Stop all model containers
  echo "Phase 1: Stop model containers"
  for host in rhel-ai rhtevan-work; do
    if ! host_reachable "$host"; then
      echo "  ⚠️  $host unreachable — skip"
      continue
    fi
    # Find and stop model containers
    CONTAINERS=$(run_on_host "$host" "podman ps --filter 'name=model-' --format '{{.Names}}' | grep -v 'skupper-router'" || echo "")
    if [[ -n "$CONTAINERS" ]]; then
      while IFS= read -r container; do
        run_on_host "$host" "podman stop ${container}" 2>/dev/null || true
        echo "  ✅ Stopped $container on $host"
      done <<< "$CONTAINERS"
    else
      echo "  ✅ No model containers running on $host"
    fi
  done
  echo

  if [[ "$KEEP_VAN" == "true" ]]; then
    echo "✅ All models stopped. VAN kept running (--keep-van)."
    exit 0
  fi

  # Phase 2: Stop local router
  echo "Phase 2: Stop local router"
  systemctl --user stop "skupper-${NAMESPACE}.service" 2>/dev/null || true
  echo "  ✅ Local router stopped"
  echo

  # Phase 3: Stop remote routers
  echo "Phase 3: Stop remote routers"
  for host in rhel-ai rhtevan-work; do
    if host_reachable "$host"; then
      run_on_host "$host" "systemctl --user stop skupper-${NAMESPACE}.service 2>/dev/null" || true
      echo "  ✅ $host router stopped"
    else
      echo "  ⚠️  $host unreachable — skip"
    fi
  done
  echo

  # Phase 4: Stop controllers (nothing to manage with all routers down)
  echo "Phase 4: Stop controllers"
  systemctl --user stop skupper-controller.service 2>/dev/null || true
  echo "  ✅ Local controller stopped"
  for host in rhel-ai rhtevan-work; do
    if host_reachable "$host"; then
      run_on_host "$host" "systemctl --user stop skupper-controller.service 2>/dev/null" || true
      echo "  ✅ $host controller stopped"
    else
      echo "  ⚠️  $host unreachable — skip"
    fi
  done
  echo

  # Phase 5: Verify
  echo "Phase 5: Verify"
  LOCAL_PORT_9000=$(ss -tlnp 2>/dev/null | grep -c ':9000' || true)
  LOCAL_PORT_10000=$(ss -tlnp 2>/dev/null | grep -c ':10000' || true)
  echo "  localhost:9000  — ${LOCAL_PORT_9000:-0} listeners"
  echo "  localhost:10000 — ${LOCAL_PORT_10000:-0} listeners"
  echo

  echo "✅ All models and routers stopped."

else
  # Single model mode
  MODEL_ALIAS="$ARG"
  REMOTE_HOST=$(alias_to_host "$MODEL_ALIAS") || exit 1
  MODEL_CONTAINER=$(alias_to_container "$MODEL_ALIAS")
  LOCAL_PORT=$(alias_to_local_port "$MODEL_ALIAS")

  echo "=== Skupper Model Provider — DOWN $MODEL_ALIAS ==="
  echo "  Remote host: $REMOTE_HOST"
  echo "  Container:   $MODEL_CONTAINER"
  echo

  echo "Phase 1: Stop model container"
  if host_reachable "$REMOTE_HOST"; then
    MODEL_STATUS=$(run_on_host "$REMOTE_HOST" "podman ps --filter name=${MODEL_CONTAINER} --format '{{.Status}}'" || echo "")
    if [[ "$MODEL_STATUS" == *"Up"* ]]; then
      run_on_host "$REMOTE_HOST" "podman stop ${MODEL_CONTAINER}" 2>/dev/null || true
      echo "  ✅ Stopped $MODEL_CONTAINER on $REMOTE_HOST"
    else
      echo "  ✅ $MODEL_CONTAINER already stopped"
    fi
  else
    echo "  ⚠️  $REMOTE_HOST unreachable — cannot stop container"
  fi
  echo

  echo "Note: VAN infrastructure (routers, links) left running."
  echo "      Use 'down.sh all' to stop everything."
  echo
  echo "✅ Model $MODEL_ALIAS stopped."
fi
