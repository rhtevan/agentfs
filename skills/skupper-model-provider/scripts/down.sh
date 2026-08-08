#!/usr/bin/env bash
# down.sh — Tear down Skupper VAN and stop model
# Usage: bash down.sh [MODEL_ALIAS]
#   With alias: stop specific model and its skupper link
#   No alias:   stop all models and all skupper components

source "$(dirname "$0")/common.sh"

MODEL_ALIAS="${1:-all}"

if [[ "$MODEL_ALIAS" == "all" ]]; then
  echo "=== Skupper Model Provider — DOWN (all) ==="
  echo

  # Phase 1: Stop all model containers
  echo "Phase 1: Stop model containers"
  for alias in g350m g1b g8b g8b-128k g30b-96k; do
    host=$(alias_to_host "$alias") || continue
    container=$(alias_to_container "$alias")
    if ! host_reachable "$host"; then
      echo "  ⚠️  $host unreachable — skipping $container"
      continue
    fi
    status=$(run_on_host "$host" "podman ps --filter name=${container} --format '{{.Status}}'" || echo "")
    if [[ "$status" == *"Up"* ]]; then
      echo "  Stopping $container on $host..."
      run_on_host "$host" "podman stop ${container}" || true
      echo "  ✅ $container stopped"
    fi
  done
  echo

  # Phase 2: Stop local router
  echo "Phase 2: Stop local router"
  LOCAL_STATUS=$(podman ps --filter name=${ROUTER_CONTAINER} --format '{{.Status}}' 2>/dev/null || echo "")
  if [[ "$LOCAL_STATUS" == *"Up"* ]]; then
    podman stop "${ROUTER_CONTAINER}" 2>/dev/null || true
    echo "  ✅ Local router stopped"
  else
    echo "  Local router not running"
  fi
  echo

  # Phase 3: Stop remote routers
  echo "Phase 3: Stop remote routers"
  for host in rhtevan-work rhel-ai; do
    if ! host_reachable "$host"; then
      echo "  ⚠️  $host unreachable — skipping"
      continue
    fi
    status=$(run_on_host "$host" "podman ps --filter name=${ROUTER_CONTAINER} --format '{{.Status}}'" || echo "")
    if [[ "$status" == *"Up"* ]]; then
      run_on_host "$host" "podman stop ${ROUTER_CONTAINER}" || true
      echo "  ✅ $host router stopped"
    else
      echo "  $host router not running"
    fi
  done
  echo

  # Phase 4: Verify
  echo "Phase 4: Verify"
  ss -tlnp 2>/dev/null | grep -E '9000|10000' && echo "  ⚠️  Ports still listening" || echo "  ✅ All local ports clear"
  echo
  echo "✅ Skupper Model Provider DOWN (all)"

else
  # Single model shutdown
  REMOTE_HOST=$(alias_to_host "$MODEL_ALIAS") || exit 1
  LOCAL_PORT=$(alias_to_local_port "$MODEL_ALIAS")
  MODEL_CONTAINER=$(alias_to_container "$MODEL_ALIAS")

  echo "=== Skupper Model Provider — DOWN ($MODEL_ALIAS) ==="
  echo "  Remote host:    $REMOTE_HOST"
  echo "  Container:      $MODEL_CONTAINER"
  echo "  Local listener: localhost:$LOCAL_PORT"
  echo

  # Stop model container
  echo "Phase 1: Stop model container"
  if ! host_reachable "$REMOTE_HOST"; then
    echo "  ⚠️  $REMOTE_HOST unreachable — cannot stop model"
  else
    status=$(run_on_host "$REMOTE_HOST" "podman ps --filter name=${MODEL_CONTAINER} --format '{{.Status}}'" || echo "")
    if [[ "$status" == *"Up"* ]]; then
      run_on_host "$REMOTE_HOST" "podman stop ${MODEL_CONTAINER}" || true
      echo "  ✅ $MODEL_CONTAINER stopped on $REMOTE_HOST"
    else
      echo "  $MODEL_CONTAINER not running ($status)"
    fi
  fi
  echo

  echo "✅ Skupper Model Provider DOWN ($MODEL_ALIAS)"
  echo "Note: Skupper routers left running. Use 'down.sh all' to stop everything."
fi
